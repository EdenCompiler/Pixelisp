;;;; Native image, SDL_ttf and SDL_mixer capabilities.
(defpackage #:pixelisp.image
  (:use #:cl) (:nicknames #:px.image) (:shadow #:load)
  (:export #:load #:load-bytes #:save #:save-bytes #:from-string #:to-string #:from-bytes #:to-bytes
           #:from-buffer #:get-extended #:get-sdl-image-version))
(defpackage #:pixelisp.font
  (:use #:cl) (:nicknames #:px.font) (:shadow #:get #:get-error #:close)
  (:export #:init #:quit #:get-init #:font #:make-font #:sys-font #:sysfont
           #:load-font-bytes
           #:get-fonts #:match-font #:get-default-font #:render #:size #:metrics
           #:get-height #:get-linesize #:get-ascent #:get-descent
           #:set-script
           #:get-bold #:set-bold #:get-italic #:set-italic #:get-underline
           #:set-underline #:get-strikethrough #:set-strikethrough #:close
           #:get-sdl-ttf-version))
(defpackage #:pixelisp.sysfont
  (:use #:cl) (:nicknames #:px.sysfont)
  (:import-from #:pixelisp.font #:sys-font #:sysfont #:get-fonts #:match-font)
  (:export #:sys-font #:sysfont #:get-fonts #:match-font))
(defpackage #:pixelisp.ftfont
  (:use #:cl) (:nicknames #:px.ftfont)
  (:export #:font #:make-font #:sys-font #:sysfont #:render #:size #:metrics
           #:get-fonts #:match-font #:get-default-font))
(defpackage #:pixelisp.mixer
  (:use #:cl) (:nicknames #:px.mixer) (:shadow #:close)
  (:export #:init #:pre-init #:quit #:get-init #:get-busy #:get-num-channels
           #:set-num-channels #:set-reserved #:find-channel #:sound #:make-sound
           #:channel #:make-channel #:play #:stop #:pause #:unpause #:fadeout
           #:set-endevent #:get-endevent
           #:set-volume #:get-volume #:get-length #:get-raw #:get-num-channels
           #:get-sound #:queue #:get-queue #:update #:close #:sample-format
           #:sound-frame-count #:sound-channels #:sound-element-type
           #:sound-sample-ref #:sound-sample-set #:get-sdl-mixer-version
           #:load-sound-bytes))
(defpackage #:pixelisp.mixer.music
  (:use #:cl) (:nicknames #:px.mixer.music) (:shadow #:load)
  (:export #:load #:load-bytes #:unload #:play #:stop #:pause #:unpause #:rewind #:fadeout
           #:set-endevent #:get-endevent
           #:get-busy #:set-volume #:get-volume #:get-pos #:set-pos #:queue #:update))
(in-package #:pixelisp.image)

(cffi:defcfun ("SDL_GetError" %sdl-error) :string)
(cffi:defcfun ("SDL_RWFromConstMem" %rw-from-const-mem) :pointer
  (memory :pointer) (size :int))
(cffi:defcfun ("SDL_RWclose" %rw-close) :int (source :pointer))
(cffi:defcfun ("IMG_Load_RW" %img-load-rw) :pointer (source :pointer) (freesrc :int))
(cffi:defcfun ("IMG_LoadTyped_RW" %img-load-typed-rw) :pointer
  (source :pointer) (freesrc :int) (type :string))

(defun get-extended () t)
(defun get-sdl-image-version () (sdl2-image:linked-version))
(defgeneric load (source &key namehint preserve-format)
  (:documentation "Decode an image pathname, binary stream, or encoded octet vector into an owned Surface.
NAMEHINT is an optional SDL_image format name (for example, \"PNG\") used for in-memory data.
When PRESERVE-FORMAT is true, retain SDL_image's decoded pixel format and palette."))
(defun %check-preserve-format (value)
  (unless (member value '(nil t))
    (error 'type-error :datum value :expected-type 'boolean))
  value)
(defmethod load ((filename (eql nil)) &key namehint preserve-format)
  (declare (ignore namehint))
  (%check-preserve-format preserve-format)
  (error 'type-error :datum filename :expected-type '(or pathname string stream (vector (unsigned-byte 8)))))
(defmethod load ((filename pathname) &key namehint preserve-format)
  (declare (ignore namehint))
  (%check-preserve-format preserve-format)
  (pixelisp.internal:wrap-surface (sdl2-image:load-image filename) :owned t :alpha t
                                  :preserve-format preserve-format))
(defmethod load ((filename string) &key namehint preserve-format)
  (declare (ignore namehint))
  (%check-preserve-format preserve-format)
  (pixelisp.internal:wrap-surface (sdl2-image:load-image filename) :owned t :alpha t
                                  :preserve-format preserve-format))
(defun %normalize-namehint (namehint)
  "Return a supported SDL_image format name, or NIL when no hint was supplied."
  (when namehint
    (unless (or (stringp namehint) (symbolp namehint))
      (error 'type-error :datum namehint :expected-type '(or string symbol)))
    (let* ((text (string-upcase (string namehint)))
           (extension (pathname-type text))
           (format (or extension (string-left-trim "." text))))
      ;; Let the installed SDL_image decide which codecs it supports; avoid a
      ;; fixed list that would hide newer codecs. Reject malformed hints here.
      (unless (and (plusp (length format))
                   (every (lambda (character) (find character "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"))
                          format))
        (error 'pixelisp:error :operation 'load
               :message (format nil "Unsupported image name hint: ~A" text)))
      format)))
(defun load-bytes (bytes &key namehint preserve-format)
  "Decode encoded image-file octets into an owned Surface. FROM-BYTES remains for raw pixels.
When PRESERVE-FORMAT is true, retain SDL_image's decoded pixel format and palette."
  (%load-encoded-octets bytes namehint preserve-format))
(defun %load-encoded-octets (bytes namehint preserve-format)
  "Decode encoded file bytes while retaining their owned CFFI copy through SDL_image."
  ;; Validate the hint before allocating any native resources.
  (let ((preserve-format (%check-preserve-format preserve-format))
        (format (%normalize-namehint namehint)))
    (unless (typep bytes '(vector (unsigned-byte 8)))
      (error 'type-error :datum bytes :expected-type '(vector (unsigned-byte 8))))
    (let ((length (length bytes)))
      (when (zerop length)
        (error 'pixelisp:error :operation 'load :message "Image data is empty"))
      (when (> length #x7fffffff)
        (error 'pixelisp:error :operation 'load :message "Image data exceeds SDL's supported size"))
      (let ((memory (cffi:foreign-alloc :uint8 :count length)))
        (unwind-protect
             (progn
               (dotimes (index length)
                 (setf (cffi:mem-aref memory :uint8 index) (aref bytes index)))
               (let ((rw (%rw-from-const-mem memory length)))
                 (when (cffi:null-pointer-p rw)
                   (error 'pixelisp:error :operation 'load
                          :message (or (%sdl-error) "Unable to create image byte stream")))
                 ;; Keep both the RW object and backing bytes alive through decode, then close RW.
                 (unwind-protect
                      (let ((native (if format
                                        (%img-load-typed-rw rw 0 format)
                                        (%img-load-rw rw 0))))
                        (when (cffi:null-pointer-p native)
                          (error 'pixelisp:error :operation 'load
                                 :message (or (%sdl-error) "Unsupported or malformed image data")))
                        (pixelisp.internal:wrap-surface native :owned t :alpha t
                                                        :preserve-format preserve-format))
                   (%rw-close rw))))
          (cffi:foreign-free memory))))))
(defmethod load ((bytes vector) &key namehint preserve-format)
  (load-bytes bytes :namehint namehint :preserve-format preserve-format))
(defmethod load ((stream stream) &key namehint preserve-format)
  "Decode encoded bytes from STREAM without closing the caller-owned stream."
  (%check-preserve-format preserve-format)
  (unless (and (input-stream-p stream)
               (subtypep (stream-element-type stream) '(unsigned-byte 8)))
    (error 'simple-type-error :datum stream :expected-type 'stream
           :format-control "Expected a binary input stream containing octets; received ~S"
           :format-arguments (list stream)))
  (%normalize-namehint namehint)
  (let ((bytes (make-array 0 :element-type '(unsigned-byte 8)
                            :adjustable t :fill-pointer 0)))
    (loop for byte = (read-byte stream nil nil) while byte do (vector-push-extend byte bytes))
    (%load-encoded-octets bytes namehint preserve-format)))
(cffi:defcfun ("IMG_SaveJPG" %save-jpg) :int (surface :pointer) (file :string) (quality :int))
(cffi:defcfun ("SDL_SaveBMP_RW" %save-bmp) :int (surface :pointer) (rw :pointer) (free :int))
(cffi:defcfun ("SDL_RWFromFile" %rw-file) :pointer (file :string) (mode :string))
(cffi:defcfun ("SDL_CreateRGBSurfaceWithFormatFrom" %surface-from) :pointer
  (pixels :pointer) (width :int) (height :int) (depth :int) (pitch :int) (format :uint32))
(defun %save-file (surface filename quality)
  "Write PNG, JPEG, or BMP according to the filename extension."
  (let* ((path (namestring (pathname filename)))
         (kind (string-downcase (or (pathname-type filename) "bmp")))
         (native (pixelisp.internal:surface-handle surface))
         (rc (cond ((string= kind "png") (sdl2-image:save-png native path) 0)
                   ((member kind '("jpg" "jpeg") :test #'string=)
                    (check-type quality (integer 0 100))
                    (%save-jpg (pixelisp.internal:%ptr native) path quality))
                   (t (let ((rw (%rw-file path "wb")))
                        (when (cffi:null-pointer-p rw)
                          (error 'pixelisp:error :operation 'save
                                 :message (or (%sdl-error) "Unable to open output file")))
                        (%save-bmp (pixelisp.internal:%ptr native) rw 1))))))
    (when (minusp rc) (error 'pixelisp:error :operation 'save :message "Unable to save image"))
    filename))
(defun %format (format &optional (operation 'from-string))
  (let ((name (substitute #\_ #\- (string-upcase (string format)))))
    (unless (member name (if (eq operation 'to-string)
                             '("RGB" "RGBA" "RGBX" "ARGB" "BGRA" "BGR"
                               "RGBA_PREMULT" "ARGB_PREMULT")
                             '("RGB" "RGBA" "RGBX" "ARGB" "BGRA" "BGR"))
                    :test #'string=)
      (error 'pixelisp:unsupported-feature :operation operation
             :message (if (eq operation 'to-string)
                          "Use RGB, RGBA, RGBX, ARGB, BGRA, BGR, RGBA_PREMULT or ARGB_PREMULT output bytes"
                          "Use RGB, RGBA, RGBX, ARGB, BGRA or BGR pixel bytes")))
    name))
(defun from-string (bytes size format &optional flipped)
  "Copy packed octets into a surface. SIZE is (width height); FLIPPED reverses rows."
  (unless (typep bytes '(vector (unsigned-byte 8)))
    (error 'type-error :datum bytes :expected-type '(vector (unsigned-byte 8))))
  (multiple-value-bind (width height) (pixelisp.internal:pair size)
    (let* ((fmt (%format format)) (channels (length fmt))
           (surface (px.surface:make-surface size :alpha (= channels 4))))
      (unless (= (length bytes) (* width height channels))
        (pixelisp.internal:dispose surface)
        (error 'pixelisp:error :operation 'from-string :message "Pixel byte count does not match dimensions"))
      (dotimes (y height surface)
        (dotimes (x width)
          (let* ((offset (* channels (+ x (* width (if flipped (- height 1 y) y)))))
                 (r (elt bytes (+ offset (position #\R fmt))))
                 (g (elt bytes (+ offset (position #\G fmt))))
                 (b (elt bytes (+ offset (position #\B fmt))))
                 (a (if (find #\A fmt) (elt bytes (+ offset (position #\A fmt))) 255)))
            (px.surface:set-at surface (list x y) (list r g b a))))))))
(defun to-string (surface format &optional flipped)
  "Return packed octets in FORMAT, ordered by rows. Premultiplied output uses per-pixel alpha."
  (let* ((fmt (%format format 'to-string))
         (premultiplied (member fmt '("RGBA_PREMULT" "ARGB_PREMULT") :test #'string=))
         (order (if premultiplied (subseq fmt 0 4) fmt))
         (channels (length order))
         (width (px.surface:width surface)) (height (px.surface:height surface))
         (bytes (make-array (* width height channels) :element-type '(unsigned-byte 8))))
    ;; The wrapper's alpha flag can be set for compatibility even when a native
    ;; pixel format has no alpha mask (for example an imported RGBX buffer).
    ;; pygame's premultiplied export requires real per-pixel alpha storage.
    (when (and premultiplied (zerop (fourth (px.surface:get-masks surface))))
      (error 'pixelisp:unsupported-feature :operation 'to-string
             :message "Premultiplied output requires a surface with a per-pixel alpha mask"))
    (dotimes (y height bytes)
      (dotimes (x width)
        (multiple-value-bind (r g b a)
            (pixelisp.internal:rgba (px.surface:get-at surface (list x (if flipped (- height 1 y) y))))
          (when premultiplied
            ;; pygame 2.6.1 uses integer floor division for each color channel.
            (setf r (floor (* r a) 255)
                  g (floor (* g a) 255)
                  b (floor (* b a) 255)))
          (loop for channel across order for k from 0 do
            (setf (aref bytes (+ k (* channels (+ x (* width y)))))
                  (case channel (#\R r) (#\G g) (#\B b) (#\A a) (#\X 255)))))))))
(setf (fdefinition 'from-bytes) #'from-string (fdefinition 'to-bytes) #'to-string)
(defun from-buffer (pointer size format &key owner byte-count)
  "Share caller-owned foreign packed RGBA memory. OWNER is retained until surface disposal.
The pointer must remain valid and writable for that whole lifetime. Use FROM-STRING to copy Lisp vectors."
  (unless (cffi:pointerp pointer) (error 'type-error :datum pointer :expected-type 'cffi:foreign-pointer))
  (when (cffi:null-pointer-p pointer)
    (error 'type-error :datum pointer :expected-type 'cffi:foreign-pointer))
  (when byte-count (check-type byte-count (integer 0 *)))
  (multiple-value-bind (width height) (pixelisp.internal:pair size)
    (check-type width (integer 1 *)) (check-type height (integer 1 *))
    (let* ((fmt (%format format)) (depth (* 8 (length fmt)))
           ;; SDL's byte-array formats; the 32-bit aliases account for host endianness.
           (pixel-format (cond ((string= fmt "RGB") #x17101803)
                               ((string= fmt "BGR") #x17401803)
                               ((string= fmt "RGBA") #x16762004)
                               ((string= fmt "BGRA") #x16362004)
                               ((string= fmt "ARGB") #x16862004)
                               (t #x16561804))))
      (unless (= depth 32)
        (error 'pixelisp:unsupported-feature :operation 'from-buffer :message "Shared surfaces require a 32-bit pixel format; use from-string for RGB/BGR"))
      (when (and byte-count (< byte-count (* width height (length fmt))))
        (error 'pixelisp:error :operation 'from-buffer :message "Foreign buffer is too short"))
      (let ((native (%surface-from pointer width height depth (* width (length fmt)) pixel-format)))
        (when (cffi:null-pointer-p native)
          (error 'pixelisp:error :operation 'from-buffer :message "SDL rejected pixel buffer"))
        (pixelisp.internal:wrap-surface (sdl2-ffi::make-sdl-surface :ptr native)
                                         :owned t :alpha (= depth 32) :parent owner :preserve-format t)))))

(in-package #:pixelisp.font)
(defclass font (pixelisp.internal:resource)
  ((path :initarg :path :reader %path) (point-size :initarg :point-size :reader %point-size)
   ;; SDL_ttf may continue reading the RWops after TTF_OpenFontRW returns.
   ;; Memory-backed fonts therefore own both objects until disposal.
   (rwops :initarg :rwops :initform nil :accessor %font-rwops)
   (memory :initarg :memory :initform nil :accessor %font-memory)))
(cffi:defcfun ("TTF_GetFontStyle" %style) :int (font :pointer))
(cffi:defcfun ("TTF_SetFontStyle" %set-style) :void (font :pointer) (style :int))
(cffi:defcfun ("TTF_FontHeight" %height) :int (font :pointer))
(cffi:defcfun ("TTF_FontLineSkip" %lineskip) :int (font :pointer))
(cffi:defcfun ("TTF_FontAscent" %ascent) :int (font :pointer))
(cffi:defcfun ("TTF_FontDescent" %descent) :int (font :pointer))
(cffi:defcfun ("TTF_GlyphMetrics32" %glyph-metrics) :int
  (font :pointer) (character :uint32) (minx :pointer) (maxx :pointer)
  (miny :pointer) (maxy :pointer) (advance :pointer))
;; Added in SDL_ttf 2.20.0. Resolve at call time so older SDL_ttf libraries
;; can still load Pixelisp and report this optional feature as unavailable.
(defun %font-script-function ()
  (ignore-errors (cffi:foreign-symbol-pointer "TTF_SetFontScriptName")))
(defun init () (unless (get-init) (sdl2-ttf:init)) t)
(defun get-init () (plusp (sdl2-ttf:was-init)))
(defun quit ()
  "Close live Font resources before shutting down SDL_ttf."
  (when (get-init)
    (dolist (resource pixelisp.internal:*resources*)
      (when (typep resource 'font) (pixelisp.internal:dispose resource)))
    (sdl2-ttf:quit))
  nil)
(defun get-sdl-ttf-version () (sdl2-ttf:linked-version))
(defun %fontconfig (program arguments)
  (ignore-errors (string-trim '(#\Space #\Tab #\Newline #\Return)
    (uiop:run-program (cons program arguments) :output :string :error-output nil))))
(defun match-font (name &key bold italic)
  (let* ((family (if (listp name) (format nil "~{~A~^,~}" name) (or name "sans")))
         (pattern (format nil "~A~A~A" family (if bold ":weight=bold" "") (if italic ":slant=italic" "")))
         (path (%fontconfig "fc-match" (list "-f" "%{file}" pattern))))
    (cond ((and path (plusp (length path)) (probe-file path)) path)
          ((probe-file "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
           "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"))))
(defun get-default-font ()
  "Return the bundled DejaVu Sans font; fall back to system sans if unavailable."
  (let ((bundled (ignore-errors
                   (asdf:system-relative-pathname "pixelisp" "assets/fonts/DejaVuSans.ttf"))))
    (or (and bundled (probe-file bundled) (namestring bundled))
        (match-font "sans")
        (error 'pixelisp:dependency-error :operation 'get-default-font
               :message "Bundled font is missing; pass a font pathname or install a system TrueType font"))))
(defun get-fonts ()
  (let ((output (%fontconfig "fc-list" (list "-f" (format nil "%{family}~%")))))
    (remove-duplicates (mapcar #'string-downcase (uiop:split-string (or output "") :separator '(#\Newline))) :test #'string=)))
(declaim (ftype function %make-font-from-source)) ; Implemented in FONT-MEMORY.
(defun make-font (&optional filename (point-size 16))
  "Open a font from a path, encoded octets or binary stream; NIL selects the bundled font."
  (check-type point-size (integer 1 *))
  (when (> point-size #x7fffffff)
    (error 'pixelisp:error :operation 'make-font :message "Font point size exceeds SDL's supported integer range"))
  (when (or (typep filename '(vector (unsigned-byte 8))) (streamp filename))
    (return-from make-font (%make-font-from-source filename point-size)))
  (init)
  (let* ((path (or filename (get-default-font)))
         (native (sdl2-ttf:open-font path point-size))
         (complete nil))
    (unwind-protect
         (progn
           (trivial-garbage:cancel-finalization native)
           (let ((resource (pixelisp.internal:register-resource
                            (make-instance 'font :handle native :path path :point-size point-size))))
             (setf complete t)
             resource))
      (unless complete (sdl2-ttf:close-font native)))))
(defun font (&optional filename (point-size 16)) (make-font filename point-size))
(defun sys-font (name point-size &key bold italic)
  (let ((font (make-font (or (match-font name :bold bold :italic italic) (get-default-font)) point-size)))
    (set-bold font bold) (set-italic font italic) font))
(setf (fdefinition 'sysfont) #'sys-font)
(defun %ptr (font)
  (check-type font font)
  (pixelisp.internal:ensure-live font)
  (pixelisp.internal:%ptr (pixelisp.internal:handle font)))
(defun %valid-script-name-p (script)
  (and (stringp script) (= (length script) 4)
       (every (lambda (character)
                (or (<= (char-code #\A) (char-code character) (char-code #\Z))
                    (<= (char-code #\a) (char-code character) (char-code #\z))))
              script)))
(defun set-script (font script)
  "Set FONT's four-letter ISO 15924 script tag for HarfBuzz text shaping.

This is a per-font setting and requires SDL_ttf 2.20.0 or newer compiled with
HarfBuzz support. UTF-8 rendering, style controls and metric queries remain
available after script selection. Return SCRIPT on success."
  ;; Validate before resolving or calling the native function so malformed
  ;; tags never mutate native font state.
  (unless (%valid-script-name-p script)
    (if (stringp script)
        (error 'pixelisp:error :operation 'set-script
               :message "Script must be exactly four ASCII letters (an ISO 15924 tag).")
        (error 'type-error :datum script :expected-type 'string)))
  (let ((font-pointer (%ptr font))
        (function (%font-script-function)))
    (when (or (null function) (cffi:null-pointer-p function))
      (error 'pixelisp:unsupported-feature :operation 'set-script
             :message "The loaded SDL_ttf library does not provide TTF_SetFontScriptName (SDL_ttf 2.20.0 or newer is required)."))
    (unless (zerop (cffi:foreign-funcall-pointer function ()
                    :pointer font-pointer :string script :int))
      ;; SDL_ttf also returns -1 when built without HarfBuzz support.
      (let ((native-message (pixelisp.image::%sdl-error)))
        (error 'pixelisp:error :operation 'set-script
               :message (if (and native-message (plusp (length native-message)))
                            native-message
                            "TTF_SetFontScriptName returned -1; this SDL_ttf build may lack HarfBuzz support."))))
    script))
(defmethod pixelisp.internal:dispose ((font font))
  (unless (pixelisp.internal:resource-disposed-p font)
    (unwind-protect
         (sdl2-ttf:close-font (pixelisp.internal:handle font))
      (when (and (%font-rwops font) (not (cffi:null-pointer-p (%font-rwops font))))
        (pixelisp.image::%rw-close (%font-rwops font)))
      (when (%font-memory font)
        (cffi:foreign-free (%font-memory font)))
      (setf (%font-rwops font) nil (%font-memory font) nil))))
(defun close (font) (pixelisp.internal:dispose font))
(defun size (font text) (%ptr font) (sdl2-ttf:size-utf8 (pixelisp.internal:handle font) text))
(defun render (font text antialias color &optional background)
  (%ptr font)
  (if (zerop (length text))
      (px.surface:make-surface (list 1 (get-height font)) :alpha t)
      (multiple-value-bind (r g b a) (pixelisp.internal:rgba color)
        (let ((native
                (if background
                    (multiple-value-bind (br bg bb ba) (pixelisp.internal:rgba background)
                      (sdl2-ttf:render-utf8-shaded (pixelisp.internal:handle font) text r g b a br bg bb ba))
                    (funcall (if antialias #'sdl2-ttf:render-utf8-blended #'sdl2-ttf:render-utf8-solid)
                             (pixelisp.internal:handle font) text r g b a))))
          (trivial-garbage:cancel-finalization native)
          (pixelisp.internal:wrap-surface native :owned t :alpha t)))))
(defun metrics (font text)
  (loop for character across text collect
    (cffi:with-foreign-objects ((minx :int) (maxx :int) (miny :int) (maxy :int) (advance :int))
      (when (zerop (%glyph-metrics (%ptr font) (char-code character) minx maxx miny maxy advance))
        (mapcar (lambda (p) (cffi:mem-ref p :int)) (list minx maxx miny maxy advance))))))
(defun get-height (font) (%height (%ptr font)))
(defun get-linesize (font) (%lineskip (%ptr font)))
(defun get-ascent (font) (%ascent (%ptr font)))
(defun get-descent (font) (%descent (%ptr font)))
(defmacro %style-property (name mask)
  (let ((get (intern (format nil "GET-~A" name))) (set (intern (format nil "SET-~A" name))))
    `(progn (defun ,get (font) (logtest ,mask (%style (%ptr font))))
            (defun ,set (font enabled)
              (%set-style (%ptr font) (if enabled (logior ,mask (%style (%ptr font)))
                                         (logandc2 (%style (%ptr font)) ,mask))) enabled))))
(%style-property bold 1) (%style-property italic 2)
(%style-property underline 4) (%style-property strikethrough 8)

(in-package #:pixelisp.mixer)
(cffi:defcstruct %chunk (allocated :int) (abuf :pointer) (alen :uint32) (volume :uint8))
(cffi:defcfun ("Mix_OpenAudioDevice" %open-audio-device) :int
  (frequency :int) (format :uint16) (channels :int) (chunksize :int)
  (device :string) (allowed-changes :int))
(cffi:defcfun ("Mix_CloseAudio" %close-audio) :void)
(cffi:defcfun ("Mix_QuerySpec" %query) :int (frequency :pointer) (format :pointer) (channels :pointer))
(cffi:defcfun ("Mix_LoadWAV_RW" %load-wav) :pointer (source :pointer) (free :int))
(cffi:defcfun ("SDL_RWFromConstMem" %rw-from-const-mem) :pointer
  (memory :pointer) (size :int))
(cffi:defcfun ("SDL_RWFromFile" %rw-from-file) :pointer (file :string) (mode :string))
(cffi:defcfun ("Mix_QuickLoad_RAW" %raw-chunk) :pointer (memory :pointer) (length :uint32))
(cffi:defcfun ("Mix_FreeChunk" %free-chunk) :void (chunk :pointer))
(cffi:defcfun ("Mix_PlayChannelTimed" %play) :int (channel :int) (chunk :pointer) (loops :int) (ticks :int))
(cffi:defcfun ("Mix_FadeInChannelTimed" %fade-in) :int (channel :int) (chunk :pointer) (loops :int) (ms :int) (ticks :int))
(cffi:defcfun ("Mix_HaltChannel" %halt) :int (channel :int))
(cffi:defcfun ("Mix_Pause" %pause) :void (channel :int))
(cffi:defcfun ("Mix_Resume" %resume) :void (channel :int))
(cffi:defcfun ("Mix_Playing" %playing) :int (channel :int))
(cffi:defcfun ("Mix_Paused" %paused) :int (channel :int))
(cffi:defcfun ("Mix_Volume" %volume) :int (channel :int) (volume :int))
(cffi:defcfun ("Mix_VolumeChunk" %chunk-volume) :int (chunk :pointer) (volume :int))
(cffi:defcfun ("Mix_SetPanning" %panning) :int (channel :int) (left :uint8) (right :uint8))
(cffi:defcfun ("Mix_FadeOutChannel" %fadeout) :int (channel :int) (ms :int))
(cffi:defcfun ("Mix_AllocateChannels" %allocate) :int (number :int))
(cffi:defcfun ("Mix_ReserveChannels" %reserve) :int (number :int))
(defconstant +default-frequency+ 44100)
(defconstant +default-size+ -16)
(defconstant +default-channels+ 2)
(defconstant +default-buffer+ 512)
(defconstant +default-allowed-changes+ 5) ; frequency | channels
(defvar *settings* (list +default-frequency+ +default-size+ +default-channels+
                         +default-buffer+ nil +default-allowed-changes+))
(defun %audio-format (size)
  ;; SDL's float format includes sign and byte-order bits. Positive SIZE 32
  ;; chooses native-endian float samples; negative 32 remains integer PCM.
  (case size (8 #x0008) (-8 #x8008) (16 #x0010) (-16 #x8010)
    (-32 #x8020)
    (32 (if (member :little-endian *features*) #x8120 #x9120))
    (otherwise (error 'pixelisp:unsupported-feature :operation 'init
                       :message "Mixer sample size must be 8, -8, 16, -16, -32 or 32"))))
(defun %float-format-p (format)
  (member format '(#x8120 #x9120)))
(defvar *channel-sounds* (make-hash-table))
(defvar *queued-sounds* (make-hash-table))
;; Configured per-channel event types and explicit stops awaiting the next pump.
(defvar *channel-endevents* (make-hash-table))
;; Each record captures its event type at completion time, preserving rapid stops.
(defvar *pending-channel-events* nil)
(defvar *queue-ready* nil)
(defclass sound (pixelisp.internal:resource)
  ((storage :initarg :storage :initform nil :accessor %storage)
   (format :initarg :format :reader sample-format)
   (channels :initarg :channels :reader sound-channels)
   (frequency :initarg :frequency :reader %frequency)))
(defun %require-init (operation)
  (unless (get-init)
    (error 'pixelisp:initialization-error :operation operation
           :message "Initialize the mixer with PX.MIXER:INIT before using this operation.")))
(defclass channel () ((id :initarg :id :reader %raw-id)))
(defun %id (channel)
  (%require-init 'channel)
  (let ((id (%raw-id channel)))
    (unless (< id (get-num-channels))
      (error 'pixelisp:error :operation 'channel :message "The mixer channel is no longer available"))
    id))
(defun %allowed-changes (value &optional (fallback +default-allowed-changes+))
  "Translate SDL audio change keywords or a raw SDL bitmask to SDL's flags."
  (cond
    ((and (integerp value) (<= 0 value 15)) value)
    ((and (integerp value) (= value -1)) fallback)
    ((and (listp value) (integerp (ignore-errors (list-length value)))
          (every (lambda (flag) (member flag '(:frequency :format :channels :samples))) value))
     (reduce #'logior value :key (lambda (flag)
                                  (ecase flag (:frequency 1) (:format 2)
                                    (:channels 4) (:samples 8)))
             :initial-value 0))
    (t (error 'pixelisp:error :operation 'init
              :message "ALLOWED-CHANGES must be an SDL flag integer (0..15), -1, or a list of :FREQUENCY, :FORMAT, :CHANNELS and :SAMPLES."))))
(defun %validate-settings (frequency size channels buffer device allowed-changes operation
                           &optional default-frequency default-size default-channels default-buffer
                             (default-allowed +default-allowed-changes+))
  ;; Pygame treats zero as “use the startup default” for numeric settings.
  (when (eql frequency 0) (setf frequency (or default-frequency +default-frequency+)))
  (when (eql size 0) (setf size (or default-size +default-size+)))
  (when (eql channels 0) (setf channels (or default-channels +default-channels+)))
  (when (eql buffer 0) (setf buffer (or default-buffer +default-buffer+)))
  (check-type frequency (integer 1 #x7fffffff))
  (unless (member size '(8 -8 16 -16 -32 32))
    (error 'pixelisp:unsupported-feature :operation operation
           :message "Mixer sample size must be 8, -8, 16, -16, -32 or 32"))
  (check-type channels (integer 1 8))
  ;; pygame rounds chunk size up to a power of two, with a 256-frame minimum.
  ;; Cap at 2^30 so the rounded value still fits SDL's signed int parameter.
  (check-type buffer (integer 1 #x40000000))
  (setf buffer (max 256 (loop for rounded = 1 then (* rounded 2)
                              when (>= rounded buffer) return rounded)))
  (when device
    (check-type device string)
    (when (find #\Null device)
      (error 'pixelisp:error :operation operation
             :message "Audio device names cannot contain a NUL character.")))
  (values frequency size channels buffer device (%allowed-changes allowed-changes default-allowed)))
(defun pre-init (&key (frequency +default-frequency+) (size +default-size+)
                      (channels +default-channels+) (buffer +default-buffer+)
                      (device-name nil) (allowed-changes +default-allowed-changes+))
  "Set startup mixer settings. ALLOWED-CHANGES accepts SDL flag keywords or a bitmask; 0 is strict."
  (multiple-value-bind (frequency size channels buffer device allowed)
      (%validate-settings frequency size channels buffer device-name allowed-changes 'pre-init
                          +default-frequency+ +default-size+ +default-channels+ +default-buffer+
                          +default-allowed-changes+)
    (setf *settings* (list frequency size channels buffer device allowed)))
  nil)
(defun init (&key (frequency (first *settings*)) (size (second *settings*))
                  (channels (third *settings*)) (buffer (fourth *settings*))
                  (device-name (fifth *settings*)) (allowed-changes (sixth *settings*)))
  "Initialize audio. DEVICE-NAME selects an SDL output; ALLOWED-CHANGES accepts a keyword list or SDL bitmask (0 means exact settings)."
  (multiple-value-bind (frequency size channels buffer device allowed)
      (%validate-settings frequency size channels buffer device-name allowed-changes 'init
                          (first *settings*) (second *settings*) (third *settings*) (fourth *settings*)
                          (sixth *settings*))
    (let ((opening (not (get-init))))
      (when opening
        (let ((format (%audio-format size)))
          (when (minusp (%open-audio-device frequency format channels buffer
                                           (or device (cffi:null-pointer)) allowed))
            (error 'pixelisp:initialization-error :operation 'init
                   :message (pixelisp.image::%sdl-error))))
        ;; SDL_mixer allocates fresh channels after shutdown, initially with no events.
        (clrhash *channel-endevents*)
        (setf *pending-channel-events* nil *queue-ready* nil))
      t)))
(defun get-init ()
  (cffi:with-foreign-objects ((frequency :int) (format :uint16) (channels :int))
    (when (plusp (%query frequency format channels))
      (let ((f (cffi:mem-ref format :uint16)))
        (values (cffi:mem-ref frequency :int)
                (if (%float-format-p f) 32
                    (* (if (logtest #x8000 f) -1 1) (logand f #xff)))
                (cffi:mem-ref channels :int))))))
(defun quit ()
  ;; Native capture must detach before SDL_mixer closes its audio device.
  ;; Mix_* playback functions can touch a closed device on some SDL_mixer
  ;; builds, so repeated shutdown must not call them after the first close.
  (when (get-init)
    (let* ((package (find-package :pixelisp.sdl2.mixer))
           (stop-capture (and package (find-symbol "STOP-CAPTURE" package))))
      (when (and stop-capture (fboundp stop-capture)) (funcall stop-capture)))
    (stop)
    (dolist (resource pixelisp.internal:*resources*)
      (when (typep resource 'sound) (pixelisp.internal:dispose resource)))
    (pixelisp.mixer.music:unload)
    (setf pixelisp.mixer.music::*pending-endevents* nil)
    (%close-audio))
  (clrhash *channel-sounds*) (clrhash *queued-sounds*)
  (clrhash *channel-endevents*) (setf *pending-channel-events* nil *queue-ready* nil) nil)
(defun %need-init () (unless (get-init) (init)))
(defun get-sdl-mixer-version () (sdl2-mixer:linked-version))
(defun sound-element-type (sound)
  (if (= (sample-format sound) 32) 'single-float
      (list (if (minusp (sample-format sound)) 'signed-byte 'unsigned-byte) (abs (sample-format sound)))))
(defun %sample-cffi (sound)
  (ecase (sample-format sound) (8 :uint8) (-8 :int8) (16 :uint16) (-16 :int16) (-32 :int32) (32 :float)))
(defun %check-sample-value (format value)
  ;; Lisp stores native SDL float samples as SINGLE-FLOAT. Their normalized
  ;; playback range is conventionally [-1, 1], but pygame preserves values
  ;; outside it, so do not clamp or reject them here.
  (when (= format 32) (check-type value single-float))
  value)
(defun %sound-pointer (sound)
  (pixelisp.internal:ensure-live sound) (pixelisp.internal:handle sound))
(defun %sample-data (sound)
  (cffi:foreign-slot-value (%sound-pointer sound) '(:struct %chunk) 'abuf))
(defun %sample-bytes (sound)
  (cffi:foreign-slot-value (%sound-pointer sound) '(:struct %chunk) 'alen))
(defun sound-frame-count (sound)
  (/ (%sample-bytes sound) (* (sound-channels sound) (/ (abs (sample-format sound)) 8))))
(defun %encoded-sound-octets (source)
  "Return encoded sound octets; binary streams are read to EOF and left open."
  (cond
    ((typep source '(vector (unsigned-byte 8))) source)
    ((streamp source)
     (unless (and (input-stream-p source)
                  (subtypep (stream-element-type source) '(unsigned-byte 8)))
       (error 'simple-type-error :datum source :expected-type 'stream
              :format-control "Expected a binary input stream containing sound octets; received ~S"
              :format-arguments (list source)))
     (let ((bytes (make-array 0 :element-type '(unsigned-byte 8)
                              :adjustable t :fill-pointer 0)))
       (loop for byte = (read-byte source nil :eof)
             until (eq byte :eof)
             do (when (>= (length bytes) #x7fffffff)
                  (error 'pixelisp:error :operation 'make-sound
                         :message "Encoded sound exceeds SDL's supported size"))
                (vector-push-extend byte bytes))
       bytes))
    (t (error 'type-error :datum source
              :expected-type '(or pathname string stream (vector (unsigned-byte 8)))))))

(defun load-sound-bytes (bytes)
  "Decode encoded WAV octets into an owned Sound; raw PCM belongs in :BUFFER."
  (unless (typep bytes '(vector (unsigned-byte 8)))
    (error 'type-error :datum bytes :expected-type '(vector (unsigned-byte 8))))
  (make-sound nil :file bytes))

(defun %load-sound-memory (bytes)
  "Decode encoded octets synchronously while keeping the SDL_RWops backing bytes alive."
  (let ((length (length bytes)))
    (when (zerop length)
      (error 'pixelisp:error :operation 'make-sound :message "Encoded sound data is empty"))
    (when (> length #x7fffffff)
      (error 'pixelisp:error :operation 'make-sound :message "Encoded sound exceeds SDL's supported size"))
    (let ((memory (cffi:foreign-alloc :uint8 :count length)))
      (unwind-protect
           (progn
             (dotimes (index length)
               (setf (cffi:mem-aref memory :uint8 index) (aref bytes index)))
             (let ((rw (%rw-from-const-mem memory length)))
               (when (cffi:null-pointer-p rw)
                 (error 'pixelisp:error :operation 'make-sound
                        :message (or (pixelisp.image::%sdl-error) "Unable to create sound byte stream")))
               ;; SDL_mixer synchronously decodes and closes the RWops via freesrc.
               (%load-wav rw 1)))
        (cffi:foreign-free memory)))))

(defun make-sound (&optional filename &key array buffer file)
  "Load a sound file, decode encoded :FILE data, copy ARRAY samples, or copy raw :BUFFER PCM.
For a float32 mixer, ARRAY samples must be SINGLE-FLOAT values. The conventional
normalized range is [-1, 1], but values outside it are preserved. Raw :BUFFER
octets are copied unchanged."
  ;; Complete source validation before opening the mixer or allocating native memory.
  (let ((sources (count-if #'identity (list filename array buffer file))))
    (unless (= sources 1)
      (error 'pixelisp:error :operation 'make-sound
             :message "Choose exactly one source: filename, :FILE, :ARRAY, or :BUFFER")))
  (when (and filename (not (or (pathnamep filename) (stringp filename))))
    (error 'type-error :datum filename :expected-type '(or pathname string)))
  (when array (unless (arrayp array) (error 'type-error :datum array :expected-type 'array)))
  (when buffer
    (unless (typep buffer '(vector (unsigned-byte 8)))
      (error 'type-error :datum buffer :expected-type '(vector (unsigned-byte 8)))))
  (when (and file (or (streamp file) (typep file '(vector (unsigned-byte 8)))))
    (setf file (%encoded-sound-octets file)))
  (when (and file (not (or (pathnamep file) (stringp file)
                           (typep file '(vector (unsigned-byte 8)))))
    (error 'type-error :datum file
           :expected-type '(or pathname string stream (vector (unsigned-byte 8))))))
  (when (and file (typep file '(vector (unsigned-byte 8)))
             (or (zerop (length file)) (> (length file) #x7fffffff)))
    (error 'pixelisp:error :operation 'make-sound
           :message "Encoded sound size must be between 1 and SDL's supported maximum"))
  (when (typep file '(vector (unsigned-byte 8))) (setf file (copy-seq file)))
  (%need-init)
  (multiple-value-bind (frequency format channels) (get-init)
    (let* ((ctype (ecase format (8 :uint8) (-8 :int8) (16 :uint16) (-16 :int16) (-32 :int32) (32 :float)))
           (sample-bytes (cffi:foreign-type-size ctype))
           (bytes (cond (array (* (array-total-size array) sample-bytes))
                        (buffer (length buffer))))
           (storage nil) (native nil) (complete nil))
      (when array
        (unless (if (= channels 1) (= (array-rank array) 1)
                    (and (= (array-rank array) 2) (= (array-dimension array 1) channels)))
          (error 'pixelisp:error :operation 'make-sound :message "Array shape must match mixer channels"))
        (when (and (= format 32)
                   (not (subtypep (array-element-type array) 'single-float)))
          (error 'type-error :datum array :expected-type '(array single-float)))
        (when (= format 32)
          (dotimes (i (array-total-size array))
            (%check-sample-value format (row-major-aref array i))))
        (when (zerop (array-total-size array))
          (error 'pixelisp:error :operation 'make-sound :message "A sound must contain at least one sample")))
      (when (and bytes (zerop bytes))
        (error 'pixelisp:error :operation 'make-sound :message "A sound buffer cannot be empty"))
      (when (and bytes (not (zerop (mod bytes (* channels sample-bytes)))))
        (error 'pixelisp:error :operation 'make-sound :message "Raw samples must contain complete audio frames"))
      (unwind-protect
           (progn
             (when bytes
               (setf storage (cffi:foreign-alloc :uint8 :count bytes))
               (if array
                   (dotimes (i (array-total-size array))
                     (setf (cffi:mem-aref storage ctype i) (row-major-aref array i)))
                   (dotimes (i bytes)
                     (setf (cffi:mem-aref storage :uint8 i) (elt buffer i))))
               (setf native (%raw-chunk storage bytes)))
             (when (or filename file)
               (let ((source (or file filename)))
                 (setf native
                       (if (typep source '(vector (unsigned-byte 8)))
                           (%load-sound-memory source)
                           (let ((rw (%rw-from-file (namestring (pathname source)) "rb")))
                             (when (cffi:null-pointer-p rw)
                               (error 'pixelisp:error :operation 'make-sound
                                      :message (or (pixelisp.image::%sdl-error) "Unable to open sound file")))
                             ;; SDL_mixer closes this synchronously after decoding.
                             (%load-wav rw 1))))))
             (when (cffi:null-pointer-p native)
               (error 'pixelisp:error :operation 'make-sound :message (pixelisp.image::%sdl-error)))
             (let ((sound (pixelisp.internal:register-resource
                           (make-instance 'sound :handle native :storage storage :format format
                                          :channels channels :frequency frequency))))
               (setf complete t)
               sound))
        (unless complete
          (when (and native (not (cffi:null-pointer-p native))) (%free-chunk native))
          (when storage (cffi:foreign-free storage)))))))
(defun sound (&optional filename &key array buffer file)
  (make-sound filename :array array :buffer buffer :file file))
(defun make-channel (id) (check-type id (integer 0 *))
  (unless (< id (get-num-channels)) (error 'pixelisp:error :operation 'make-channel :message "Invalid mixer channel"))
  (make-instance 'channel :id id))
(defun channel (id) (make-channel id))
(defun get-num-channels (&optional sound)
  (if sound (progn (pixelisp.internal:ensure-live sound)
                   (loop for value being the hash-values of *channel-sounds* count (eq sound value)))
      (if (get-init) (%allocate -1) 0)))
(defun %check-channel-target (object)
  (etypecase object
    (null nil)
    (channel object)
    (sound (pixelisp.internal:ensure-live object))))
(defun set-endevent (channel &optional (event-type 0))
  "Post EVENT-TYPE when CHANNEL finishes or is stopped; 0 disables notification.
Events are created by UPDATE on the Lisp thread, never by SDL's audio thread."
  (unless (or (keywordp event-type) (and (integerp event-type) (not (minusp event-type))))
    (error 'type-error :datum event-type :expected-type '(or keyword (integer 0 *))))
  (%harvest-channel-finishes)
  (let ((id (%id channel)))
    (if (eql event-type 0) (remhash id *channel-endevents*)
        (setf (gethash id *channel-endevents*) event-type)))
  event-type)
(defun get-endevent (channel)
  "Return CHANNEL's configured end event type, or 0 when notification is disabled."
  (if (and (get-init) (< (%raw-id channel) (get-num-channels)))
      (gethash (%raw-id channel) *channel-endevents* 0) 0))
(defun %record-channel-end (id)
  "Capture the configured event now; native audio callbacks never call Lisp."
  (let ((type (gethash id *channel-endevents* 0)))
    (unless (eql type 0)
      (setf *pending-channel-events* (nconc *pending-channel-events* (list (list type id)))))))
(defun %harvest-channel-finishes ()
  "Record tracked natural completions and defer queued playback until UPDATE."
  (dolist (id (loop for id being the hash-keys of *channel-sounds* collect id))
    (when (zerop (%playing id))
      (%record-channel-end id)
      (remhash id *channel-sounds*)
      (when (gethash id *queued-sounds*) (pushnew id *queue-ready*))))
  nil)
(defun set-num-channels (count)
  (check-type count (integer 0 *)) (%require-init 'set-num-channels)
  (%harvest-channel-finishes)
  (let ((old-count (get-num-channels)))
    (when (< count old-count)
      ;; Shrinking stops live channels too; preserve their end events before SDL
      ;; discards their channel slots, then forget all configuration above COUNT.
      (loop for id from count below old-count do
        (when (plusp (%playing id)) (%record-channel-end id))
        (remhash id *channel-sounds*) (remhash id *queued-sounds*)
        (remhash id *channel-endevents*) (setf *queue-ready* (delete id *queue-ready*))))
    (%allocate count)))
(defun set-reserved (count) (%require-init 'set-reserved) (%reserve count))
(defun find-channel (&optional force)
  (or (loop for i below (get-num-channels) when (zerop (%playing i)) return (make-channel i))
      (when (and force (plusp (get-num-channels))) (make-channel 0))))
(defun update ()
  "Advance queued sounds from the Lisp thread; call once per game-loop iteration."
  (unless (get-init) (return-from update nil))
  (%harvest-channel-finishes)
  (let ((ready (nreverse *queue-ready*)))
    (setf *queue-ready* nil)
    (dolist (id ready)
      (let ((next (gethash id *queued-sounds*)))
        (remhash id *queued-sounds*)
        (when next (play next :channel (make-channel id))))))
  (dolist (record *pending-channel-events*)
    (px.event:post (px.event:make-event (first record) :code (second record))))
  (setf *pending-channel-events* nil)
  (pixelisp.mixer.music:update) nil)
(defun play (sound &key channel (loops 0) (maxtime -1) (fade-ms 0))
  "Play SOUND on a chosen or free channel; -1 LOOPS repeats indefinitely."
  (%require-init 'play)
  ;; Validate Lisp arguments and the native Sound before recording a replaced
  ;; playback, so a rejected request cannot create a false completion event.
  (let ((chunk (%sound-pointer sound)))
    (check-type loops integer) (check-type maxtime integer) (check-type fade-ms integer)
    (let ((id (if channel (%id channel) -1)))
      (%harvest-channel-finishes)
      ;; Replacing a live channel ends its current chunk just like an explicit
      ;; stop. Capture the old event before Mix_PlayChannel replaces that chunk.
      (when (and (>= id 0) (plusp (%playing id)))
        (%record-channel-end id)
        (remhash id *queued-sounds*))
      (when (>= id 0) (setf *queue-ready* (delete id *queue-ready*)))
      (setf id (if (plusp fade-ms) (%fade-in id chunk loops fade-ms maxtime)
                   (%play id chunk loops maxtime)))
      (when (>= id 0)
        (remhash id *queued-sounds*)
        (setf *queue-ready* (delete id *queue-ready*)
              (gethash id *channel-sounds*) sound)
        (make-channel id)))))
(defun %each-channel (object function)
  (%check-channel-target object)
  (etypecase object
    (null (funcall function -1))
    (channel (funcall function (%id object)))
    (sound (dolist (id (loop for id being the hash-keys of *channel-sounds*
                             using (hash-value sound) when (eq sound object) collect id))
             (funcall function id)))))
(defun stop (&optional object)
  (%check-channel-target object)
  (if (get-init)
      (progn
        (%harvest-channel-finishes)
        (%each-channel object (lambda (id)
          (if (= id -1)
              (dotimes (channel (get-num-channels))
                (when (plusp (%playing channel)) (%record-channel-end channel)))
              (when (plusp (%playing id)) (%record-channel-end id)))
          (%halt id)
          (if (= id -1) (progn (clrhash *channel-sounds*) (clrhash *queued-sounds*)
                                (setf *queue-ready* nil))
              (progn (remhash id *channel-sounds*) (remhash id *queued-sounds*)
                     (setf *queue-ready* (delete id *queue-ready*)))))))
      (progn (clrhash *channel-sounds*) (clrhash *queued-sounds*) (setf *queue-ready* nil)))
  nil)
(defun pause (&optional object) (%check-channel-target object) (when (get-init) (%each-channel object #'%pause)))
(defun unpause (&optional object) (%check-channel-target object) (when (get-init) (%each-channel object #'%resume)))
(defun fadeout (milliseconds &optional object)
  (%check-channel-target object)
  (when (get-init) (%each-channel object (lambda (id) (%fadeout id milliseconds)))))
(defun get-busy (&optional object)
  (%check-channel-target object)
  (unless (get-init) (return-from get-busy nil))
  (update)
  (etypecase object (null (plusp (%playing -1))) (channel (plusp (%playing (%id object))))
    (sound (plusp (get-num-channels object)))))
(defun set-volume (object volume &optional right)
  "Set a Sound's volume or a Channel's volume; RIGHT enables stereo panning."
  (unless (or (typep object 'sound) (typep object 'channel))
    (error 'type-error :datum object :expected-type '(or sound channel)))
  (when (typep object 'sound) (pixelisp.internal:ensure-live object))
  (%require-init 'set-volume)
  (let* ((left (max 0 (min 1 volume)))
         (level (round (* 128 left))))
    (etypecase object
      (sound (%chunk-volume (%sound-pointer object) level))
      (channel
       (if right
           (%panning (%id object) (round (* 255 left)) (round (* 255 (max 0 (min 1 right)))))
           (%volume (%id object) level)))))
  volume)
(defun get-volume (object)
  (unless (or (typep object 'sound) (typep object 'channel))
    (error 'type-error :datum object :expected-type '(or sound channel)))
  (if (get-init)
      (/ (etypecase object (sound (%chunk-volume (%sound-pointer object) -1))
           (channel (%volume (%id object) -1))) 128.0)
      (progn (when (typep object 'sound) (pixelisp.internal:ensure-live object)) 0.0)))
(defun get-length (sound) (/ (sound-frame-count sound) (float (%frequency sound))))
(defun get-raw (sound)
  (let ((bytes (make-array (%sample-bytes sound) :element-type '(unsigned-byte 8))))
    (dotimes (i (length bytes) bytes) (setf (aref bytes i) (cffi:mem-aref (%sample-data sound) :uint8 i)))))
(defun get-sound (channel) (when (get-init) (update) (gethash (%id channel) *channel-sounds*)))
(defun queue (channel sound) (if (get-busy channel) (setf (gethash (%id channel) *queued-sounds*) sound)
                                  (play sound :channel channel)) sound)
(defun get-queue (channel) (gethash (%id channel) *queued-sounds*))
(defun sound-sample-ref (sound frame &optional (channel 0))
  (unless (and (<= 0 frame) (< frame (sound-frame-count sound)) (<= 0 channel) (< channel (sound-channels sound)))
    (error 'pixelisp:error :operation 'sound-sample-ref :message "Audio sample index out of bounds"))
  (cffi:mem-aref (%sample-data sound) (%sample-cffi sound) (+ (* frame (sound-channels sound)) channel)))
(defun sound-sample-set (sound value frame &optional (channel 0))
  (sound-sample-ref sound frame channel)
  (%check-sample-value (sample-format sound) value)
  (setf (cffi:mem-aref (%sample-data sound) (%sample-cffi sound) (+ (* frame (sound-channels sound)) channel)) value))
(defmethod pixelisp.internal:dispose ((sound sound))
  (unless (pixelisp.internal:resource-disposed-p sound)
    ;; Queued sounds also hold native memory and must not be played after close.
    (maphash (lambda (channel queued)
               (when (eq sound queued) (remhash channel *queued-sounds*)))
             *queued-sounds*)
    (stop sound)
    (%free-chunk (%sound-pointer sound))
    (when (%storage sound) (cffi:foreign-free (%storage sound)) (setf (%storage sound) nil))))
(defun close (sound) (pixelisp.internal:dispose sound))

(in-package #:pixelisp.mixer.music)
(cffi:defcfun ("Mix_LoadMUS" %load) :pointer (filename :string))
(cffi:defcfun ("Mix_LoadMUS_RW" %load-rw) :pointer (source :pointer) (freesrc :int))
(cffi:defcfun ("Mix_LoadMUSType_RW" %load-rw-type) :pointer
  (source :pointer) (type :int) (freesrc :int))
(cffi:defcfun ("Mix_FreeMusic" %free) :void (music :pointer))
(cffi:defcfun ("Mix_PlayMusic" %play) :int (music :pointer) (loops :int))
(cffi:defcfun ("Mix_FadeInMusicPos" %fade-in) :int (music :pointer) (loops :int) (ms :int) (position :double))
(cffi:defcfun ("Mix_HaltMusic" %halt) :int)
(cffi:defcfun ("Mix_PauseMusic" %pause) :void)
(cffi:defcfun ("Mix_ResumeMusic" %resume) :void)
(cffi:defcfun ("Mix_RewindMusic" %rewind) :void)
(cffi:defcfun ("Mix_FadeOutMusic" %fadeout) :int (ms :int))
(cffi:defcfun ("Mix_PlayingMusic" %playing) :int)
(cffi:defcfun ("Mix_PausedMusic" %paused) :int)
(cffi:defcfun ("Mix_VolumeMusic" %volume) :int (volume :int))
(cffi:defcfun ("Mix_SetMusicPosition" %position) :int (position :double))
(cffi:defcfun ("SDL_RWFromConstMem" %rw-from-const-mem) :pointer (memory :pointer) (size :int))
(cffi:defcfun ("SDL_RWclose" %rw-close) :int (source :pointer))
(defstruct (%stream (:constructor %make-stream (native rw memory loops))) native rw memory loops)
(defvar *music* nil) (defvar *queued* nil) (defvar *started* nil) (defvar *paused-at* nil) (defvar *pause-time* 0)
(defvar *natural-end-pending* nil)
;; Music endevent is module-wide and pygame keeps it across mixer shutdown.
(defvar *endevent* 0) (defvar *pending-endevents* nil)
(defun %record-music-end ()
  (unless (eql *endevent* 0)
    (setf *pending-endevents* (nconc *pending-endevents* (list *endevent*))))
  nil)
(defun set-endevent (&optional (event-type 0))
  "Set the event posted when streamed music ends; omitting the type disables it."
  (unless (or (keywordp event-type) (and (integerp event-type) (not (minusp event-type))))
    (error 'type-error :datum event-type :expected-type '(or keyword (integer 0 *))))
  (%harvest-music-finish)
  (setf *endevent* event-type) event-type)
(defun get-endevent () "Return the configured streamed-music end event, or 0." *endevent*)
(defun %harvest-music-finish ()
  "Capture a natural stream ending before another operation changes its state."
  (when (and *started* (pixelisp.mixer:get-init) (zerop (%playing)))
    (%record-music-end)
    (setf *started* nil *paused-at* nil *pause-time* 0 *natural-end-pending* t))
  nil)
(defun %namehint-type (hint)
  (when hint
    (unless (or (stringp hint) (symbolp hint))
      (error 'type-error :datum hint :expected-type '(or string symbol)))
    (let* ((text (string-downcase (string hint)))
           (extension (pathname-type text))
           (format (or extension text)))
      (unless (plusp (length format)) (return-from %namehint-type nil))
      (or (cdr (assoc format '(("wav" . 2) ("mod" . 3) ("mid" . 4) ("midi" . 4)
                               ("ogg" . 5) ("mp3" . 6) ("flac" . 8) ("opus" . 10))
                         :test #'string=))
          (error 'pixelisp:error :operation 'load
                 :message (format nil "Unsupported music name hint: ~A" text))))))
(defun %read-source (stream)
  (unless (and (input-stream-p stream)
               (subtypep (stream-element-type stream) '(unsigned-byte 8)))
    (error 'simple-type-error :datum stream :expected-type 'stream
           :format-control "Expected a binary input stream containing octets"))
  (let ((bytes (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0)))
    (loop for byte = (read-byte stream nil nil) while byte do (vector-push-extend byte bytes))
    bytes))
(defun %encoded-stream (bytes hint &optional (loops 0))
  ;; SDL_RWFromConstMem borrows its buffer; keep both buffer and RWops until music is freed.
  (unless (and (vectorp bytes) (subtypep (array-element-type bytes) '(unsigned-byte 8)))
    (error 'type-error :datum bytes :expected-type '(vector (unsigned-byte 8))))
  (let ((size (length bytes)) (type (%namehint-type hint)))
    (when (zerop size) (error 'pixelisp:error :operation 'load :message "Music data is empty"))
    (when (> size #x7fffffff) (error 'pixelisp:error :operation 'load :message "Music data exceeds SDL's supported size"))
    (let ((memory (cffi:foreign-alloc :uint8 :count size)) (rw nil) (native nil) (complete nil))
      (unwind-protect
           (let ((stream
                   (progn
                     (dotimes (i size) (setf (cffi:mem-aref memory :uint8 i) (aref bytes i)))
                     (setf rw (%rw-from-const-mem memory size))
                     (when (cffi:null-pointer-p rw)
                       (setf rw nil)
                       (error 'pixelisp:error :operation 'load :message (or (pixelisp.image::%sdl-error) "Unable to create music byte stream")))
                     (setf native (if type (%load-rw-type rw type 0) (%load-rw rw 0)))
                     (when (cffi:null-pointer-p native)
                       (setf native nil)
                       (error 'pixelisp:error :operation 'load :message (or (pixelisp.image::%sdl-error) "Unsupported or malformed music data")))
                     (%make-stream native rw memory loops))))
             (setf complete t)
             stream)
        (unless complete
          (when native (%free native))
          (when rw (%rw-close rw))
          (cffi:foreign-free memory))))))
(defun %candidate (source namehint &optional (loops 0))
  (cond
    ((or (pathnamep source) (stringp source))
     (let ((native (%load (if (pathnamep source) (namestring source) source))))
       (when (cffi:null-pointer-p native)
         (error 'pixelisp:error :operation 'load :message (pixelisp.image::%sdl-error)))
       (%make-stream native nil nil loops)))
    ((and (vectorp source) (subtypep (array-element-type source) '(unsigned-byte 8)))
     (%encoded-stream source namehint loops))
    (t (error 'type-error :datum source :expected-type '(or pathname string (vector (unsigned-byte 8)))))))
(defun %prepare-source (source namehint)
  "Validate a source and materialize stream contents before initializing or changing playback."
  (%namehint-type namehint)
  (let ((prepared (typecase source
                    (pathname source)
                    (string source)
                    (stream (%read-source source))
                    (vector (unless (subtypep (array-element-type source) '(unsigned-byte 8))
                              (error 'type-error :datum source :expected-type '(vector (unsigned-byte 8))))
                            source)
                    (t (error 'type-error :datum source
                              :expected-type '(or pathname string stream (vector (unsigned-byte 8))))))))
    (when (and (vectorp prepared) (not (stringp prepared)))
      (when (zerop (length prepared)) (error 'pixelisp:error :operation 'load :message "Music data is empty"))
      (when (> (length prepared) #x7fffffff)
        (error 'pixelisp:error :operation 'load :message "Music data exceeds SDL's supported size")))
    prepared))
(defun %release-stream (stream)
  (when stream
    (when (%stream-native stream) (%free (%stream-native stream)))
    (when (%stream-rw stream) (%rw-close (%stream-rw stream)))
    (when (%stream-memory stream) (cffi:foreign-free (%stream-memory stream)))
    (setf (%stream-native stream) nil (%stream-rw stream) nil (%stream-memory stream) nil))
  nil)
(defun load (source &key namehint)
  ;; Validate and fully prepare before touching the active stream.
  (let* ((prepared (%prepare-source source namehint))
         (candidate (progn (pixelisp.mixer::%need-init) (%candidate prepared namehint))))
    (when *music*
      (%harvest-music-finish)
      (when (pixelisp.mixer:get-init) (when (plusp (%playing)) (%record-music-end)) (%halt)))
    (%release-stream *music*) (%release-stream *queued*)
    (setf *music* candidate *queued* nil *started* nil *paused-at* nil *pause-time* 0
          *natural-end-pending* nil)
    source))
(defun load-bytes (bytes &key namehint)
  "Load music from a specialized unsigned-byte 8 vector."
  (unless (and (vectorp bytes) (subtypep (array-element-type bytes) '(unsigned-byte 8)))
    (error 'type-error :datum bytes :expected-type '(vector (unsigned-byte 8))))
  (load bytes :namehint namehint))
(defun unload ()
  (%harvest-music-finish)
  (when (and *music* (pixelisp.mixer:get-init))
    (when (plusp (%playing)) (%record-music-end))
    (%halt))
  (%release-stream *music*) (%release-stream *queued*)
  (setf *music* nil *queued* nil *started* nil *paused-at* nil *pause-time* 0
        *natural-end-pending* nil) nil)
(defun play (&key (loops 0) (start 0) (fade-ms 0))
  (unless *music* (error 'pixelisp:error :operation 'play :message "Load music before playback"))
  (%harvest-music-finish)
  (when (and (pixelisp.mixer:get-init) (plusp (%playing))) (%record-music-end))
  (let ((rc (if (or (plusp fade-ms) (plusp start))
                (%fade-in (%stream-native *music*) loops fade-ms (coerce start 'double-float))
                (%play (%stream-native *music*) loops))))
    (when (minusp rc) (error 'pixelisp:error :operation 'play :message (pixelisp.image::%sdl-error))))
  (setf *started* (get-internal-real-time) *paused-at* nil *pause-time* 0
        *natural-end-pending* nil) nil)
(defun stop ()
  (%harvest-music-finish)
  (when (pixelisp.mixer:get-init)
    (when (plusp (%playing)) (%record-music-end))
    (%halt))
  (%release-stream *queued*)
  (setf *started* nil *paused-at* nil *queued* nil *natural-end-pending* nil) nil)
(defun pause ()
  (when (pixelisp.mixer:get-init)
    (when (and *started* (null *paused-at*)) (setf *paused-at* (get-internal-real-time)))
    (%pause)))
(defun unpause ()
  (when (pixelisp.mixer:get-init)
    (when *paused-at* (incf *pause-time* (- (get-internal-real-time) *paused-at*)) (setf *paused-at* nil))
    (%resume)))
(defun rewind ()
  (when (pixelisp.mixer:get-init)
    (%rewind)
    (setf *started* (get-internal-real-time) *pause-time* 0 *natural-end-pending* nil)))
(defun fadeout (milliseconds) (when (pixelisp.mixer:get-init) (%fadeout milliseconds)))
(defun set-volume (volume)
  "Set streaming music volume in the range 0 to 1."
  (pixelisp.mixer::%require-init 'set-volume)
  (%volume (round (* 128 (max 0 (min 1 volume)))))
  volume)
(defun get-volume () (if (pixelisp.mixer:get-init) (/ (%volume -1) 128.0) 0.0))
(defun get-busy () (and (pixelisp.mixer:get-init) (plusp (%playing)) (zerop (%paused))))
(defun get-pos () (if (and (pixelisp.mixer:get-init) *started* (plusp (%playing))) (round (* 1000 (/ (- (or *paused-at* (get-internal-real-time)) *started* *pause-time*) internal-time-units-per-second))) -1))
(defun set-pos (seconds)
  (pixelisp.mixer::%require-init 'set-pos)
  (when (minusp (%position (coerce seconds 'double-float)))
    (error 'pixelisp:unsupported-feature :operation 'set-pos :message "Music decoder does not support seeking")) seconds)
(defun queue (source &key namehint (loops 0))
  ;; Build the replacement completely before releasing the previous queued music.
  (unless (and (integerp loops) (>= loops -1))
    (error 'type-error :datum loops :expected-type '(integer -1 *)))
  (let* ((prepared (%prepare-source source namehint))
         (candidate (progn (pixelisp.mixer::%need-init) (%candidate prepared namehint loops))))
    (%release-stream *queued*)
    (setf *queued* candidate))
  source)
(defun update ()
  ;; Deliver explicit stops and natural endings from the event-loop thread.
  (dolist (type *pending-endevents*)
    (px.event:post (px.event:make-event type :code 0)))
  (setf *pending-endevents* nil)
  (%harvest-music-finish)
  (dolist (type *pending-endevents*) (px.event:post (px.event:make-event type :code 0)))
  (setf *pending-endevents* nil)
  (when (and (pixelisp.mixer:get-init) *queued* *natural-end-pending*
             (zerop (%paused)))
    (let ((next *queued*))
      (setf *queued* nil)
      (%release-stream *music*)
      (setf *music* next)
      (setf *natural-end-pending* nil)
      (play :loops (%stream-loops next))))
  ;; A completed stream only authorizes a handoff during this event-loop pass.
  ;; Preserve the signal while paused so an existing queue can resume later.
  (when (and (pixelisp.mixer:get-init) *natural-end-pending*
             (zerop (%paused)) (null *queued*))
    (setf *natural-end-pending* nil))
  nil)

;;; Work requiring Lisp execution stays on the application's event-loop thread.
(pushnew #'pixelisp.mixer:update pixelisp.internal:*pump-hooks*)
(pushnew #'pixelisp.mixer:quit pixelisp.internal:*shutdown-hooks*)
(pushnew #'pixelisp.font:quit pixelisp.internal:*shutdown-hooks*)

(in-package #:pixelisp.ftfont)
(defun %freetype-call (name &rest arguments)
  (let* ((package (find-package :pixelisp.freetype))
         (function (and package (find-symbol (string name) package))))
    (unless (and function (fboundp function))
      (error 'pixelisp:dependency-error :operation name
             :message "Load the pixelisp/freetype ASDF system to use FTFont"))
    (apply function arguments)))
(defun make-font (&optional filename (point-size 16))
  "SDL_ttf-style constructor backed by the optional direct FreeType renderer."
  (%freetype-call :make-font filename point-size))
(defun font (&optional filename (point-size 16)) (make-font filename point-size))
(defun sys-font (name point-size &key bold italic)
  (%freetype-call :sys-font name point-size :bold bold :italic italic))
(setf (fdefinition 'sysfont) #'sys-font)
(defun render (font text antialias color &optional background)
  (let* ((package (find-package :pixelisp.freetype))
         (accessor (and package (find-symbol "ANTIALIASED" package))))
    (when accessor (funcall (fdefinition (list 'setf accessor)) antialias font)))
  (%freetype-call :render font text color background))
(defun size (font text)
  (let ((rect (%freetype-call :get-rect font text)))
    (values (px.rect:width rect) (px.rect:height rect))))
(defun metrics (font text)
  (mapcar (lambda (metric) (when metric (subseq metric 0 5)))
          (%freetype-call :get-metrics font text)))
(defun get-fonts () (px.font:get-fonts))
(defun match-font (name &key bold italic) (px.font:match-font name :bold bold :italic italic))
(defun get-default-font () (px.font:get-default-font))
