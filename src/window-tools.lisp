;;;; Window controls that complement the core window creation and size API.
;;;; Each entry point validates ownership/thread state through %POINTER before
;;;; it calls SDL, and native operations that can fail report SDL's error.
(in-package #:pixelisp.sdl2.video)

(cffi:defcfun ("SDL_GetWindowID" %wt-id) :uint32 (window :pointer))
(cffi:defcfun ("SDL_GetWindowDisplayIndex" %wt-display-index) :int (window :pointer))
(cffi:defcfun ("SDL_GetWindowFlags" %wt-flags) :uint32 (window :pointer))
(cffi:defcfun ("SDL_SetWindowResizable" %wt-set-resizable) :void (window :pointer) (enabled :int))
(cffi:defcfun ("SDL_SetWindowBordered" %wt-set-bordered) :void (window :pointer) (enabled :int))
(cffi:defcfun ("SDL_GetWindowOpacity" %wt-get-opacity) :int (window :pointer) (opacity :pointer))
(cffi:defcfun ("SDL_SetWindowOpacity" %wt-set-opacity) :int (window :pointer) (opacity :float))
(cffi:defcfun ("SDL_SetWindowFullscreen" %wt-fullscreen) :int (window :pointer) (flags :uint32))
(cffi:defcfun ("SDL_MaximizeWindow" %wt-maximize) :void (window :pointer))
(cffi:defcfun ("SDL_MinimizeWindow" %wt-minimize) :void (window :pointer))
(cffi:defcfun ("SDL_RestoreWindow" %wt-restore) :void (window :pointer))
(cffi:defcfun ("SDL_RaiseWindow" %wt-focus) :void (window :pointer))
(cffi:defcfun ("SDL_SetWindowGrab" %wt-set-grab) :void (window :pointer) (enabled :int))
(cffi:defcfun ("SDL_GetWindowGrab" %wt-get-grab) :int (window :pointer))
(cffi:defcfun ("SDL_SetWindowIcon" %wt-set-icon) :void (window :pointer) (surface :pointer))

(defun %wt-pointer (window)
  "Validate the resource kind before resolving its native window handle."
  (check-type window window)
  (%pointer window))

(defun window-id (window)
  "Return SDL's unique integer identifier for WINDOW."
  (pixelisp.internal:with-native-context (%wt-id (%wt-pointer window))))

(defun window-display-index (window)
  "Return the display index currently containing WINDOW."
  (pixelisp.internal:with-native-context
    (let ((index (%wt-display-index (%wt-pointer window))))
      (when (minusp index) (pixelisp.internal:native-error 'window-display-index))
      index)))

(defun window-resizable-p (window)
  "Return whether WINDOW can be resized by the window manager."
  (pixelisp.internal:with-native-context
    (logbitp 5 (%wt-flags (%wt-pointer window)))))

(defun (setf window-resizable-p) (value window)
  "Allow or prevent user resizing of WINDOW."
  (check-type value boolean)
  (pixelisp.internal:with-native-context (%wt-set-resizable (%wt-pointer window) (if value 1 0)))
  value)

(defun window-borderless-p (window)
  "Return whether WINDOW has no window-manager border."
  (pixelisp.internal:with-native-context
    (logbitp 4 (%wt-flags (%wt-pointer window)))))

(defun (setf window-borderless-p) (value window)
  "Show or hide WINDOW's window-manager border."
  (check-type value boolean)
  (pixelisp.internal:with-native-context (%wt-set-bordered (%wt-pointer window) (if value 0 1)))
  value)

(defun window-opacity (window)
  "Return WINDOW opacity in the range 0.0 to 1.0."
  (pixelisp.internal:with-native-context
    (cffi:with-foreign-object (opacity :float)
      (let ((status (%wt-get-opacity (%wt-pointer window) opacity)))
        (when (minusp status)
          (error 'pixelisp:unsupported-feature :operation 'window-opacity
                 :message (format nil "SDL cannot read opacity on this video backend: ~A"
                                  (cffi:foreign-funcall "SDL_GetError" :string))))
        (cffi:mem-ref opacity :float)))))

(defun (setf window-opacity) (value window)
  "Set WINDOW opacity, where 0.0 is transparent and 1.0 is opaque."
  (unless (and (realp value) (<= 0 value 1))
    (error 'type-error :datum value :expected-type '(real 0 1)))
  (pixelisp.internal:with-native-context
    (let ((status (%wt-set-opacity (%wt-pointer window) (coerce value 'single-float))))
      (when (minusp status)
        (error 'pixelisp:unsupported-feature :operation 'window-opacity
               :message (format nil "SDL cannot set opacity on this video backend: ~A"
                                (cffi:foreign-funcall "SDL_GetError" :string)))))
    value))

(defun window-fullscreen-mode (window)
  "Return NIL when windowed, :DESKTOP for desktop fullscreen, or :EXCLUSIVE."
  (pixelisp.internal:with-native-context
    (let ((flags (%wt-flags (%wt-pointer window))))
      (when (logbitp 0 flags)
        (if (logbitp 12 flags) :desktop :exclusive)))))

(defun set-fullscreen (window &key desktop)
  "Request fullscreen for WINDOW; DESKTOP selects desktop-sized fullscreen."
  (check-type desktop boolean)
  (pixelisp.internal:with-native-context
    (pixelisp.devices.internal:check-code
     (%wt-fullscreen (%wt-pointer window) (if desktop #x1001 1)) 'set-fullscreen))
  window)

(defun set-windowed (window)
  "Request ordinary windowed mode for WINDOW."
  (pixelisp.internal:with-native-context
    (pixelisp.devices.internal:check-code (%wt-fullscreen (%wt-pointer window) 0) 'set-windowed))
  window)

(defun maximize-window (window)
  "Ask the window manager to maximize WINDOW."
  (pixelisp.internal:with-native-context (%wt-maximize (%wt-pointer window))) window)
(defun minimize-window (window)
  "Ask the window manager to minimize WINDOW."
  (pixelisp.internal:with-native-context (%wt-minimize (%wt-pointer window))) window)
(defun restore-window (window)
  "Restore WINDOW after it has been minimized or maximized."
  (pixelisp.internal:with-native-context (%wt-restore (%wt-pointer window))) window)
(defun window-grab-p (window)
  "Return whether WINDOW has the input grab enabled."
  (pixelisp.internal:with-native-context (plusp (%wt-get-grab (%wt-pointer window)))))
(defun (setf window-grab-p) (value window)
  "Enable or disable SDL's input grab for WINDOW."
  (check-type value boolean)
  (pixelisp.internal:with-native-context (%wt-set-grab (%wt-pointer window) (if value 1 0))) value)

(defun set-window-icon (window surface)
  "Set WINDOW's icon from a Pixelisp software SURFACE."
  (check-type surface px.surface:surface)
  (pixelisp.internal:with-native-context
    (when (px.surface:locked-p surface)
      (error 'pixelisp:resource-in-use :operation 'set-window-icon
             :message "Setting a window icon from a locked surface is not allowed."))
    (pixelisp.internal:ensure-live surface)
    (%wt-set-icon (%wt-pointer window)
                  (pixelisp.internal:%ptr (pixelisp.internal:surface-handle surface))))
  window)
