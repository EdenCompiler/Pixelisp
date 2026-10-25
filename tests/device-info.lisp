(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test joystick-info-rejects-other-handle-types
  ;; Reject a non-joystick before passing its unrelated pointer to SDL.
  (let ((resource (make-instance 'pixelisp.internal:resource)))
    (signals type-error (px.joystick:get-guid resource))
    (signals type-error (px.joystick:get-power-level resource))))

(test virtual-device-identity-and-controller-event-state
  ;; Reuse the virtual-device bindings from devices.lisp. The controller
  ;; subsystem initializes lazily when these module-level queries are used.
  (px.joystick:init)
  (let ((index (%attach-virtual 1 2 4 1))
        (joystick nil)
        (old-event-state nil))
    (is (not (minusp index)))
    (unwind-protect
         (progn
           (setf joystick (px.joystick:open-joystick index))
           (let ((guid (px.joystick:get-guid joystick)))
             (is (= 32 (length guid)))
             (is (every (lambda (character)
                          (or (digit-char-p character 16)
                              (find (char-downcase character) "abcdef")))
                        guid)))
           (is (member (px.joystick:get-power-level joystick)
                       '(:unknown :empty :low :medium :full :wired)))

           (setf old-event-state (px.controller:get-eventstate))
           (let ((joystick-event-state
                   (cffi:foreign-funcall "SDL_JoystickEventState" :int -1 :int)))
             (unwind-protect
                  (progn
                    (px.controller:set-eventstate (not old-event-state))
                    (is (eq (not old-event-state) (px.controller:get-eventstate)))
                    ;; Turning off mapped-controller events leaves joystick
                    ;; events available to applications using both interfaces.
                    (is (= joystick-event-state
                           (cffi:foreign-funcall "SDL_JoystickEventState" :int -1 :int))))
               (px.controller:set-eventstate old-event-state)))
           (is (eq old-event-state (px.controller:get-eventstate)))

           (is (null (px.controller:name-for-index
                      (1+ (px.controller:get-count)))))
           (px:dispose joystick)
           (signals px:disposed-resource (px.joystick:get-guid joystick))
           (signals px:disposed-resource (px.joystick:get-power-level joystick)))
      (when joystick (px:dispose joystick))
      (%detach-virtual index))))
