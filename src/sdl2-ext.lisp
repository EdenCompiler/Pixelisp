;;;; Optional native bridge and SDL2-oriented rendering/audio objects.
;;;;
;;;; Window, renderer, and texture objects form an ownership tree. Closing a
;;;; parent closes its children first, so SDL never receives a dangling handle.
;;;; All video methods run on the thread that initialized the video subsystem.
(defpackage #:pixelisp.native
  (:use #:cl) (:export #:ensure-loaded #:available-p #:last-error #:postmix-start #:postmix-read #:postmix-stop))
(in-package #:pixelisp.native)
(defvar *library* nil)
(defvar *build-lock* (bordeaux-threads:make-lock "pixelisp native adapter build"))
(defun ensure-loaded ()
  "Build the small C adapters in ASDF's output cache, then load them once."
  (bordeaux-threads:with-lock-held (*build-lock*)
    (or *library*
        (handler-case
            (let* ((source (asdf:system-relative-pathname "pixelisp" "native/pixelisp-native.c"))
                   (output (asdf:apply-output-translations
                            (asdf:system-relative-pathname "pixelisp" "native/libpixelisp-native.so"))))
              (when (or (not (probe-file output)) (> (file-write-date source) (file-write-date output)))
                (ensure-directories-exist output)
                (let ((flags (remove "" (uiop:split-string
                                          (uiop:run-program '("pkg-config" "--cflags" "--libs" "sdl2" "SDL2_mixer") :output :string)
                                          :separator '(#\Space #\Tab #\Newline)) :test #'string=)))
                  (uiop:run-program (append (list "cc" "-O2" "-fPIC" "-shared" (namestring source) "-o" (namestring output))
                                            flags '("-ldl" "-pthread")) :output :string :error-output :string)))
              (setf *library* (cffi:load-foreign-library output)))
          (error (condition)
            (error 'pixelisp:dependency-error :operation 'native-adapter
                   :message (format nil "Cannot build/load the native adapter. Install a C compiler, pkg-config, SDL2 and SDL2_mixer development files. ~A" condition)))))))
(defun available-p () (handler-case (not (null (ensure-loaded))) (error () nil)))
(cffi:defcfun ("px_native_error" last-error) :string)
(cffi:defcfun ("px_postmix_start" %postmix-start) :int (capacity :size))
(cffi:defcfun ("px_postmix_read" %postmix-read) :size (output :pointer) (capacity :size))
(cffi:defcfun ("px_postmix_stop" %postmix-stop) :void)
(defun postmix-start (&optional (capacity 1048576))
  "Capture mixed PCM into a bounded native ring; overflow discards oldest bytes."
  (check-type capacity (integer 4096 1073741824)) (ensure-loaded)
  (when (minusp (%postmix-start capacity)) (error 'pixelisp:error :operation 'postmix-start :message (last-error))) t)
(defun postmix-read (&optional (maximum 65536))
  "Remove up to MAXIMUM captured PCM bytes without entering Lisp on the audio thread."
  (check-type maximum (integer 0 1073741824)) (ensure-loaded)
  (let ((bytes (make-array maximum :element-type '(unsigned-byte 8))))
    (if (zerop maximum) bytes
        (cffi:with-pointer-to-vector-data (p bytes)
          (subseq bytes 0 (%postmix-read p maximum))))))
(defun postmix-stop () (when *library* (%postmix-stop)) nil)
(pushnew #'postmix-stop pixelisp.internal:*shutdown-hooks*)

(defpackage #:pixelisp.sdl2.video
  (:nicknames #:px.sdl2.video #:pixelisp.sdl2 #:px.sdl2) (:use #:cl) (:shadow #:close #:position)
  (:export #:window #:renderer #:texture #:make-window #:make-renderer #:make-texture
           #:texture-from-surface #:close #:title #:size #:position #:show #:hide
           #:clear #:present #:draw-color #:draw-line #:draw-point #:fill-rect #:draw-texture
           #:texture-size #:texture-alpha #:texture-color #:with-window #:with-renderer))
(in-package #:pixelisp.sdl2.video)
(cffi:defcfun ("SDL_CreateWindow" %window-new) :pointer (title :string) (x :int) (y :int) (w :int) (h :int) (flags :uint32))
(cffi:defcfun ("SDL_DestroyWindow" %window-close) :void (p :pointer))
(cffi:defcfun ("SDL_GetWindowTitle" %title) :string (p :pointer))
(cffi:defcfun ("SDL_SetWindowTitle" %title-set) :void (p :pointer) (title :string))
(cffi:defcfun ("SDL_GetWindowSize" %size) :void (p :pointer) (w :pointer) (h :pointer))
(cffi:defcfun ("SDL_SetWindowSize" %size-set) :void (p :pointer) (w :int) (h :int))
(cffi:defcfun ("SDL_GetWindowPosition" %position) :void (p :pointer) (x :pointer) (y :pointer))
(cffi:defcfun ("SDL_SetWindowPosition" %position-set) :void (p :pointer) (x :int) (y :int))
(cffi:defcfun ("SDL_ShowWindow" %show) :void (p :pointer))
(cffi:defcfun ("SDL_HideWindow" %hide) :void (p :pointer))
(cffi:defcfun ("SDL_CreateRenderer" %renderer-new) :pointer (window :pointer) (index :int) (flags :uint32))
(cffi:defcfun ("SDL_DestroyRenderer" %renderer-close) :void (p :pointer))
(cffi:defcfun ("SDL_SetRenderDrawColor" %color-set) :int (p :pointer) (r :uint8) (g :uint8) (b :uint8) (a :uint8))
(cffi:defcfun ("SDL_GetRenderDrawColor" %color-get) :int (p :pointer) (r :pointer) (g :pointer) (b :pointer) (a :pointer))
(cffi:defcfun ("SDL_SetRenderDrawBlendMode" %blend-set) :int (p :pointer) (mode :int))
(cffi:defcfun ("SDL_RenderClear" %clear) :int (p :pointer))
(cffi:defcfun ("SDL_RenderPresent" %present) :void (p :pointer))
(cffi:defcfun ("SDL_RenderDrawLine" %line) :int (p :pointer) (x1 :int) (y1 :int) (x2 :int) (y2 :int))
(cffi:defcfun ("SDL_RenderDrawPoint" %point) :int (p :pointer) (x :int) (y :int))
(cffi:defcfun ("SDL_RenderFillRect" %fill) :int (p :pointer) (rect :pointer))
(cffi:defcfun ("SDL_RenderCopyEx" %copy) :int (renderer :pointer) (texture :pointer) (source :pointer) (destination :pointer) (angle :double) (center :pointer) (flip :int))
(cffi:defcfun ("SDL_CreateTexture" %texture-new) :pointer (renderer :pointer) (format :uint32) (access :int) (w :int) (h :int))
(cffi:defcfun ("SDL_CreateTextureFromSurface" %texture-surface) :pointer (renderer :pointer) (surface :pointer))
(cffi:defcfun ("SDL_DestroyTexture" %texture-close) :void (p :pointer))
(cffi:defcfun ("SDL_QueryTexture" %texture-query) :int (p :pointer) (format :pointer) (access :pointer) (w :pointer) (h :pointer))
(cffi:defcfun ("SDL_SetTextureBlendMode" %texture-blend) :int (p :pointer) (blend :int))
(cffi:defcfun ("SDL_SetTextureAlphaMod" %texture-alpha-set) :int (p :pointer) (a :uint8))
(cffi:defcfun ("SDL_GetTextureAlphaMod" %texture-alpha-get) :int (p :pointer) (a :pointer))
(cffi:defcfun ("SDL_SetTextureColorMod" %texture-color-set) :int (p :pointer) (r :uint8) (g :uint8) (b :uint8))
(cffi:defcfun ("SDL_GetTextureColorMod" %texture-color-get) :int (p :pointer) (r :pointer) (g :pointer) (b :pointer))
(cffi:defcstruct native-rect (x :int) (y :int) (w :int) (h :int))
(defclass video-resource (pixelisp.internal:resource)
  ((parent :initarg :parent :initform nil :reader %parent)
   (children :initform nil :accessor %children)))
(defclass window (video-resource) ())
(defclass renderer (video-resource) ())
(defclass texture (video-resource) ())
(defmethod pixelisp.internal:ensure-live ((object video-resource))
  (call-next-method) (when (%parent object) (pixelisp.internal:ensure-live (%parent object))) object)
(defun %pointer (object)
  (pixelisp.internal:check-video-thread) (pixelisp.internal:ensure-live object) (pixelisp.internal:handle object))
(defun %new (class ptr &optional parent)
  (let ((object (pixelisp.internal:register-resource
                 (make-instance class :handle (pixelisp.devices.internal:check-pointer ptr 'create-video-resource) :parent parent))))
    (when parent (push object (%children parent))) object))
(defmethod pixelisp.internal:dispose :before ((object video-resource))
  (pixelisp.internal:check-video-thread)
  (dolist (child (copy-list (%children object))) (pixelisp.internal:dispose child)))
(defmethod pixelisp.internal:dispose ((object window)) (%window-close (pixelisp.internal:handle object)))
(defmethod pixelisp.internal:dispose ((object renderer)) (%renderer-close (pixelisp.internal:handle object)))
(defmethod pixelisp.internal:dispose ((object texture)) (%texture-close (pixelisp.internal:handle object)))
(defun close (object) (pixelisp.internal:dispose object))
(defun make-window (&key (title "Pixelisp") (size '(800 600)) position resizable hidden borderless)
  "Create an independent SDL window. Close its children before destroying it."
  (pixelisp.internal:check-video-thread)
  (px.display:init)
  (destructuring-bind (w h) size
    (check-type w (integer 1 *)) (check-type h (integer 1 *))
    (%new 'window (%window-new title (if position (first position) #x2fff0000)
                             (if position (second position) #x2fff0000) w h
                             (logior (if resizable #x20 0) (if hidden #x8 #x4) (if borderless #x10 0))))))
(defun make-renderer (window &key accelerated vsync)
  "Create a renderer owned by WINDOW. Software rendering works with SDL's dummy driver."
  ;; SDL's renderer backends can leave floating-point exception flags set on
  ;; return (notably the X11/Mesa path). Keep those native side effects local
  ;; to the call instead of changing the application's floating-point mode.
  (pixelisp.internal:with-native-context
    (check-type window window)
    (let ((object (%new 'renderer (%renderer-new (%pointer window) -1 (logior (if accelerated 2 0) (if vsync 4 0))) window)))
      (pixelisp.devices.internal:check-code (%blend-set (%pointer object) 1) 'renderer-blend) object)))
(defun make-texture (renderer size &key (access :static))
  "Allocate an RGBA texture; ACCESS is :STATIC, :STREAMING, or :TARGET."
  (pixelisp.internal:with-native-context
    (check-type renderer renderer)
    (let ((code (or (cl:position access '(:static :streaming :target)) (error 'type-error :datum access :expected-type '(member :static :streaming :target)))))
      (destructuring-bind (w h) size
        (%new 'texture (%texture-new (%pointer renderer) sdl2:+pixelformat-rgba32+ code w h) renderer)))))
(defun texture-from-surface (renderer surface)
  "Upload a surface into a new renderer-owned texture. SDL copies the pixels."
  (pixelisp.internal:with-native-context
    (check-type renderer renderer)
    (let ((object (%new 'texture (%texture-surface (%pointer renderer) (pixelisp.internal:%ptr (pixelisp.internal:surface-handle surface))) renderer)))
      (pixelisp.devices.internal:check-code (%texture-blend (%pointer object) 1) 'texture-blend) object)))
(defun title (window) (%title (%pointer window)))
(defun (setf title) (value window) (%title-set (%pointer window) value) value)
(defun size (window) (cffi:with-foreign-objects ((w :int) (h :int)) (%size (%pointer window) w h) (list (cffi:mem-ref w :int) (cffi:mem-ref h :int))))
(defun (setf size) (value window) (%size-set (%pointer window) (first value) (second value)) value)
(defun position (window) (cffi:with-foreign-objects ((x :int) (y :int)) (%position (%pointer window) x y) (list (cffi:mem-ref x :int) (cffi:mem-ref y :int))))
(defun (setf position) (value window) (%position-set (%pointer window) (first value) (second value)) value)
(defun show (window) (%show (%pointer window)) window)
(defun hide (window) (%hide (%pointer window)) window)
(defun draw-color (renderer)
  (cffi:with-foreign-objects ((r :uint8) (g :uint8) (b :uint8) (a :uint8))
    (pixelisp.devices.internal:check-code (%color-get (%pointer renderer) r g b a) 'draw-color)
    (mapcar (lambda (p) (cffi:mem-ref p :uint8)) (list r g b a))))
(defun (setf draw-color) (color renderer)
  (multiple-value-bind (r g b a) (pixelisp.internal:rgba color)
    (pixelisp.devices.internal:check-code (%color-set (%pointer renderer) r g b a) 'draw-color)) color)
(defun clear (renderer &optional color)
  (pixelisp.internal:with-native-context
    (when color (setf (draw-color renderer) color))
    (pixelisp.devices.internal:check-code (%clear (%pointer renderer)) 'clear) renderer))
(defun present (renderer) (pixelisp.internal:with-native-context (%present (%pointer renderer)) renderer))
(defun draw-line (renderer start end)
  (pixelisp.internal:with-native-context
    (pixelisp.devices.internal:check-code (%line (%pointer renderer) (first start) (second start) (first end) (second end)) 'draw-line) renderer))
(defun draw-point (renderer point)
  (pixelisp.internal:with-native-context
    (pixelisp.devices.internal:check-code (%point (%pointer renderer) (first point) (second point)) 'draw-point) renderer))
(defun %put-rect (pointer value)
  (let ((rect (pixelisp.internal:as-rect value)))
    (setf (cffi:foreign-slot-value pointer '(:struct native-rect) 'x) (px.rect:x rect)
          (cffi:foreign-slot-value pointer '(:struct native-rect) 'y) (px.rect:y rect)
          (cffi:foreign-slot-value pointer '(:struct native-rect) 'w) (px.rect:width rect)
          (cffi:foreign-slot-value pointer '(:struct native-rect) 'h) (px.rect:height rect))))
(defun fill-rect (renderer rect)
  (pixelisp.internal:with-native-context
    (cffi:with-foreign-object (p '(:struct native-rect))
      (%put-rect p rect) (pixelisp.devices.internal:check-code (%fill (%pointer renderer) p) 'fill-rect)) renderer))
(defun draw-texture (renderer texture &key source destination (angle 0d0) flip-x flip-y)
  "Copy TEXTURE into RENDERER with optional rectangles, rotation and flips."
  (pixelisp.internal:with-native-context
    (check-type renderer renderer) (check-type texture texture)
    (unless (eq renderer (%parent texture)) (error 'pixelisp:error :operation 'draw-texture :message "Texture belongs to a different renderer."))
    (cffi:with-foreign-objects ((s '(:struct native-rect)) (d '(:struct native-rect)))
      (when source (%put-rect s source)) (when destination (%put-rect d destination))
      (pixelisp.devices.internal:check-code
       (%copy (%pointer renderer) (%pointer texture) (if source s (cffi:null-pointer)) (if destination d (cffi:null-pointer))
              (coerce angle 'double-float) (cffi:null-pointer) (logior (if flip-x 1 0) (if flip-y 2 0))) 'draw-texture)) renderer))
(defun texture-size (texture)
  (cffi:with-foreign-objects ((w :int) (h :int))
    (pixelisp.devices.internal:check-code (%texture-query (%pointer texture) (cffi:null-pointer) (cffi:null-pointer) w h) 'texture-size)
    (list (cffi:mem-ref w :int) (cffi:mem-ref h :int))))
(defun texture-alpha (texture)
  (cffi:with-foreign-object (a :uint8) (pixelisp.devices.internal:check-code (%texture-alpha-get (%pointer texture) a) 'texture-alpha) (cffi:mem-ref a :uint8)))
(defun (setf texture-alpha) (value texture) (check-type value (unsigned-byte 8)) (pixelisp.devices.internal:check-code (%texture-alpha-set (%pointer texture) value) 'texture-alpha) value)
(defun texture-color (texture)
  (cffi:with-foreign-objects ((r :uint8) (g :uint8) (b :uint8))
    (pixelisp.devices.internal:check-code (%texture-color-get (%pointer texture) r g b) 'texture-color)
    (mapcar (lambda (p) (cffi:mem-ref p :uint8)) (list r g b))))
(defun (setf texture-color) (value texture)
  (pixelisp.devices.internal:check-code (%texture-color-set (%pointer texture) (first value) (second value) (third value)) 'texture-color) value)
(defmacro with-window ((var &rest options) &body body) `(let ((,var (make-window ,@options))) (unwind-protect (progn ,@body) (close ,var))))
(defmacro with-renderer ((var window &rest options) &body body) `(let ((,var (make-renderer ,window ,@options))) (unwind-protect (progn ,@body) (close ,var))))

;;;; Raw queued audio deliberately uses SDL's queue API. C owns the realtime
;;;; callback, and user Lisp runs only when QUEUE/DEQUEUE are called explicitly.
(defpackage #:pixelisp.sdl2.audio
  (:nicknames #:px.sdl2.audio) (:use #:cl) (:shadow #:close)
  (:export #:audio-device #:devices #:open-device #:close #:pause #:start #:queue #:dequeue #:queued-size #:clear-queue #:format-info))
(in-package #:pixelisp.sdl2.audio)
(cffi:defcstruct audio-spec (frequency :int) (format :uint16) (channels :uint8) (silence :uint8) (samples :uint16) (padding :uint16) (size :uint32) (callback :pointer) (userdata :pointer))
(cffi:defcfun ("SDL_GetNumAudioDevices" %device-count) :int (capture :int))
(cffi:defcfun ("SDL_GetAudioDeviceName" %device-name) :string (index :int) (capture :int))
(cffi:defcfun ("SDL_OpenAudioDevice" %open) :uint32 (name :pointer) (capture :int) (desired :pointer) (obtained :pointer) (changes :int))
(cffi:defcfun ("SDL_CloseAudioDevice" %close) :void (id :uint32))
(cffi:defcfun ("SDL_PauseAudioDevice" %pause) :void (id :uint32) (paused :int))
(cffi:defcfun ("SDL_QueueAudio" %queue) :int (id :uint32) (data :pointer) (size :uint32))
(cffi:defcfun ("SDL_DequeueAudio" %dequeue) :uint32 (id :uint32) (data :pointer) (size :uint32))
(cffi:defcfun ("SDL_GetQueuedAudioSize" %queued) :uint32 (id :uint32))
(cffi:defcfun ("SDL_ClearQueuedAudio" %clear) :void (id :uint32))
(defclass audio-device (pixelisp.internal:resource)
  ((capture :initarg :capture :reader %capture) (format-info :initarg :format-info :reader format-info)))
(defun %id (device) (pixelisp.internal:ensure-live device) (pixelisp.internal:handle device))
(defun devices (&key capture)
  "List available SDL recording or playback devices without opening any device."
  (pixelisp.devices.internal:init-flags #x10)
  (loop for i below (pixelisp.devices.internal:check-code (%device-count (if capture 1 0)) 'audio-devices)
        collect (%device-name i (if capture 1 0))))
(defun open-device (&key name capture (frequency 44100) (format :s16) (channels 2) (samples 1024))
  "Open a paused PCM device. Queue/dequeue bytes in the exact FORMAT-INFO format."
  (check-type frequency (integer 1 *)) (check-type channels (integer 1 8)) (check-type samples (integer 1 65535))
  (pixelisp.devices.internal:init-flags #x10)
  (let ((code (or (cdr (assoc format '((:u8 . #x8) (:s8 . #x8008) (:u16 . #x10) (:s16 . #x8010) (:s32 . #x8020) (:f32 . #x8120))))
                  (error 'type-error :datum format :expected-type '(member :u8 :s8 :u16 :s16 :s32 :f32)))))
    (cffi:with-foreign-objects ((desired '(:struct audio-spec)) (obtained '(:struct audio-spec)))
      (dotimes (i (cffi:foreign-type-size '(:struct audio-spec))) (setf (cffi:mem-aref desired :uint8 i) 0))
      (setf (cffi:foreign-slot-value desired '(:struct audio-spec) 'frequency) frequency
            (cffi:foreign-slot-value desired '(:struct audio-spec) 'format) code
            (cffi:foreign-slot-value desired '(:struct audio-spec) 'channels) channels
            (cffi:foreign-slot-value desired '(:struct audio-spec) 'samples) samples)
      (flet ((open-with (name-pointer)
               (let ((id (%open name-pointer (if capture 1 0) desired obtained 0)))
                 (when (zerop id) (pixelisp.devices.internal:check-code -1 'open-audio-device))
                 (pixelisp.internal:register-resource
                  (make-instance 'audio-device :handle id :capture capture
                                 :format-info (list :frequency frequency :format format :channels channels :samples samples))))))
        (if name (cffi:with-foreign-string (p name :encoding :utf-8) (open-with p)) (open-with (cffi:null-pointer)))))))
(defmethod pixelisp.internal:dispose ((device audio-device)) (%close (pixelisp.internal:handle device)))
(defun close (device) (pixelisp.internal:dispose device))
(defun pause (device &optional (paused t)) (%pause (%id device) (if paused 1 0)) device)
(defun start (device) (pause device nil))
(defun queue (device bytes)
  "Copy PCM octets to a playback queue; SDL owns its copy after this call."
  (when (%capture device) (error 'pixelisp:error :operation 'queue :message "Cannot queue audio to a recording device."))
  (let ((data (coerce bytes '(vector (unsigned-byte 8)))))
    (unless (zerop (length data))
      (cffi:with-pointer-to-vector-data (p data)
        (pixelisp.devices.internal:check-code (%queue (%id device) p (length data)) 'queue-audio)))) device)
(defun dequeue (device &optional (maximum 65536))
  "Remove up to MAXIMUM recorded PCM octets from a recording device."
  (unless (%capture device) (error 'pixelisp:error :operation 'dequeue :message "Cannot dequeue audio from a playback device."))
  (check-type maximum (integer 0 1073741824))
  (let ((data (make-array maximum :element-type '(unsigned-byte 8))))
    (if (zerop maximum) data (cffi:with-pointer-to-vector-data (p data) (subseq data 0 (%dequeue (%id device) p maximum))))))
(defun queued-size (device) (%queued (%id device)))
(defun clear-queue (device) (%clear (%id device)) device)

(defpackage #:pixelisp.sdl2.mixer
  (:nicknames #:px.sdl2.mixer) (:use #:cl)
  (:export #:start-capture #:read-capture #:stop-capture))
(in-package #:pixelisp.sdl2.mixer)
(defun start-capture (&key (capacity 1048576))
  "Capture postmix PCM in a bounded native ring after PX.MIXER:INIT."
  (pixelisp.native:postmix-start capacity))
(defun read-capture (&optional (maximum 65536)) (pixelisp.native:postmix-read maximum))
(defun stop-capture () (pixelisp.native:postmix-stop))
