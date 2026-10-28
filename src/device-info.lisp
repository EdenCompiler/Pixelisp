;;;; Joystick identity and SDL game-controller event metadata.
;;;; These functions complement the handle-based device operations in devices.lisp.

(in-package #:pixelisp.joystick)

;; SDL returns the GUID as sixteen bytes by value. Format its bytes in Lisp
;; to avoid a second struct-by-value round trip through the native formatter.
(cffi:defcstruct %guid
  (data (:array :uint8 16)))

(cffi:defcfun ("SDL_JoystickGetGUID" %get-guid) (:struct %guid)
  (joystick :pointer))
(cffi:defcfun ("SDL_JoystickCurrentPowerLevel" %current-power-level) :int
  (joystick :pointer))

(defun get-guid (object)
  "Return OBJECT's hardware identifier as SDL's 32-character GUID string."
  (let* ((guid (%get-guid (%attached-pointer object 'get-guid)))
         (bytes (getf guid 'data)))
    (string-downcase (format nil "~{~2,'0X~}" (coerce bytes 'list)))))

(defparameter *power-levels*
  #(:empty :low :medium :full :wired))

(defun get-power-level (object)
  "Return OBJECT's SDL power level as a keyword, including :UNKNOWN."
  (let ((level (%current-power-level (%attached-pointer object 'get-power-level))))
    (if (<= 0 level (1- (length *power-levels*)))
        (aref *power-levels* level)
        :unknown)))

(in-package #:pixelisp.controller)

(cffi:defcfun ("SDL_GameControllerEventState" %event-state) :int
  (state :int))
(cffi:defcfun ("SDL_GameControllerNameForIndex" %name-for-index) :pointer
  (index :int))

(defun get-eventstate ()
  "Return true when SDL will post game-controller events."
  (unless (get-init) (init))
  ;; SDL uses -1 as a query that leaves the current state unchanged.
  (plusp (%event-state -1)))

(defun set-eventstate (enabled)
  "Enable or disable SDL game-controller events using a boolean value."
  (check-type enabled boolean)
  (unless (get-init) (init))
  (%event-state (if enabled 1 0))
  nil)

(defun name-for-index (index)
  "Return a controller's system name, or NIL when INDEX has no name."
  (check-type index (integer 0 *))
  (unless (get-init) (init))
  (let ((name (%name-for-index index)))
    (unless (cffi:null-pointer-p name)
      (cffi:foreign-string-to-lisp name :encoding :utf-8))))
