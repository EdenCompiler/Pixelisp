;;;; SDL virtual controllers exercise handle bridges and editable mappings.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(cffi:defcfun ("SDL_JoystickAttachVirtual" %controller-attach-virtual) :int
  (type :int) (axes :int) (buttons :int) (hats :int))
(cffi:defcfun ("SDL_JoystickDetachVirtual" %controller-detach-virtual) :int
  (index :int))
(cffi:defcfun ("SDL_JoystickSetVirtualAxis" %controller-set-axis) :int
  (joystick :pointer) (axis :int) (value :int16))
(cffi:defcfun ("SDL_JoystickSetVirtualButton" %controller-set-button) :int
  (joystick :pointer) (button :int) (value :uint8))
(cffi:defcfun ("SDL_GameControllerFromInstanceID" %controller-from-id) :pointer
  (instance-id :int32))
(cffi:defcfun ("SDL_JoystickFromInstanceID" %joystick-from-id) :pointer
  (instance-id :int32))

(defun %attach-mapped-virtual-controller ()
  "Attach an SDL virtual pad with the conventional Xbox mapping."
  (px.joystick:init)
  (let ((index (%controller-attach-virtual 1 6 21 1)))
    (when (minusp index)
      (error 'pixelisp:error :operation 'attach-virtual-controller
             :message (cffi:foreign-funcall "SDL_GetError" :string)))
    (let ((complete nil))
      (unwind-protect
           (let ((joystick (px.joystick:open-joystick index)))
             (unwind-protect
                  (let* ((guid (px.joystick:get-guid joystick))
                         (mapping (format nil "~A,Pixelisp Virtual Pad,a:b0,b:b1,x:b2,y:b3,~
                                           leftx:a0,lefty:a1,rightx:a2,righty:a3,~
                                           lefttrigger:a4,righttrigger:a5,platform:Linux" guid)))
                    (px.controller:add-mapping mapping)
                    (setf complete t)
                    index)
               (px.joystick:close joystick)))
        (unless complete (ignore-errors (%controller-detach-virtual index)))))))

(defun %copy-equal-hash (table)
  (let ((copy (make-hash-table :test 'equal)))
    (maphash (lambda (key value) (setf (gethash key copy) value)) table)
    copy))

(test controller-bridges-open-independent-handles-and-resolve-current-index
  (px.joystick:init)
  (let ((lower (%controller-attach-virtual 0 0 0 0))
        (lower-detached nil) (target nil) (target-id nil)
        (joystick nil) (controller nil) (other-joystick nil))
    (unwind-protect
         (progn
           (setf target (%attach-mapped-virtual-controller)
                 joystick (px.joystick:open-joystick target)
                 target-id (px.joystick:instance-id joystick))
           ;; Removing a lower index shifts enumeration but not the open ID.
           (is (not (minusp lower)))
           (%controller-detach-virtual lower)
           (setf lower-detached t)
           (setf controller (px.controller:from-joystick joystick))
           (is (= (px.joystick:instance-id joystick)
                  (px.controller:instance-id controller)))
           (%controller-set-button (pixelisp.internal:handle joystick) 0 1)
           (%controller-set-axis (pixelisp.internal:handle joystick) 0 16384)
           (px.joystick:update)
           (is (px.controller:get-button controller :a))
           (is (> (px.controller:get-axis controller :left-x) 0.49))
           (px.joystick:close joystick)
           (is (px.controller:attached-p controller))
           (setf other-joystick (px.controller:as-joystick controller))
           (px.controller:close controller)
           (is (px.joystick:attached-p other-joystick))
           (is (px.joystick:get-button other-joystick 0)))
      (when joystick (px:dispose joystick))
      (when controller (px:dispose controller))
      (when other-joystick (px:dispose other-joystick))
      (when target-id
        (let ((current (px.joystick::%index-for-instance-id target-id)))
          (when current (%controller-detach-virtual current))))
      (unless lower-detached
        (let ((count (px.joystick:get-count)))
          (when (and (integerp lower) (<= 0 lower) (< lower count))
            (ignore-errors (%controller-detach-virtual lower))))))))

(test controller-mapping-hash-roundtrip-is-defensive-and-preserves-metadata
  (let* ((index (%attach-mapped-virtual-controller))
         (joystick (px.joystick:open-joystick index))
         (controller nil))
    (unwind-protect
         (progn
           (setf controller (px.controller:from-joystick joystick))
           (let* ((mapping (px.controller:get-mapping controller))
                  (copy (%copy-equal-hash mapping)))
             (is (not (nth-value 1 (gethash "guid" mapping))))
             (is (not (nth-value 1 (gethash "name" mapping))))
             (is (string= "Linux" (gethash "platform" mapping)))
             (setf (gethash "a" mapping) "b1")
             (is (member (px.controller:set-mapping controller mapping) '(0 1)))
             (is (string= "b1" (gethash "a" (px.controller:get-mapping controller))))
             (is (string= "Linux" (gethash "platform" (px.controller:get-mapping controller))))
             ;; Returned hashes are detached from SDL and from later reads.
             (is (string= "b0" (gethash "a" copy)))
             (setf (gethash "a" mapping) "b0,b1")
             (signals error
               (px.controller:set-mapping controller mapping))
             (setf (gethash "a" mapping) "b1"
                   (gethash "guid" mapping) "forged-guid")
             (signals error
               (px.controller:set-mapping controller mapping))
             (is (string= "b1" (gethash "a" (px.controller:get-mapping controller))))))
      (when controller (px:dispose controller))
      (when joystick (px:dispose joystick))
      (let ((count (px.joystick:get-count)))
        (when (and (integerp index) (<= 0 index) (< index count))
          (%controller-detach-virtual index))))))

(test joystick-controller-bridges-reject-wrong-closed-and-detached-handles
  (let* ((index (%attach-mapped-virtual-controller))
         (joystick (px.joystick:open-joystick index))
         (controller (px.controller:from-joystick joystick))
         (detached nil))
    (unwind-protect
         (progn
           (signals error (px.controller:from-joystick controller))
           (signals error (px.controller:as-joystick joystick))
           (px.joystick:close joystick)
           (signals px:disposed-resource (px.controller:from-joystick joystick))
           (%controller-detach-virtual index)
           (setf detached t)
           (is (not (px.controller:attached-p controller)))
           (signals px:error (px.controller:get-button controller :a))
           (signals px:error (px.controller:as-joystick controller)))
      (px:dispose joystick)
      (px:dispose controller)
      (unless detached
        (let ((count (px.joystick:get-count)))
          (when (and (integerp index) (<= 0 index) (< index count))
            (ignore-errors (%controller-detach-virtual index))))))))

(test controller-bridge-registration-failures-close-the-new-native-handle
  (let* ((index (%attach-mapped-virtual-controller))
         (joystick (px.joystick:open-joystick index))
         (instance-id (px.joystick:instance-id joystick))
         (controller nil)
         (register-symbol 'pixelisp.internal:register-resource)
         (real-register (symbol-function register-symbol)))
    (unwind-protect
         (progn
           (setf (symbol-function register-symbol)
                 (lambda (&rest arguments)
                   (declare (ignore arguments))
                   (error "Injected resource-registration failure.")))
           (signals error (px.controller:from-joystick joystick))
           (is (cffi:null-pointer-p (%controller-from-id instance-id)))
           (setf (symbol-function register-symbol) real-register
                 controller (px.controller:from-joystick joystick))
           ;; The controller keeps the device open while the original joystick
           ;; handle is closed; a failed reverse bridge must add no extra ref.
           (px.joystick:close joystick)
           (setf (symbol-function register-symbol)
                 (lambda (&rest arguments)
                   (declare (ignore arguments))
                   (error "Injected resource-registration failure.")))
           (signals error (px.controller:as-joystick controller))
           (setf (symbol-function register-symbol) real-register)
           (px.controller:close controller)
           (setf controller nil)
           (is (cffi:null-pointer-p (%joystick-from-id instance-id))))
      (setf (symbol-function register-symbol) real-register)
      (when joystick (px:dispose joystick))
      (when controller (px:dispose controller))
      (let ((current (px.joystick::%index-for-instance-id instance-id)))
        (when current (%controller-detach-virtual current))))))

(test joystick-and-controller-quit-dispose-only-their-own-live-resources
  (let* ((index (%attach-mapped-virtual-controller))
         (joystick (px.joystick:open-joystick index))
         (instance-id (px.joystick:instance-id joystick))
         (controller (px.controller:from-joystick joystick)))
    (unwind-protect
         (progn
           (px.joystick:quit)
           (px.joystick:quit)
           (signals px:disposed-resource (px.joystick:instance-id joystick))
           (is (px.controller:attached-p controller))
           (px.joystick:init)
           (is (px.joystick:get-init))
           (px.controller:quit)
           (px.controller:quit)
           (signals px:disposed-resource (px.controller:instance-id controller))
           (px.controller:init)
           (is (px.controller:get-init)))
      (px:dispose joystick)
      (px:dispose controller)
      (let ((current (px.joystick::%index-for-instance-id instance-id)))
        (when current (%controller-detach-virtual current))))))
