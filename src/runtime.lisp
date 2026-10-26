;;;; SDL lifecycle, display, input and frame timing.
;;;; Keep event pumping on the initializing thread. Worker threads only POST.

(defpackage #:pixelisp.display
  (:use #:cl) (:nicknames #:px.display)
  (:export #:init #:quit #:get-init #:set-mode #:get-surface #:get-window
           #:flip #:update #:set-caption #:get-caption #:get-window-size
           #:get-active #:toggle-fullscreen #:set-icon #:get-desktop-sizes
           #:get-driver #:get-num-displays #:list-modes #:mode-ok #:get-display-info
           #:iconify #:get-allow-screensaver #:set-allow-screensaver))
(defpackage #:pixelisp.event
  (:use #:cl) (:nicknames #:px.event) (:shadow #:get #:type #:wait)
  (:export #:event #:make-event #:type #:attributes #:attribute #:post #:get
           #:poll #:wait #:pump #:clear #:peek #:custom-type #:set-blocked #:set-allowed
           #:get-blocked #:event-name #:set-grab #:get-grab
           #:set-keyboard-grab #:get-keyboard-grab))
(defpackage #:pixelisp.key
  (:use #:cl) (:nicknames #:px.key)
  (:export #:get-pressed #:pressed-p #:name #:key-code #:get-mods #:set-mods
           #:start-text-input #:stop-text-input #:set-text-input-rect #:get-focused
           #:set-repeat #:get-repeat))
(defpackage #:pixelisp.mouse
  (:use #:cl) (:nicknames #:px.mouse)
  (:export #:get-pos #:set-pos #:get-rel #:get-pressed #:set-visible #:get-visible
           #:set-relative-mode #:get-relative-mode #:get-focused))
(defpackage #:pixelisp.time
  (:use #:cl) (:nicknames #:px.time)
  (:export #:clock #:make-clock #:get-ticks #:delay #:wait #:tick #:tick-busy-loop
           #:get-time #:get-rawtime #:get-fps #:set-timer #:cancel-timer))
(defpackage #:pixelisp.locals
  (:use #:cl) (:nicknames #:px.locals)
  (:export #:+quit+ #:+keydown+ #:+keyup+ #:+mousemotion+ #:+mousebuttondown+
           #:+mousebuttonup+ #:+textinput+ #:+resizable+ #:+fullscreen+ #:+srcalpha+))
(defpackage #:pixelisp.version
  (:use #:cl) (:nicknames #:px.version)
  (:export #:+version+ #:+pygame-reference+ #:get-sdl-version))

(in-package #:pixelisp.internal)
(cffi:defcfun ("SDL_Init" %init) :int (flags :uint32))
(cffi:defcfun ("SDL_InitSubSystem" %init-subsystem) :int (flags :uint32))
(cffi:defcfun ("SDL_Quit" %quit) :void)
(cffi:defcfun ("SDL_SetHint" %set-hint) :int (name :string) (value :string))
(defun prepare-native-runtime ()
  "Preserve the host Lisp's signal handlers before initializing any SDL subsystem."
  ;; SBCL uses POSIX signals for its own runtime. Letting SDL install handlers can
  ;; corrupt signal delivery when an SDL worker forwards a signal to a Lisp thread.
  ;; Setting a hint does not initialize SDL or open a window/audio/input device.
  (%set-hint "SDL_NO_SIGNAL_HANDLERS" "1")
  t)
(prepare-native-runtime)

(defun check-video-ready (operation)
  "Check both the video initialization state and its owning thread."
  (check-video-thread)
  (unless *video-thread*
    (error 'pixelisp:initialization-error :operation operation
           :message "Initialize the video subsystem before querying keyboard or mouse state.")))

(defun pixelisp:init (&key (video t) audio)
  "Initialize timers/events and optionally video or audio on the current thread.
Loading an ASDF system never initializes SDL or opens devices."
  (check-video-thread)
  (prepare-native-runtime)
  (let* ((flags (logior 1 #x4000 (if video #x20 0) (if audio #x10 0)))
         (result (if *initialized* (%init-subsystem flags) (%init flags))))
    (when (minusp result) (native-error 'pixelisp:init))
    (when video (setf *video-thread* (bt:current-thread)))
    (setf *initialized* t))
  t)
(defun pixelisp:get-init () *initialized*)
(defun pixelisp:quit ()
  "Dispose registered resources before shutting down their native subsystems."
  (check-video-thread)
  (let ((errors nil))
    ;; The newest object is disposed first: views before buffers, textures before
    ;; renderers, and fonts before SDL_ttf. Continue cleanup after a local error.
    (dolist (resource *resources*)
      (handler-case (dispose resource) (error (condition) (push condition errors))))
    (setf *resources* (remove-if #'resource-disposed-p *resources*))
    (dolist (hook *shutdown-hooks*)
      (handler-case (funcall hook) (error (condition) (push condition errors))))
    (px.display:quit)
    (%quit)
    (setf *initialized* nil *video-thread* nil)
    (when errors (error (first errors))))
  t)
(defmacro pixelisp:with-init ((&rest options) &body body)
  "Run BODY with SDL initialized, always disposing resources on exit."
  `(with-native-context
     (pixelisp:init ,@options)
     (unwind-protect (progn ,@body) (pixelisp:quit))))

(in-package #:pixelisp.display)
(defvar *window* nil)
(defvar *screen* nil)
(defvar *caption* "Pixelisp")
(cffi:defcfun ("SDL_UpdateWindowSurfaceRects" %update-rects) :int
  (window :pointer) (rects :pointer) (count :int))
(cffi:defcfun ("SDL_SetWindowIcon" %set-icon) :void (window :pointer) (surface :pointer))
(cffi:defcfun ("SDL_GetNumVideoDisplays" %display-count) :int)
(cffi:defcfun ("SDL_GetDisplayBounds" %display-bounds) :int (index :int) (rect :pointer))
;; SDL_DisplayMode is a public SDL2 structure: Uint32 format, three ints, and
;; driverdata. CFFI lays out the fields with the platform's native alignment.
(cffi:defcstruct %display-mode
  (format :uint32) (w :int) (h :int) (refresh-rate :int) (driverdata :pointer))
(cffi:defcfun ("SDL_GetNumDisplayModes" %display-mode-count) :int (display :int))
(cffi:defcfun ("SDL_GetDisplayMode" %display-mode-at) :int
  (display :int) (mode :int) (output :pointer))
(cffi:defcfun ("SDL_GetCurrentDisplayMode" %current-display-mode) :int
  (display :int) (output :pointer))
(cffi:defcfun ("SDL_GetDesktopDisplayMode" %desktop-display-mode) :int
  (display :int) (output :pointer))
(cffi:defcfun ("SDL_GetCurrentVideoDriver" %current-video-driver) :string)
;; These are SDL2's public display controls. SDL_MinimizeWindow has no return
;; value; ICONIFY therefore reports that SDL accepted the request after a live
;; window was supplied, not that the window manager completed minimization.
(cffi:defcfun ("SDL_MinimizeWindow" %minimize-window) :void (window :pointer))
(cffi:defcfun ("SDL_IsScreenSaverEnabled" %is-screensaver-enabled) :int)
(cffi:defcfun ("SDL_EnableScreenSaver" %enable-screensaver) :void)
(cffi:defcfun ("SDL_DisableScreenSaver" %disable-screensaver) :void)
(defun init () (pixelisp:init :video t))
(defun get-init () (and pixelisp.internal:*initialized* (not (null pixelisp.internal:*video-thread*))))
(defun quit ()
  "Close the default display; offscreen surfaces remain individually usable."
  (pixelisp.internal:check-video-thread)
  (when *screen* (pixelisp:dispose *screen*) (setf *screen* nil))
  (when *window* (sdl2:destroy-window *window*) (setf *window* nil)) t)
(defun set-mode (&optional (size '(0 0))
                &key (flags '(:shown)) (title *caption*) fullscreen resizable (display 0))
  "Create the default display and return its software drawing surface.
SET-MODE disposes the previous display surface. Offscreen assets are retained."
  (init)
  ;; Resolve and validate the requested monitor/size before replacing a live
  ;; display. A zero axis uses that monitor's desktop dimension.
  (multiple-value-bind (width height) (%resolved-display-size size display)
    (quit)
    (let ((window-flags (append flags (when fullscreen '(:fullscreen-desktop))
                               (when resizable '(:resizable))))
          (position (logior #x2fff0000 display))) ; SDL_WINDOWPOS_CENTERED_DISPLAY
      (setf *window* (sdl2:create-window :title title :x position :y position
                                      :w width :h height :flags window-flags)
            *caption* title))
    (handler-case (setf *screen* (px.surface:make-surface (list width height)))
      (error (condition) (quit) (error condition))))
  *screen*)
(defun get-surface () *screen*)
(defun get-window ()
  (pixelisp.internal:check-video-thread)
  (or *window* (error 'pixelisp:initialization-error :operation 'get-window :message "Create a display with SET-MODE first.")))
(defun get-window-size ()
  (multiple-value-bind (w h) (sdl2:get-window-size (get-window)) (list w h)))
(defun get-caption () *caption*)
(defun set-caption (title)
  (setf *caption* title) (when *window* (sdl2:set-window-title (get-window) title)) title)
(defun set-icon (surface)
  (%set-icon (pixelisp.internal:%ptr (get-window))
             (pixelisp.internal:%ptr (pixelisp.internal:surface-handle surface))) surface)
(defun get-active ()
  "Return true when the default window is shown and not minimized."
  (pixelisp.internal:check-video-thread)
  (when *window*
    (let ((flags (sdl2:get-window-flags *window*)))
      (and (not (null (member :shown flags))) (not (member :minimized flags))))))
(defun iconify ()
  "Request minimization of the current window and return true after issuing it.
SDL's minimize call is void, so this does not report whether the window manager
has completed the request."
  (pixelisp.internal::check-video-ready 'iconify)
  (%minimize-window (pixelisp.internal:%ptr (get-window)))
  t)
(defun get-allow-screensaver ()
  "Return whether SDL currently allows the system screensaver to run."
  (pixelisp.internal::check-video-ready 'get-allow-screensaver)
  (plusp (%is-screensaver-enabled)))
(defun set-allow-screensaver (allow)
  "Allow or inhibit the system screensaver and return ALLOW."
  (pixelisp.internal::check-video-ready 'set-allow-screensaver)
  (check-type allow boolean)
  (if allow (%enable-screensaver) (%disable-screensaver))
  allow)
(defun toggle-fullscreen ()
  (let* ((window (get-window)) (flags (sdl2:get-window-flags window))
         (fullscreen (member :fullscreen flags)))
    (sdl2:set-window-fullscreen window (if fullscreen nil :desktop)) (not fullscreen)))
(defun %copy-to-window (&optional rectangle)
  ;; SDL may replace the window surface after resize or presentation. Reacquire
  ;; it each time, and never free this borrowed native surface ourselves.
  (let ((native (sdl2:get-window-surface (get-window)))
        (screen (pixelisp.internal:surface-handle *screen*)))
    (if rectangle
        (pixelisp.internal::with-native-rect (source rectangle)
          (pixelisp.internal::with-native-rect (destination rectangle)
            (when (minusp (pixelisp.internal::%blit (pixelisp.internal:%ptr screen) source
                                                   (pixelisp.internal:%ptr native) destination))
              (pixelisp.internal:native-error 'update))))
        (when (minusp (sdl2:blit-scaled screen nil native nil))
          (pixelisp.internal:native-error 'flip)))))
(defun flip ()
  "Present the whole logical framebuffer, scaled to the current window size."
  (%copy-to-window) (sdl2:update-window (get-window)) t)
(defun update (&optional rectangles)
  "Present one rectangle or a list of rectangles. NIL presents the whole frame."
  (unless rectangles (return-from update (flip)))
  ;; A resized native window may scale the logical framebuffer. Fall back to
  ;; full presentation so partial rectangles cannot use the wrong coordinate space.
  (unless (equal (get-window-size) (px.surface:size *screen*))
    (return-from update (flip)))
  (when (and (vectorp rectangles) (zerop (length rectangles))) (return-from update t))
  (let ((areas (if (or (typep rectangles 'pixelisp:rect)
                       (and (typep rectangles 'sequence) (numberp (elt rectangles 0))))
                   (list (pixelisp.internal:as-rect rectangles))
                   (mapcar #'pixelisp.internal:as-rect rectangles))))
    (setf areas (remove-if (lambda (area) (or (zerop (px.rect:width area)) (zerop (px.rect:height area))))
                          (mapcar (lambda (area) (px.rect:clip area (px.surface:get-rect *screen*))) areas)))
    (unless areas (return-from update t))
    (dolist (area areas) (%copy-to-window area))
    (cffi:with-foreign-object (native '(:struct pixelisp.internal::native-rect) (length areas))
      (loop for area in areas for i from 0
            for pointer = (cffi:mem-aptr native '(:struct pixelisp.internal::native-rect) i)
            do (setf (cffi:foreign-slot-value pointer '(:struct pixelisp.internal::native-rect) 'pixelisp.internal::x) (px.rect:x area)
                     (cffi:foreign-slot-value pointer '(:struct pixelisp.internal::native-rect) 'pixelisp.internal::y) (px.rect:y area)
                     (cffi:foreign-slot-value pointer '(:struct pixelisp.internal::native-rect) 'pixelisp.internal::w) (px.rect:width area)
                     (cffi:foreign-slot-value pointer '(:struct pixelisp.internal::native-rect) 'pixelisp.internal::h) (px.rect:height area)))
      (when (minusp (%update-rects (pixelisp.internal:%ptr (get-window)) native (length areas)))
        (pixelisp.internal:native-error 'update)))) t)
(defun get-desktop-sizes ()
  (init)
  (loop for index below (%display-count) collect
    (cffi:with-foreign-object (r '(:struct pixelisp.internal::native-rect))
      (when (minusp (%display-bounds index r)) (pixelisp.internal:native-error 'get-desktop-sizes))
      (list (cffi:foreign-slot-value r '(:struct pixelisp.internal::native-rect) 'pixelisp.internal::w)
            (cffi:foreign-slot-value r '(:struct pixelisp.internal::native-rect) 'pixelisp.internal::h)))))

(defun get-driver ()
  "Return the name of SDL's active video driver.
Video must already be initialized on its owning thread."
  (pixelisp.internal::check-video-ready 'get-driver)
  (or (%current-video-driver) (pixelisp.internal:native-error 'get-driver)))

(defun get-num-displays ()
  "Return the number of displays SDL currently exposes.
Video must already be initialized on its owning thread."
  (pixelisp.internal::check-video-ready 'get-num-displays)
  (let ((count (%display-count)))
    (when (minusp count) (pixelisp.internal:native-error 'get-num-displays))
    count))

(defun %check-display-index (display operation)
  (pixelisp.internal::check-video-ready operation)
  (check-type display (integer 0 *))
  (let ((count (get-num-displays)))
    (unless (< display count)
      (error "Display index ~D is outside the available range [0, ~D)." display count)))
  display)

(defun %mode-values (display query operation &optional mode-index)
  (cffi:with-foreign-object (mode '(:struct %display-mode))
    (when (minusp (if mode-index
                      (%display-mode-at display mode-index mode)
                      (funcall query display mode)))
      (pixelisp.internal:native-error operation))
    (values (cffi:foreign-slot-value mode '(:struct %display-mode) 'format)
            (cffi:foreign-slot-value mode '(:struct %display-mode) 'w)
            (cffi:foreign-slot-value mode '(:struct %display-mode) 'h)
            (cffi:foreign-slot-value mode '(:struct %display-mode) 'refresh-rate))))

(defun list-modes (&key (display 0))
  "Return unique (width height) pairs in SDL's native mode order.
An empty enumeration is returned as NIL, as SDL backends can expose no modes."
  (%check-display-index display 'list-modes)
  (let ((count (%display-mode-count display)))
    (when (minusp count) (pixelisp.internal:native-error 'list-modes))
    (let ((sizes nil))
      (dotimes (index count (nreverse sizes))
        (multiple-value-bind (format width height refresh-rate)
            (%mode-values display nil 'list-modes index)
          (declare (ignore format refresh-rate))
          (let ((size (list width height)))
            (unless (member size sizes :test #'equal)
              (push size sizes))))))))

(defun %pixel-depth (format)
  ;; SDL_PixelFormatEnumToMasks is the public function behind SDL's
  ;; SDL_BITSPERPIXEL macro for packed formats. FourCC formats report zero.
  (cffi:with-foreign-objects ((bits :int) (red :uint32) (green :uint32)
                              (blue :uint32) (alpha :uint32))
    (if (plusp (pixelisp.internal::%pixel-format-masks format bits
                                                       red green blue alpha))
        (cffi:mem-ref bits :int)
        0)))

(defun get-display-info (&optional (display 0))
  "Return a fresh plist describing DISPLAY's desktop and current SDL modes.
The plist contains :DESKTOP-SIZE, :CURRENT-SIZE, :PIXEL-FORMAT,
:PIXEL-DEPTH, :REFRESH-RATE, and (when available) :DRIVER."
  (%check-display-index display 'get-display-info)
  (multiple-value-bind (desktop-format desktop-width desktop-height desktop-refresh)
      (%mode-values display #'%desktop-display-mode 'get-display-info)
    (declare (ignore desktop-format desktop-refresh))
    (multiple-value-bind (format width height refresh-rate)
        (%mode-values display #'%current-display-mode 'get-display-info)
      (let ((info (list :desktop-size (list desktop-width desktop-height)
                        :current-size (list width height)
                        :pixel-format format :pixel-depth (%pixel-depth format)
                        :refresh-rate refresh-rate)))
        (let ((driver (%current-video-driver)))
          (when driver (setf (getf info :driver) driver)))
        info))))

(in-package #:pixelisp.time)
(defvar *epoch* (get-internal-real-time))
(defun get-ticks () "Milliseconds elapsed since this system was loaded."
  (floor (* 1000 (- (get-internal-real-time) *epoch*)) internal-time-units-per-second))
(defun delay (milliseconds)
  (check-type milliseconds (real 0 *))
  (let ((before (get-ticks))) (sleep (/ milliseconds 1000.0)) (- (get-ticks) before)))
(setf (fdefinition 'wait) #'delay)
(defstruct (clock (:constructor make-clock ()))
  (last (get-ticks)) (time 0) (rawtime 0) (samples nil))
(defun tick (clock &optional (framerate 0))
  "Return frame milliseconds, sleeping when necessary to cap FRAMERATE."
  (check-type framerate (real 0 *))
  (let* ((now (get-ticks)) (raw (- now (clock-last clock)))
         (budget (if (plusp framerate) (/ 1000.0 framerate) 0)))
    (when (< raw budget) (delay (- budget raw)))
    (let* ((end (get-ticks)) (elapsed (- end (clock-last clock))))
      (setf (clock-last clock) end (clock-time clock) elapsed (clock-rawtime clock) raw)
      (push elapsed (clock-samples clock))
      (when (> (length (clock-samples clock)) 10) (setf (clock-samples clock) (subseq (clock-samples clock) 0 10))) elapsed)))
(setf (fdefinition 'tick-busy-loop) #'tick)
(defun get-time (clock) (clock-time clock))
(defun get-rawtime (clock) (clock-rawtime clock))
(defun get-fps (clock)
  (let ((total (reduce #'+ (clock-samples clock) :initial-value 0)))
    (if (plusp total) (/ (* 1000.0 (length (clock-samples clock))) total) 0.0)))
(defstruct timer event interval next remaining)
(defvar *timers* nil)
(defun cancel-timer (type)
  (setf *timers* (delete type *timers* :key (lambda (timer) (px.event:type (timer-event timer))) :test #'eql)))
(defun set-timer (event-or-type milliseconds &key (loops 0))
  "Post EVENT-OR-TYPE at an interval. LOOPS=0 repeats; zero interval cancels."
  (check-type milliseconds (integer 0 *)) (check-type loops (integer 0 *))
  (let ((event (if (typep event-or-type 'px.event:event) event-or-type (px.event:make-event event-or-type))))
    (cancel-timer (px.event:type event))
    (when (plusp milliseconds)
      (push (make-timer :event event :interval milliseconds :next (+ (get-ticks) milliseconds)
                        :remaining (unless (zerop loops) loops)) *timers*))) t)
(defun update-timers ()
  ;; Timers are delivered during pumping, never through foreign-thread callbacks.
  (let ((now (get-ticks)))
    (dolist (timer (copy-list *timers*))
      (when (>= now (timer-next timer))
        (px.event:post (timer-event timer))
        (setf (timer-next timer) (+ now (timer-interval timer)))
        (when (and (timer-remaining timer) (zerop (decf (timer-remaining timer))))
          (setf *timers* (delete timer *timers*)))))))
(pushnew #'update-timers pixelisp.internal:*pump-hooks*)
(pushnew (lambda () (setf *timers* nil)) pixelisp.internal:*shutdown-hooks*)

(in-package #:pixelisp.event)
(defstruct (event (:constructor %event (type attributes))) type attributes)
(defun make-event (type &rest attributes)
  "Build an event with a keyword or integer TYPE and a property list of attributes."
  (unless (or (keywordp type) (integerp type)) (error "Event type must be a keyword or integer."))
  (unless (evenp (length attributes)) (error "Event attributes must be key/value pairs."))
  (%event type (copy-list attributes)))
(setf (fdefinition 'type) #'event-type (fdefinition 'attributes) #'event-attributes)
(defun attribute (event name &optional default) (getf (event-attributes event) name default))
(defun (setf attribute) (value event name &optional default)
  (declare (ignore default)) (setf (getf (event-attributes event) name) value))
(defvar *queue* nil)
(defvar *queue-lock* (bt:make-lock "Pixelisp event queue"))
(defvar *blocked* (make-hash-table))
(defvar *allowed* (make-hash-table))
(defvar *all-blocked* nil)
(defvar *next-custom-type* #x10000)
(defun custom-type () (bt:with-lock-held (*queue-lock*) (incf *next-custom-type*)))
(defun %event-types (types)
  "Normalize one event type or a sequence of types, preserving NIL as empty."
  (let ((result (cond ((or (keywordp types) (integerp types)) (list types))
                      ((and (typep types 'sequence) (not (stringp types))) (coerce types 'list))
                      (t (error "Expected an event type or a sequence of event types, got ~S." types)))))
    (unless (every (lambda (type) (or (keywordp type) (integerp type))) result)
      (error "Event type sequences may contain only keywords or integers: ~S." types))
    result))
(defun set-blocked (types)
  "Block TYPES and remove matching queued events. NIL blocks every event type."
  (bt:with-lock-held (*queue-lock*)
    (let ((event-types (%event-types types)))
      (if (null types)
          (progn (setf *all-blocked* t) (clrhash *allowed*) (setf *queue* nil))
          (progn
            (dolist (type event-types)
              (if *all-blocked* (remhash type *allowed*) (setf (gethash type *blocked*) t)))
            (setf *queue* (delete-if (lambda (event) (member (type event) event-types)) *queue*)))))) nil)
(defun set-allowed (types)
  "Allow TYPES; NIL allows every event type."
  (bt:with-lock-held (*queue-lock*)
    (let ((event-types (%event-types types)))
      (if (null types)
          (progn (setf *all-blocked* nil) (clrhash *allowed*) (clrhash *blocked*))
          (dolist (type event-types)
            (if *all-blocked* (setf (gethash type *allowed*) t) (remhash type *blocked*)))))) nil)
(defun get-blocked (types)
  "Return true when any supplied event type is blocked from Pixelisp's queue."
  (bt:with-lock-held (*queue-lock*)
    (some (lambda (type)
            (if *all-blocked* (not (gethash type *allowed*)) (gethash type *blocked*)))
          (%event-types types))))
(defparameter *event-names*
  ;; Each entry keeps the Lisp spelling, SDL2 integer ID, and display name
  ;; together. Removing hyphens also recognizes the binding's native keywords.
  '((:no-event 0 "NoEvent") (:quit #x100 "Quit")
    (:window-event #x200 "WindowEvent")
    (:key-down #x300 "KeyDown") (:key-up #x301 "KeyUp")
    (:text-editing #x302 "TextEditing") (:text-input #x303 "TextInput")
    (:mouse-motion #x400 "MouseMotion")
    (:mouse-button-down #x401 "MouseButtonDown") (:mouse-button-up #x402 "MouseButtonUp")
    (:mouse-wheel #x403 "MouseWheel")
    (:joy-axis-motion #x600 "JoyAxisMotion") (:joy-ball-motion #x601 "JoyBallMotion")
    (:joy-hat-motion #x602 "JoyHatMotion") (:joy-button-down #x603 "JoyButtonDown")
    (:joy-button-up #x604 "JoyButtonUp") (:joy-device-added #x605 "JoyDeviceAdded")
    (:joy-device-removed #x606 "JoyDeviceRemoved")
    (:controller-axis-motion #x650 "ControllerAxisMotion")
    (:controller-button-down #x651 "ControllerButtonDown")
    (:controller-button-up #x652 "ControllerButtonUp")
    (:controller-device-added #x653 "ControllerDeviceAdded")
    (:controller-device-removed #x654 "ControllerDeviceRemoved")
    (:controller-device-remapped #x655 "ControllerDeviceRemapped")
    (:controller-touchpad-down #x656 "ControllerTouchpadDown")
    (:controller-touchpad-motion #x657 "ControllerTouchpadMotion")
    (:controller-touchpad-up #x658 "ControllerTouchpadUp")
    (:controller-sensor-update #x659 "ControllerSensorUpdate")
    (:finger-down #x700 "FingerDown") (:finger-up #x701 "FingerUp")
    (:finger-motion #x702 "FingerMotion")
    (:dollar-gesture #x800 "DollarGesture") (:dollar-record #x801 "DollarRecord")
    (:multi-gesture #x802 "MultiGesture") (:clipboard-update #x900 "ClipboardUpdate")
    (:drop-file #x1000 "DropFile") (:drop-text #x1001 "DropText")
    (:drop-begin #x1002 "DropBegin") (:drop-complete #x1003 "DropComplete")
    (:audio-device-added #x1100 "AudioDeviceAdded")
    (:audio-device-removed #x1101 "AudioDeviceRemoved")
    (:sensor-update #x1200 "SensorUpdate")
    (:render-targets-reset #x2000 "RenderTargetsReset")
    (:render-device-reset #x2001 "RenderDeviceReset")))

(defun event-name (type)
  "Return a fresh readable name for a keyword or SDL2 integer event type.
Native binding keywords and hyphenated Lisp spellings are both recognized.
User IDs at or above #x8000 include their number; unknown types include their value."
  (let* ((key (when (keywordp type) (remove #\- (symbol-name type))))
         (entry (find-if (lambda (entry)
                           (if key
                               (string= key (remove #\- (symbol-name (first entry))))
                               (eql type (second entry))))
                         *event-names*)))
    (cond (entry (copy-seq (third entry)))
          ((and (integerp type) (>= type #x8000)) (format nil "UserEvent (~D)" type))
          (t (format nil "Unknown (~S)" type)))))

(defun %display-window (operation)
  (pixelisp.internal::check-video-ready operation)
  (or px.display::*window*
      (error 'pixelisp:initialization-error :operation operation
             :message "Create a display with PX.DISPLAY:SET-MODE before using window grabs.")))
(defun %native-grab-call (symbols return-type enabled)
  (let* ((window (pixelisp.internal:%ptr (%display-window (first symbols))))
         (native nil))
    (dolist (candidate symbols)
      (when (setf native (cffi:foreign-symbol-pointer candidate))
        (return)))
    (unless native
      (error 'pixelisp:unsupported-feature :operation (first symbols)
             :message (format nil "The loaded SDL library provides none of: ~{~A~^, ~}." symbols)))
    (if (eq return-type :void)
        (progn (cffi:foreign-funcall-pointer native () :pointer window :int (if enabled 1 0) :void)
               (not (null enabled)))
        (not (zerop (cffi:foreign-funcall-pointer native () :pointer window :int))))))
(defun set-grab (enabled)
  "Confine mouse input to the current display window when ENABLED is true."
  (%native-grab-call '("SDL_SetWindowMouseGrab" "SDL_SetWindowGrab") :void enabled))
(defun get-grab ()
  "Return whether the current display window has a mouse grab."
  (%native-grab-call '("SDL_GetWindowMouseGrab" "SDL_GetWindowGrab") :int nil))
(defun set-keyboard-grab (enabled)
  "Confine keyboard input to the current display window when ENABLED is true."
  (%native-grab-call '("SDL_SetWindowKeyboardGrab") :void enabled))
(defun get-keyboard-grab ()
  "Return whether the current display window has a keyboard grab."
  (%native-grab-call '("SDL_GetWindowKeyboardGrab") :int nil))
(defun post (event)
  "Thread-safe posting of Lisp payloads without storing Lisp pointers in SDL."
  (check-type event event)
  (bt:with-lock-held (*queue-lock*)
    (unless (if *all-blocked* (not (gethash (type event) *allowed*))
                (gethash (type event) *blocked*))
      (setf *queue* (nconc *queue* (list event))) t)))
(defmacro %field (event &rest path)
  `(plus-c:c-ref ,event sdl2-ffi:sdl-event ,@path))
(cffi:defcfun ("SDL_free" %free-drop-payload) :void (pointer :pointer))
(defun %copy-drop-payload (pointer)
  ;; SDL transfers ownership of DROPFILE/DROPTEXT strings to the application.
  ;; Copy the UTF-8 data before the next poll and release it with SDL's allocator.
  (unless (cffi:null-pointer-p pointer)
    (unwind-protect (cffi:foreign-string-to-lisp pointer :encoding :utf-8)
      (%free-drop-payload pointer))))
(defun %drop-payload-pointer (native)
  ;; PLUS-C normally turns `char *` fields into Lisp strings. Its second value
  ;; is the address of the pointer slot, from which we read the SDL-owned value.
  (cffi:mem-ref (nth-value 1 (%field native :drop :file)) :pointer))
(defun %normalize-axis (value)
  "Map SDL's asymmetric signed axis range onto the inclusive interval [-1,1]."
  (/ value (if (minusp value) 32768.0 32767.0)))
;; Implemented in mouse-events.lisp, loaded after this file because those helpers
;; depend on %FIELD above and SDL's runtime version API.
(declaim (ftype function %native-touch-mouse-p %native-wheel-precise))
(defun %decode-native (native)
  "Copy SDL's transient union into an ordinary Lisp event before polling again."
  (let ((type (sdl2:get-event-type native)))
    (case type
      ((:keydown :keyup)
       (make-event (if (eq type :keydown) :key-down :key-up)
                   :key (px.key:key-code (sdl2:get-key-name (%field native :key :keysym :sym)))
                   :keycode (%field native :key :keysym :sym)
                   :scancode (%field native :key :keysym :scancode)
                   :mod (%field native :key :keysym :mod) :repeat (plusp (%field native :key :repeat))))
      (:mousemotion
       (make-event :mouse-motion :pos (list (%field native :motion :x) (%field native :motion :y))
                   :rel (list (%field native :motion :xrel) (%field native :motion :yrel))
                   :buttons (%field native :motion :state)
                   :which (%field native :motion :which)
                   :touch (%native-touch-mouse-p (%field native :motion :which))
                   :window-id (%field native :motion :window-id)))
      ((:mousebuttondown :mousebuttonup)
       (make-event (if (eq type :mousebuttondown) :mouse-button-down :mouse-button-up)
                   :button (%field native :button :button)
                   :pos (list (%field native :button :x) (%field native :button :y))
                   :which (%field native :button :which)
                   :touch (%native-touch-mouse-p (%field native :button :which))
                   :window-id (%field native :button :window-id)))
      (:mousewheel
       (let ((precise (%native-wheel-precise native)))
         (make-event :mouse-wheel :x (%field native :wheel :x) :y (%field native :wheel :y)
                     :which (%field native :wheel :which)
                     :touch (%native-touch-mouse-p (%field native :wheel :which))
                     :window-id (%field native :wheel :window-id)
                     :flipped (= (%field native :wheel :direction) 1)
                     :precise-x (first precise) :precise-y (second precise))))
      (:textinput (make-event :text-input :text (%field native :text :text string)))
      (:textediting (make-event :text-editing :text (%field native :edit :text string)
                               :start (%field native :edit :start) :length (%field native :edit :length)))
      (:windowevent (make-event :window-event :event (%field native :window :event)
                               :window-id (%field native :window :window-id)
                               :size (list (%field native :window :data1) (%field native :window :data2))))
      ((:joyaxismotion :controlleraxismotion)
       (let ((controller (eq type :controlleraxismotion)))
         (if controller
             (make-event :controller-axis-motion :which (%field native :caxis :which)
                         :axis (%field native :caxis :axis) :value (%normalize-axis (%field native :caxis :value)))
             (make-event :joy-axis-motion :which (%field native :jaxis :which)
                         :axis (%field native :jaxis :axis) :value (%normalize-axis (%field native :jaxis :value))))))
      ((:controllerbuttondown :controllerbuttonup)
       (make-event type :which (%field native :cbutton :which) :button (%field native :cbutton :button)
                   :state (%field native :cbutton :state)))
      ((:joybuttondown :joybuttonup)
       (make-event type :which (%field native :jbutton :which) :button (%field native :jbutton :button)
                   :state (%field native :jbutton :state)))
      (:joyhatmotion
       (make-event :joy-hat-motion :which (%field native :jhat :which)
                   :hat (%field native :jhat :hat) :value (%field native :jhat :value)))
      (:joyballmotion
       (make-event :joy-ball-motion :which (%field native :jball :which)
                   :ball (%field native :jball :ball)
                   :rel (list (%field native :jball :xrel) (%field native :jball :yrel))))
      ((:controllerdeviceadded :controllerdeviceremoved)
       (make-event type :which (%field native :cdevice :which)))
      ((:joydeviceadded :joydeviceremoved)
       (make-event type :which (%field native :jdevice :which)))
      ((:controllertouchpaddown :controllertouchpadmotion :controllertouchpadup)
       (make-event type :which (%field native :ctouchpad :which)
                   :touchpad (%field native :ctouchpad :touchpad)
                   :finger (%field native :ctouchpad :finger)
                   :x (%field native :ctouchpad :x) :y (%field native :ctouchpad :y)
                   :pressure (%field native :ctouchpad :pressure)))
      (:controllersensorupdate
       (make-event type :which (%field native :csensor :which)
                   :sensor (%field native :csensor :sensor)
                   :data (loop for index below 3 collect (%field native :csensor :data index))))
      (:sensorupdate
       (make-event type :which (%field native :sensor :which)
                   :data (loop for index below 6 collect (%field native :sensor :data index))))
      ((:audiodeviceadded :audiodeviceremoved)
       (make-event type :which (%field native :adevice :which)
                   :capture (plusp (%field native :adevice :iscapture))))
      ((:fingerdown :fingerup :fingermotion)
       (make-event type :touch-id (%field native :tfinger :touch-id) :finger-id (%field native :tfinger :finger-id)
                   :x (%field native :tfinger :x) :y (%field native :tfinger :y)
                   :dx (%field native :tfinger :dx) :dy (%field native :tfinger :dy)
                   :pressure (%field native :tfinger :pressure)))
      (:multigesture
       (make-event type :touch-id (%field native :mgesture :touch-id)
                   :dtheta (%field native :mgesture :d-theta)
                   :ddist (%field native :mgesture :d-dist)
                   :x (%field native :mgesture :x) :y (%field native :mgesture :y)
                   :fingers (%field native :mgesture :num-fingers)))
      ((:dollargesture :dollarrecord)
       (make-event type :touch-id (%field native :dgesture :touch-id)
                   :gesture-id (%field native :dgesture :gesture-id)
                   :fingers (%field native :dgesture :num-fingers)
                   :x (%field native :dgesture :x) :y (%field native :dgesture :y)))
      ((:dropfile :droptext)
       (let ((payload (%copy-drop-payload (%drop-payload-pointer native))))
         (make-event type (if (eq type :droptext) :text :file) payload
                     :window-id (%field native :drop :window-id))))
      ((:dropbegin :dropcomplete)
       (make-event type :window-id (%field native :drop :window-id)))
      (otherwise (make-event type)))))
(defun pump ()
  "Pump native events and scheduled work on the video thread."
  (pixelisp.internal:check-video-thread)
  (when pixelisp.internal:*initialized*
    (sdl2:with-sdl-event (native)
      (loop while (plusp (sdl2:next-event native)) do
        (let ((event (%decode-native native)))
          (when (px.key::%handle-native-key-repeat event)
            (post event))))))
  (dolist (hook pixelisp.internal:*pump-hooks*) (funcall hook)) t)
(defun %selection (types exclude limit pump)
  "Validate event selection arguments before pumping or changing the queue."
  (check-type pump boolean)
  (when limit (check-type limit (integer 0 *)))
  (when (and types exclude)
    (error "TYPES and EXCLUDE cannot both be non-NIL."))
  (values (not (null types)) (and types (%event-types types))
          (not (null exclude)) (and exclude (%event-types exclude))))
(defun %pump-if-requested (pump)
  ;; Even a queue-only operation must not consume from a worker thread when
  ;; video is initialized. The pump function performs this same check itself.
  (if pump (pixelisp.event:pump) (pixelisp.internal:check-video-thread)))
(defun get (&key types limit exclude (pump t))
  "Remove queued events, optionally filtered by TYPES or EXCLUDE.
With no selection, all events are removed. LIMIT caps the number returned;
PUMP controls whether native events and scheduled work are processed first."
  (multiple-value-bind (types-specified types exclude-specified exclude)
      (%selection types exclude limit pump)
    (%pump-if-requested pump)
    (let ((accepted nil) (remaining nil) (count 0))
      (bt:with-lock-held (*queue-lock*)
        (dolist (event *queue*)
          (if (and (or (not types-specified) (member (type event) types))
                   (or (not exclude-specified) (not (member (type event) exclude)))
                   (or (null limit) (< count limit)))
              (progn (push event accepted) (incf count))
              (push event remaining)))
        (setf *queue* (nreverse remaining)))
      (nreverse accepted))))
(defun poll () (first (get :limit 1)))
(defun wait (&optional timeout)
  "Wait for one event; TIMEOUT is milliseconds, or NIL for no deadline."
  (let ((deadline (when timeout (+ (px.time:get-ticks) timeout))))
    (loop for event = (poll) when event return event
          when (and deadline (>= (px.time:get-ticks) deadline)) return nil do (sleep 0.001))))
(defun clear (&optional types &key (pump t))
  "Remove all matching events. With keyword arguments, pass NIL for TYPES first."
  (get :types types :pump pump)
  nil)
(defun peek (&optional types &key (pump t))
  "Test for matching queued events. With keyword arguments, pass NIL for TYPES first."
  (multiple-value-bind (types-specified types exclude-specified exclude)
      (%selection types nil nil pump)
    (declare (ignore exclude-specified exclude))
    (%pump-if-requested pump)
    (bt:with-lock-held (*queue-lock*)
      (not (null (if types-specified
                     (find-if (lambda (event) (member (type event) types)) *queue*)
                     *queue*))))))
(pushnew (lambda () (bt:with-lock-held (*queue-lock*)
                      (setf *queue* nil *all-blocked* nil)
                      (clrhash *blocked*) (clrhash *allowed*)))
         pixelisp.internal:*shutdown-hooks*)

(in-package #:pixelisp.key)
(cffi:defcfun ("SDL_GetKeyboardState" %state) :pointer (count :pointer))
(cffi:defcfun ("SDL_GetScancodeFromName" %scancode) :int (name :string))
(cffi:defcfun ("SDL_SetModState" %set-mods) :void (mod :int))
(cffi:defcfun ("SDL_SetTextInputRect" %text-rect) :void (rect :pointer))
(cffi:defcfun ("SDL_GetKeyboardFocus" %focus) :pointer)
(defun key-code (name)
  "Return the Lisp keyword used in events for a human-readable key name."
  (intern (if (string= name " ") "SPACE" (substitute #\- #\Space (string-upcase name))) :keyword))
(defun name (key)
  "Return SDL's human-readable key name, accepting event keywords or keycodes."
  (if (integerp key) (sdl2:get-key-name key)
      (let ((name (string-downcase (string key))))
        (if (> (length name) 1) (substitute #\Space #\- name) name))))
(defun get-pressed ()
  (pixelisp.internal::check-video-ready 'get-pressed)
  (cffi:with-foreign-object (count :int)
    (let* ((pointer (%state count)) (n (cffi:mem-ref count :int)) (result (make-array n :element-type 'bit)))
      (dotimes (i n result) (setf (aref result i) (if (zerop (cffi:mem-aref pointer :uint8 i)) 0 1))))))
(defun pressed-p (key)
  (let* ((scan (if (integerp key) key (%scancode (name key)))) (state (get-pressed)))
    (and (<= 0 scan) (< scan (length state)) (= 1 (aref state scan)))))
(defun get-mods () (pixelisp.internal::check-video-ready 'get-mods) (sdl2:get-mod-state))
(defun set-mods (mods) (pixelisp.internal::check-video-ready 'set-mods) (%set-mods mods) mods)
(defun start-text-input () (pixelisp.internal::check-video-ready 'start-text-input) (sdl2:start-text-input))
(defun stop-text-input () (pixelisp.internal::check-video-ready 'stop-text-input) (sdl2:stop-text-input))
(defun set-text-input-rect (rectangle)
  (pixelisp.internal::check-video-ready 'set-text-input-rect)
  (pixelisp.internal::with-native-rect (rect rectangle) (%text-rect rect)))
(defun get-focused () (pixelisp.internal::check-video-ready 'get-focused) (not (cffi:null-pointer-p (%focus))))

;; SDL2 key repeat events are platform generated and can arrive late or in
;; bursts after a stalled frame. Pixelisp schedules repeats at pump time so
;; delivery remains on the video thread and missed intervals coalesce to one.
(defvar *repeat-delay* 0)
(defvar *repeat-interval* 0)
(defvar *repeat-press* nil)
(defvar *repeat-next* nil)
(defun %clear-repeat-state () (setf *repeat-press* nil *repeat-next* nil))
(defun %reset-repeat-state ()
  (setf *repeat-delay* 0 *repeat-interval* 0)
  (%clear-repeat-state))
(defun set-repeat (&optional (delay 0) (interval 0))
  "Set held-key repeat timing in milliseconds; zero delay disables repeating.

The initial native key-down is preserved, SDL's own repeat key-downs are
suppressed, and Pixelisp emits at most one missed repeat per event pump."
  ;; Validate all arguments before changing either the settings or pending key.
  (check-type delay (integer 0 *))
  (check-type interval (integer 0 *))
  (pixelisp.internal::check-video-ready 'set-repeat)
  (setf *repeat-delay* delay
        *repeat-interval* (if (and (plusp delay) (zerop interval)) delay interval))
  (%clear-repeat-state)
  (values))
(defun get-repeat ()
  "Return the configured repeat delay and interval as a two-item list."
  (pixelisp.internal::check-video-ready 'get-repeat)
  (list *repeat-delay* *repeat-interval*))
(defun %same-pressed-key-p (down up)
  (let ((down-code (px.event:attribute down :keycode))
        (up-code (px.event:attribute up :keycode)))
    (if (and down-code up-code)
        (eql down-code up-code)
        (eql (px.event:attribute down :key) (px.event:attribute up :key)))))
(defun %handle-native-key-repeat (event &optional (now (px.time:get-ticks)))
  "Track native key transitions and return whether EVENT should be queued."
  (case (px.event:type event)
    (:key-down
     (if (px.event:attribute event :repeat)
         ;; SDL-generated repeat events are suppressed even when Lisp repeat is off.
         nil
         (progn
           (if (plusp *repeat-delay*)
               (setf *repeat-press* (apply #'px.event:make-event :key-down
                                          (copy-list (px.event:attributes event)))
                     *repeat-next* (+ now *repeat-delay*))
               (%clear-repeat-state))
           t)))
    (:key-up
     (when (and *repeat-press* (%same-pressed-key-p *repeat-press* event))
       (%clear-repeat-state))
     t)
    (:window-event
     ;; SDL_WINDOWEVENT_FOCUS_LOST is 13. Do not synthesize releases on focus loss.
     (when (= (or (px.event:attribute event :event) -1) 13)
       (%clear-repeat-state))
     t)
    (otherwise t)))
(defun %update-key-repeat (&optional (now (px.time:get-ticks)))
  (when (and *repeat-press* *repeat-next* (>= now *repeat-next*))
    (let ((event (apply #'px.event:make-event :key-down
                        (copy-list (px.event:attributes *repeat-press*)))))
      (setf (px.event:attribute event :repeat) t)
      (px.event:post event)
      ;; Coalesce missed intervals after a long frame or stalled pump.
      (setf *repeat-next* (+ now *repeat-interval*))))
  nil)
(pushnew #'%update-key-repeat pixelisp.internal:*pump-hooks*)
(pushnew #'%reset-repeat-state pixelisp.internal:*shutdown-hooks*)

(in-package #:pixelisp.mouse)
(cffi:defcfun ("SDL_GetRelativeMouseState" %relative) :uint32 (x :pointer) (y :pointer))
(cffi:defcfun ("SDL_ShowCursor" %show) :int (toggle :int))
(cffi:defcfun ("SDL_GetMouseFocus" %focus) :pointer)
(defun get-pos ()
  (pixelisp.internal::check-video-ready 'get-pos)
  (multiple-value-bind (x y) (sdl2:mouse-state) (list x y)))
(defun set-pos (position)
  (pixelisp.internal::check-video-ready 'set-pos)
  (multiple-value-bind (x y) (pixelisp.internal:pair position)
    (sdl2:warp-mouse-in-window (px.display:get-window) x y)) position)
(defun get-rel ()
  (pixelisp.internal::check-video-ready 'get-rel)
  (cffi:with-foreign-objects ((x :int) (y :int))
    (%relative x y) (list (cffi:mem-ref x :int) (cffi:mem-ref y :int))))
(defun get-pressed (&optional (buttons 3))
  (pixelisp.internal::check-video-ready 'get-pressed)
  (multiple-value-bind (x y mask) (sdl2:mouse-state)
    (declare (ignore x y)) (loop for i below buttons collect (logbitp i mask))))
(defun set-visible (visible)
  (pixelisp.internal::check-video-ready 'set-visible)
  (not (zerop (%show (if visible 1 0)))))
(defun get-visible () (pixelisp.internal::check-video-ready 'get-visible) (plusp (%show -1)))
(defun set-relative-mode (enabled)
  (pixelisp.internal::check-video-ready 'set-relative-mode)
  (sdl2:set-relative-mouse-mode enabled))
(defun get-relative-mode ()
  (pixelisp.internal::check-video-ready 'get-relative-mode)
  (sdl2:relative-mouse-mode-p))
(defun get-focused ()
  (pixelisp.internal::check-video-ready 'get-focused)
  (not (cffi:null-pointer-p (%focus))))

(in-package #:pixelisp.locals)
(defconstant +quit+ :quit) (defconstant +keydown+ :key-down) (defconstant +keyup+ :key-up)
(defconstant +mousemotion+ :mouse-motion) (defconstant +mousebuttondown+ :mouse-button-down)
(defconstant +mousebuttonup+ :mouse-button-up) (defconstant +textinput+ :text-input)
(defconstant +resizable+ :resizable) (defconstant +fullscreen+ :fullscreen)
(defconstant +srcalpha+ :srcalpha)
(in-package #:pixelisp.version)
(defparameter +version+ "0.1.0")
(defparameter +pygame-reference+ "2.6.1")
(defun get-sdl-version () (multiple-value-list (sdl2:version)))
