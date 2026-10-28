;;;; SDL window operations with backend-dependent focus and modal behavior.
;;;; Relative mouse mode is SDL-global, despite the window-shaped property API.
(in-package #:pixelisp.sdl2.video)

(cffi:defcfun ("SDL_SetWindowModalFor" %window-modal-for) :int
  (window :pointer) (parent :pointer))
(cffi:defcfun ("SDL_SetWindowInputFocus" %window-input-focus) :int
  (window :pointer))
(cffi:defcfun ("SDL_SetRelativeMouseMode" %relative-mouse-set) :int
  (enabled :int))
(cffi:defcfun ("SDL_GetRelativeMouseMode" %relative-mouse-get) :int)

(defun %window-capability-error (operation)
  (error 'pixelisp:unsupported-feature :operation operation
         :message (format nil "SDL could not perform this window operation: ~A"
                          (cffi:foreign-funcall "SDL_GetError" :string))))

(defun set-modal-for (window parent)
  "Set WINDOW as a modal child of PARENT; SDL supports this on X11 only."
  ;; Validate both Lisp objects and the video thread before resolving either
  ;; native handle, so a wrong-kind or cross-thread call never reaches SDL.
  (check-type window window)
  (check-type parent window)
  (pixelisp.internal:check-video-thread)
  (pixelisp.internal:ensure-live window)
  (pixelisp.internal:ensure-live parent)
  (when (eq window parent)
    (error "A window cannot be modal for itself."))
  (pixelisp.internal:with-native-context
    (let ((window-pointer (%pointer window))
          (parent-pointer (%pointer parent)))
      (when (minusp (%window-modal-for window-pointer parent-pointer))
        (%window-capability-error 'set-modal-for))))
  window)

(defun window-relative-mouse-p (window)
  "Return SDL's process-wide relative mouse mode after validating WINDOW."
  (check-type window window)
  (pixelisp.internal:with-native-context
    (%pointer window)
    (not (zerop (%relative-mouse-get)))))

(defun (setf window-relative-mouse-p) (enabled window)
  "Set SDL's process-wide relative mouse mode; SDL does not track it per window."
  (check-type enabled boolean)
  (check-type window window)
  (pixelisp.internal:with-native-context
    (%pointer window)
    (when (minusp (%relative-mouse-set (if enabled 1 0)))
      (%window-capability-error 'window-relative-mouse-p)))
  enabled)

(defun focus-window (window &key (input-only nil))
  "Raise WINDOW and request input focus, or request input focus alone.
When INPUT-ONLY is true SDL may focus a completely obscured window; backend
support varies and SDL errors are reported as unsupported-feature."
  (check-type window window)
  (check-type input-only boolean)
  (pixelisp.internal:with-native-context
    (let ((pointer (%pointer window)))
      (if input-only
          (when (minusp (%window-input-focus pointer))
            (%window-capability-error 'focus-window))
          (%wt-focus pointer))))
  window)
