;;;; Independent joystick/controller bridges and mapping hash operations.
(in-package #:pixelisp.joystick)

(cffi:defcfun ("SDL_JoystickGetDeviceInstanceID" %device-instance-id) :int32
  (index :int))

(defun %index-for-instance-id (instance-id)
  "Resolve a stable opened-device ID to its current enumeration index."
  (loop with count = (get-count)
        for index below count
        when (= (%device-instance-id index) instance-id)
          do (return index)
        finally (return nil)))

(in-package #:pixelisp.controller)

(defun %open-instance-controller (instance-id)
  (unless (get-init) (init))
  (let ((index (px.joystick::%index-for-instance-id instance-id)))
    (unless (and index (controller-p index))
      (error 'pixelisp:error :operation 'from-joystick
             :message "This joystick has no current game-controller mapping."))
    (let ((object (open-controller index)) (complete nil))
      (unwind-protect
           (progn
             ;; A hotplug between lookup and open can reuse the old index.
             (unless (= instance-id (instance-id object))
               (error 'pixelisp:error :operation 'from-joystick
                      :message "The joystick changed while opening its controller."))
             (setf complete t)
             object)
        (unless complete (close object))))))

(defun from-joystick (joystick)
  "Open an independent controller handle for JOYSTICK's current instance."
  (px.joystick::%attached-pointer joystick 'from-joystick)
  (let ((instance-id (px.joystick:instance-id joystick)))
    (%open-instance-controller instance-id)))

(defun as-joystick (controller)
  "Open an independent joystick handle for CONTROLLER's current instance."
  (%attached-pointer controller 'as-joystick)
  (let* ((instance-id (instance-id controller))
         (index (px.joystick::%index-for-instance-id instance-id)))
    (unless index
      (error 'pixelisp:error :operation 'as-joystick :message "Controller is detached."))
    (let ((object (px.joystick:open-joystick index)) (complete nil))
      (unwind-protect
           (progn
             (unless (= instance-id (px.joystick::instance-id object))
               (error 'pixelisp:error :operation 'as-joystick
                      :message "The controller changed while opening its joystick."))
             (setf complete t)
             object)
        (unless complete (px.joystick:close object))))))

(defun %split-string (string delimiter)
  (loop with start = 0
        for end = (position delimiter string :start start)
        collect (subseq string start end)
        while end
        do (setf start (1+ end))))

(defun %parse-mapping (string)
  "Convert SDL's GUID,name,key:value mapping line to a fresh equal hash."
  (let* ((fields (%split-string string #\,))
         (table (make-hash-table :test 'equal)))
    (unless (>= (length fields) 2)
      (error 'pixelisp:error :operation 'get-mapping :message "SDL returned a malformed mapping."))
    (setf (gethash "guid" table) (first fields)
          (gethash "name" table) (second fields))
    (dolist (field (cddr fields))
      (let ((separator (position #\: field)))
        (when (and separator (plusp separator) (< separator (1- (length field))))
          (setf (gethash (subseq field 0 separator) table)
                (subseq field (1+ separator))))))
    table))

(defun get-mapping (controller)
  "Return a fresh equal hash of SDL bindings and metadata, without GUID/name."
  (let ((table (%parse-mapping (mapping controller))))
    ;; SDL's raw line starts with a GUID and human-readable name; pygame's
    ;; mapping dictionary contains the binding/metadata fields only.
    (remhash "guid" table)
    (remhash "name" table)
    table))

(defun %validate-mapping-hash (table)
  (unless (hash-table-p table) (error 'type-error :datum table :expected-type 'hash-table))
  ;; Validate the entire user table before reading or changing SDL mappings.
  (maphash
   (lambda (key value)
     (when (member key '("guid" "name") :test #'string=)
       (error "Do not include SDL's GUID/name header fields in the mapping hash."))
     (dolist (entry (list key value))
       (unless (stringp entry)
         (error 'type-error :datum entry :expected-type 'string))
       (unless (and (plusp (length entry))
                    (notany (lambda (character)
                              (find character '(#\Nul #\, #\:))) entry))
         (error "Mapping strings must be nonempty and contain no NUL, comma, or colon: ~S"
                entry))))
   table)
  table)

(defun set-mapping (controller table)
  "Update this controller's SDL mapping from a fresh string-keyed hash.

GUID and device name always come from the controller's existing SDL mapping.
TABLE contains binding and metadata strings, as returned by GET-MAPPING; the
GUID/name header keys are not accepted. Current fields, including metadata
such as PLATFORM, are retained unless replaced by TABLE. Return SDL's
1-new / 0-updated result."
  (%validate-mapping-hash table)
  (let* ((pointer (%attached-pointer controller 'set-mapping))
         (current (%parse-mapping (mapping controller)))
         (merged (make-hash-table :test 'equal)))
    (maphash (lambda (key value) (setf (gethash key merged) value)) current)
    (maphash (lambda (key value) (setf (gethash key merged) value)) table)
    (let ((guid (gethash "guid" current))
          (name (gethash "name" current)))
      (unless (and guid name)
        (error 'pixelisp:error :operation 'set-mapping :message "SDL mapping lacks GUID or device name."))
      (let* ((keys (sort (loop for key being the hash-keys of merged
                               unless (member key '("guid" "name") :test #'string=)
                                 collect key)
                         #'string<))
             (text (with-output-to-string (stream)
                     (format stream "~A,~A" guid name)
                     (dolist (key keys)
                       (format stream ",~A:~A" key (gethash key merged)))))
             (result (pixelisp.devices.internal:check-code (%mapping-add text) 'set-mapping)))
        (unless (member result '(0 1))
          (error 'pixelisp:error :operation 'set-mapping
                 :message (format nil "Unexpected SDL mapping result ~D." result)))
        result))))
