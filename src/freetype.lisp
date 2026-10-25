;;;; FreeType is a separate optional system, independent of SDL_ttf rendering.
;;;; Each Font owns a face. Loading a glyph reuses FreeType's glyph slot, so we
;;;; copy its coverage bitmap before loading the next glyph. Layout positions
;;;; use baseline coordinates and account for bearings, advances, and kerning.
(defpackage #:pixelisp.freetype
  (:use #:cl) (:nicknames #:px.freetype) (:shadow #:close)
  (:export #:init #:quit #:get-init #:font #:make-font #:sys-font #:sysfont
           #:style-normal #:style-underline #:style-oblique #:style-strong #:style-wide #:style-default
           #:close #:get-version #:get-fonts #:match-font #:get-default-font
           #:get-metrics #:get-kerning #:get-rect #:render #:render-to #:render-raw
           #:size #:kerning #:antialiased #:origin #:style #:underline #:oblique #:strong #:wide
           #:strength #:underline-adjustment #:get-sized-height #:get-sized-ascender
           #:get-sized-descender #:name #:render-raw-to #:rotation #:vertical))
(in-package #:pixelisp.freetype)
(defconstant style-normal 0)
(defconstant style-underline 4)
(defconstant style-oblique 2)
(defconstant style-strong 1)
(defconstant style-wide 8)
(defconstant style-default 255)
(defvar *initialized* t)
(defclass font (pixelisp.internal:resource)
  ((size :initarg :size :reader %size)
   (kerning :initarg :kerning :initform t :accessor kerning)
   (antialiased :initarg :antialiased :initform t :accessor antialiased)
   (origin :initarg :origin :initform nil :accessor origin)
   (rotation :initarg :rotation :initform 0 :reader %rotation)
   (vertical :initarg :vertical :initform nil :reader %vertical)
   (style :initarg :style :initform style-normal :reader %style)
   (strength :initarg :strength :initform (/ 1.0 36) :reader %strength)
   (underline-adjustment :initarg :underline-adjustment :initform 1.0 :reader %underline-adjustment)
   (path :initarg :path :reader %path)))
(defun init () (setf *initialized* t))
(defun quit ()
  (dolist (resource pixelisp.internal:*resources*)
    (when (typep resource 'font) (pixelisp.internal:dispose resource)))
  (setf *initialized* nil))
(defun get-init () *initialized*)
(defun get-version () (freetype2:freetype-version))
(defun get-default-font () (px.font:get-default-font))
(defun get-fonts () (px.font:get-fonts))
(defun match-font (name &key bold italic) (px.font:match-font name :bold bold :italic italic))
(defun %normalize-size (value)
  "Copy and validate a scalar pixel size or a horizontal/vertical pixel pair."
  (cond
    ((realp value)
     (unless (> value 0) (error "A scalar font size must be positive."))
     value)
    ((and (typep value 'sequence) (not (stringp value)) (= (length value) 2))
     (let ((width (elt value 0)) (height (elt value 1)))
       (unless (and (realp width) (realp height) (>= width 0) (>= height 0))
         (error "A font size pair must contain non-negative real pixel sizes."))
       (when (zerop width)
         (if (zerop height)
             (error "A zero size has no default FreeType pixel size.")
             (error "A zero horizontal size cannot be paired with a non-zero vertical size.")))
       ;; Pygame treats a zero vertical component as an automatic axis. Keep
       ;; the pair as supplied so the getter is explicit and caller-independent.
       (list width height)))
    (t (error "Font size must be a positive real pixel size or a two-value sequence."))))
(defun %size-axes (value)
  "Return native horizontal and vertical ppem values for a normalized size."
  (flet ((native-size (axis)
           (let ((pixels (max 1 (round axis))))
             ;; FT_Set_Pixel_Sizes takes unsigned C integers. Check before the
             ;; FFI call so a bignum cannot silently wrap to an unrelated size.
             (check-type pixels (unsigned-byte 32))
             pixels)))
    (if (numberp value)
        (values 0 (native-size value))
        (values (native-size (first value))
                (if (zerop (second value)) 0 (native-size (second value)))))))
(defun %size-vertical (value)
  "Return the vertical pixel dimension used by vertical metrics and strength."
  (if (numberp value) value (if (zerop (second value)) (first value) (second value))))
(defun %copy-size (value)
  (if (numberp value) value (copy-list value)))
(defun %bitmap-size-valid-p (face value)
  "Check bitmap-only faces against the nominal sizes reported by FreeType."
  (or (freetype2-types:ft-face-face-flags-test face '(:scalable))
      (let* ((count (freetype2-types:ft-face-num-fixed-sizes face))
             (sizes (cffi:mem-ref
                     (cffi:foreign-slot-pointer
                      (freetype2-types:w* face)
                      '(:struct freetype2-types::foreign-ft-facerec)
                      'freetype2-types::available-sizes)
                     :pointer)))
        (loop for index below count
              thereis
              (let* ((record (cffi:mem-aptr sizes
                                            '(:struct freetype2-types::foreign-ft-bitmap-size)
                                            index))
                     (point-size (floor (+ (cffi:foreign-slot-value
                                            record '(:struct freetype2-types::foreign-ft-bitmap-size)
                                            'freetype2-types::size) 32) 64))
                     ;; FT_Set_Pixel_Sizes consumes ppem, not the dimensions
                     ;; of the rasterized strike bitmap.
                     (width (/ (cffi:foreign-slot-value
                                record '(:struct freetype2-types::foreign-ft-bitmap-size)
                                'freetype2-types::x-ppem) 64.0))
                     (height (/ (cffi:foreign-slot-value
                                 record '(:struct freetype2-types::foreign-ft-bitmap-size)
                                 'freetype2-types::y-ppem) 64.0)))
                (if (numberp value)
                    (or (= value point-size) (and (= value width) (= value height)))
                    (and (= (first value) width)
                         (or (zerop (second value)) (= (second value) height)))))))))
(defun %set-face-size (face value)
  "Validate a size before changing the face, leaving it untouched on error."
  (multiple-value-bind (width height) (%size-axes value)
    (unless (%bitmap-size-valid-p face value)
      (error "The requested size is not available in this bitmap-only font."))
    (freetype2:set-pixel-sizes face width height)))
(defun size (font)
  "Return the default size in pixels; pairs are fresh (width height) lists."
  (check-type font font)
  (pixelisp.internal:ensure-live font)
  (%copy-size (%size font)))
(defun (setf size) (value font)
  "Set the default pixel size, accepting a scalar or (horizontal vertical) pair."
  (check-type font font)
  (pixelisp.internal:ensure-live font)
  (let ((normalized (%normalize-size value)))
    (%set-face-size (pixelisp.internal:handle font) normalized)
    (setf (slot-value font 'size) normalized)
    ;; SETF returns its new value; do not let that expose the stored pair.
    (%copy-size normalized)))
(defun make-font (&optional filename (size 16) &key (kerning t) (antialiased t))
  "Open a directly rendered FreeType face at SIZE pixels (or (width height))."
  (let ((size (%normalize-size size)))
    (init)
    (let* ((path (or filename (get-default-font)))
           (face (freetype2:new-face path))
           (complete nil) (finalizer-cancelled nil))
      (unwind-protect
           (progn
             ;; Keep the dependency's finalizer until native face setup succeeds.
             (%set-face-size face size)
             (trivial-garbage:cancel-finalization face)
             (setf finalizer-cancelled t)
             (let ((resource (pixelisp.internal:register-resource
                              (make-instance 'font :handle face :path path
                                             :size size :kerning kerning :antialiased antialiased))))
               (setf complete t)
               resource))
        (when (and (not complete) finalizer-cancelled)
          ;; We cancelled FreeType's finalizer immediately before registration.
          (when (not (cffi:null-pointer-p (freetype2-types:fw-ptr face)))
            (freetype2-ffi:ft-done-face (freetype2-types:w* face))
            (freetype2-types:libc-free (freetype2-types:fw-ptr face))
            (setf (freetype2-types:fw-ptr face) (cffi:null-pointer))))))))
(defun font (&optional filename (size 16) &key (kerning t) (antialiased t))
  (make-font filename size :kerning kerning :antialiased antialiased))
(defun sys-font (name size &key bold italic)
  (make-font (or (match-font name :bold bold :italic italic) (get-default-font)) size))
(setf (fdefinition 'sysfont) #'sys-font)
(defun %face (font &optional requested-size)
  (check-type font font)
  (pixelisp.internal:ensure-live font)
  (%set-face-size (pixelisp.internal:handle font)
                  (%normalize-size (or requested-size (%size font))))
  (pixelisp.internal:handle font))
(defun %valid-style-p (value)
  (and (integerp value) (<= 0 value) (= 0 (logandc2 value 15))))
(defun %scalable-font-p (font)
  (freetype2-types:ft-face-face-flags-test (pixelisp.internal:handle font) '(:scalable)))
(defun %rotation-value (value)
  (check-type value integer)
  (mod value 360))
(defun rotation (font)
  (check-type font font)
  (pixelisp.internal:ensure-live font)
  (%rotation font))
(defun (setf rotation) (value font)
  "Set the counterclockwise baseline rotation, normalized to 0 through 359."
  (check-type font font)
  (pixelisp.internal:ensure-live font)
  (let ((normalized (%rotation-value value)))
    (when (and (plusp normalized) (not (%scalable-font-p font)))
      (error 'pixelisp:unsupported-feature :operation 'rotation
             :message "Rotation requires a scalable outline font."))
    (setf (slot-value font 'rotation) normalized)))
(defun vertical (font)
  (check-type font font)
  (pixelisp.internal:ensure-live font)
  (%vertical font))
(defun (setf vertical) (value font)
  "Enable FreeType vertical metrics and top-to-bottom glyph layout."
  (check-type font font)
  (pixelisp.internal:ensure-live font)
  (check-type value boolean)
  (setf (slot-value font 'vertical) value))
(defun style (font)
  (check-type font font) (pixelisp.internal:ensure-live font) (%style font))
(defun (setf style) (value font)
  "Set style flags after validating the mask and font lifetime."
  (check-type font font)
  (pixelisp.internal:ensure-live font)
  (when (eql value style-default) (return-from style (%style font)))
  (unless (%valid-style-p value) (error "STYLE must be a combination of supported style flags."))
  (when (and (logtest value (logior style-oblique style-strong style-wide))
             (not (%scalable-font-p font)))
    (error 'pixelisp:unsupported-feature :operation 'style :message "Synthetic styles require a scalable outline font."))
  (setf (slot-value font 'style) value))
(defun %set-style-bit (font bit enabled)
  (check-type enabled boolean)
  (setf (style font) (if enabled (logior (style font) bit) (logandc2 (style font) bit)))
  enabled)
(defun underline (font) (logtest (style font) style-underline))
(defun (setf underline) (value font) (%set-style-bit font style-underline value))
(defun oblique (font) (logtest (style font) style-oblique))
(defun (setf oblique) (value font) (%set-style-bit font style-oblique value))
(defun strong (font) (logtest (style font) style-strong))
(defun (setf strong) (value font) (%set-style-bit font style-strong value))
(defun wide (font) (logtest (style font) style-wide))
(defun (setf wide) (value font) (%set-style-bit font style-wide value))
(defun strength (font) (check-type font font) (pixelisp.internal:ensure-live font) (%strength font))
(defun (setf strength) (value font)
  (check-type font font) (pixelisp.internal:ensure-live font)
  (check-type value (real 0 1))
  (unless (%scalable-font-p font)
    (error 'pixelisp:unsupported-feature :operation 'strength :message "Synthetic styles require a scalable outline font."))
  (setf (slot-value font 'strength) value))
(defun underline-adjustment (font)
  (check-type font font) (pixelisp.internal:ensure-live font) (%underline-adjustment font))
(defun (setf underline-adjustment) (value font)
  (check-type font font) (pixelisp.internal:ensure-live font)
  (check-type value (real -2.0 2.0))
  (setf (slot-value font 'underline-adjustment) value))
(defmethod pixelisp.internal:dispose ((font font))
  (let* ((face (pixelisp.internal:handle font)) (storage (freetype2-types:fw-ptr face)))
    (freetype2-ffi:ft-done-face (freetype2-types:w* face))
    (freetype2-types:libc-free storage)
    (setf (freetype2-types:fw-ptr face) (cffi:null-pointer))))
(defun close (font) (pixelisp.internal:dispose font))
(defun name (font) (freetype2-types:ft-face-family-name (%face font)))
(defun get-sized-height (font &optional size)
  (multiple-value-bind (x y xs ys asc desc height) (freetype2:face-metrics (%face font size))
    (declare (ignore x y xs ys asc desc)) height))
(defun get-sized-ascender (font &optional size) (freetype2:face-ascender-pixels (%face font size)))
(defun get-sized-descender (font &optional size) (- (freetype2:face-descender-pixels (%face font size))))
(defun get-kerning (font left right &optional size)
  (freetype2:get-kerning (%face font size) left right))
(defun get-metrics (font text &key size)
  "Return (min-x max-x min-y max-y advance-x advance-y), or NIL for missing glyphs."
  (let ((face (%face font size)))
    (loop for character across text collect
      (when (plusp (freetype2:get-char-index face character))
        (freetype2:load-char face character)
        (let* ((slot (freetype2-types:ft-face-glyph face))
               (metrics (freetype2-types:ft-glyphslot-metrics slot))
               (left (/ (freetype2-types:ft-glyph-metrics-hori-bearing-x metrics) 64.0))
               (top (/ (freetype2-types:ft-glyph-metrics-hori-bearing-y metrics) 64.0))
               (width (/ (freetype2-types:ft-glyph-metrics-width metrics) 64.0))
               (height (/ (freetype2-types:ft-glyph-metrics-height metrics) 64.0)))
          (list left (+ left width) (- top height) top (freetype2:get-loaded-advance face nil) 0.0))))))

(defun %rotation-matrix (degrees)
  "Return a FreeType 16.16 matrix for a counterclockwise outline rotation."
  (let ((radians (* pi (/ degrees 180.0))))
    (list (round (* 65536 (cos radians)))
          (round (* -65536 (sin radians)))
          (round (* 65536 (sin radians)))
          (round (* 65536 (cos radians))))))
(defun %transform-outline (outline matrix)
  (cffi:with-foreign-object (native '(:struct freetype2-types::foreign-ft-matrix))
    (setf (cffi:foreign-slot-value native '(:struct freetype2-types::foreign-ft-matrix) 'freetype2-types::xx) (first matrix)
          (cffi:foreign-slot-value native '(:struct freetype2-types::foreign-ft-matrix) 'freetype2-types::xy) (second matrix)
          (cffi:foreign-slot-value native '(:struct freetype2-types::foreign-ft-matrix) 'freetype2-types::yx) (third matrix)
          (cffi:foreign-slot-value native '(:struct freetype2-types::foreign-ft-matrix) 'freetype2-types::yy) (fourth matrix))
    ;; The dependency wraps this void function as an error result, so call its
    ;; raw FFI entry point directly, as the existing synthetic-style path does.
    (freetype2-ffi:ft-outline-transform (freetype2-types:fw-ptr outline) native)))
(defun %vertical-origin-offset (slot)
  "Return the horizontal-to-vertical origin shift in FreeType's 26.6 units."
  (let ((metrics (freetype2-types:ft-glyphslot-metrics slot)))
    (values (- (freetype2-types:ft-glyph-metrics-vert-bearing-x metrics)
               (freetype2-types:ft-glyph-metrics-hori-bearing-x metrics))
            (- (+ (freetype2-types:ft-glyph-metrics-vert-bearing-y metrics)
                  (freetype2-types:ft-glyph-metrics-hori-bearing-y metrics))))))

(defun %style-outline (font outline active-style requested-size)
  "Change the current glyph's shape before its placement and rotation."
  (let* ((pixel-size (%size-vertical (%normalize-size (or requested-size (%size font)))))
         (scale (if (logtest active-style style-wide) (+ 1 (strength font)) 1))
         (shear (if (logtest active-style style-oblique) 0.21255656 0)))
    (%transform-outline outline
                        (list (round (* 65536 scale)) (round (* 65536 shear)) 0 65536))
    (when (logtest active-style style-strong)
      (freetype2:outline-embolden
       outline (round (* 64 pixel-size (strength font)))))))

(defun %raster-layout-glyph (font face character requested-size active-style degrees vertical-layout)
  "Return coverage, bitmap X/Y bearings, and the unrotated pen advance.

Only the reusable glyph slot is modified. Its coverage must be copied before
the next character is loaded; no face-wide transform survives this call."
  (let* ((synthetic (logtest active-style (logior style-oblique style-strong style-wide)))
         (rotated (plusp degrees))
         (flags (append (when (or synthetic rotated) '(:no-bitmap))
                        (when vertical-layout '(:vertical-layout)))))
    (freetype2:load-char face character flags)
    (let* ((slot (freetype2-types:ft-face-glyph face))
           (outline-p (eq :outline (freetype2-types:ft-glyphslot-format slot)))
           (advance (freetype2:get-loaded-advance face vertical-layout))
           (bitmap-offset-x 0) (bitmap-offset-y 0))
      (when (and (or synthetic rotated) (not outline-p))
        (error 'pixelisp:unsupported-feature :operation 'render
               :message "Rotation and synthetic styles require outline glyphs."))
      (let ((outline (when outline-p (freetype2-types:ft-glyphslot-outline slot))))
        ;; Embolden before rotation so strong text rotates as a complete shape.
        (when synthetic (%style-outline font outline active-style requested-size))
        (when vertical-layout
          (multiple-value-bind (dx dy) (%vertical-origin-offset slot)
            (if outline
                (freetype2-ffi:ft-outline-translate (freetype2-types:fw-ptr outline) dx dy)
                ;; Bitmap fonts have no outline. Move their bitmap at placement.
                (setf bitmap-offset-x (round dx 64) bitmap-offset-y (- (round dy 64))))))
        (when rotated (%transform-outline outline (%rotation-matrix degrees))))
      (let* ((rendered (freetype2:render-glyph face (if (antialiased font) :normal :mono)))
             (bitmap (freetype2-types:ft-glyphslot-bitmap rendered))
             (x (+ (freetype2-types:ft-glyphslot-bitmap-left rendered) bitmap-offset-x))
             (y (+ (- (freetype2-types:ft-glyphslot-bitmap-top rendered)) bitmap-offset-y)))
        (multiple-value-bind (coverage mode) (freetype2:bitmap-to-array bitmap)
          (when (eq mode :mono)
            ;; The binding may use BIT storage for monochrome glyphs. Widen it
            ;; before converting 0/1 samples into ordinary byte coverage.
            (let ((bytes (make-array (array-dimensions coverage) :element-type '(unsigned-byte 8))))
              (dotimes (index (array-total-size coverage))
                (setf (row-major-aref bytes index) (* 255 (row-major-aref coverage index))))
              (setf coverage bytes)))
          (values coverage x y
                  (* advance (if (and (not vertical-layout) (logtest active-style style-wide))
                                 (+ 1 (strength font)) 1))))))))

(defun %underline-coverage (font face requested-size advance)
  "Return the ordinary horizontal underline mask and its baseline Y offset."
  (let* ((upem (max 1 (freetype2-types:ft-face-units-per-em face)))
         (adjustment (underline-adjustment font))
         (font-size (%size-vertical (%normalize-size (or requested-size (%size font)))))
         (position (if (minusp adjustment)
                       (* adjustment (freetype2-types:ft-face-ascender face))
                       (* -1 adjustment (freetype2-types:ft-face-underline-position face))))
         (y (round (/ (* font-size position) upem)))
         (height (max 1 (ceiling (* font-size (abs (freetype2-types:ft-face-underline-thickness face))) upem))))
    (values (make-array (list height (ceiling advance)) :element-type '(unsigned-byte 8)
                                                         :initial-element 255)
            y)))

(defun %layout (font text requested-size requested-style requested-rotation)
  "Return glyph placements and their baseline-relative bounds."
  (check-type font font)
  (pixelisp.internal:ensure-live font)
  (unless (or (null requested-style) (eql requested-style style-default) (%valid-style-p requested-style))
    (error "STYLE must be a combination of supported style flags."))
  (let* ((degrees (%rotation-value requested-rotation))
         (active-style (if (or (null requested-style) (eql requested-style style-default))
                           (style font) requested-style))
         (vertical-layout (vertical font))
         (synthetic (logtest active-style (logior style-oblique style-strong style-wide)))
         (rotated (plusp degrees)))
    ;; Validate combinations before loading glyphs, resizing a face, or touching
    ;; a caller's target. These are also pygame's layout restrictions.
    (when (and (or rotated synthetic) (not (%scalable-font-p font)))
      (error 'pixelisp:unsupported-feature :operation 'render
             :message "Rotation and synthetic styles require an outline font."))
    (when (and rotated (logtest active-style style-wide))
      (error 'pixelisp:unsupported-feature :operation 'rotation
             :message "The wide style cannot be combined with rotation."))
    (when (and (or rotated vertical-layout) (logtest active-style style-underline))
      (error 'pixelisp:unsupported-feature :operation 'render
             :message "Underline cannot be combined with rotation or vertical layout."))
    (let* ((face (%face font requested-size))
           (angle (* pi (/ degrees 180)))
           ;; Positive Y points down on a surface. The horizontal axis rotates
           ;; counterclockwise; the vertical axis starts pointing downward.
           (axis-x (if vertical-layout (sin angle) (cos angle)))
           (axis-y (if vertical-layout (cos angle) (- (sin angle))))
           (pen 0.0) (previous nil) (glyphs nil)
           (left 0) (top 0) (right 0) (bottom 0))
      (labels ((record-glyph (x y coverage)
                 (push (list x y coverage) glyphs)
                 (setf left (min left x) top (min top y)
                       right (max right (+ x (array-dimension coverage 1)))
                       bottom (max bottom (+ y (array-dimension coverage 0))))))
        (loop for character across text do
          (when (and previous (kerning font) (not vertical-layout))
            (incf pen (freetype2:get-kerning face previous character)))
          (multiple-value-bind (coverage x y advance)
              (%raster-layout-glyph font face character requested-size active-style degrees vertical-layout)
            (record-glyph (+ (round (* pen axis-x)) x) (+ (round (* pen axis-y)) y) coverage)
            (incf pen advance))
          (setf previous character))
        (when (and (logtest active-style style-underline) (plusp (ceiling pen)))
          (multiple-value-bind (coverage y) (%underline-coverage font face requested-size pen)
            (record-glyph 0 y coverage))))
      ;; Include the advance as well as ink, retaining the existing horizontal
      ;; spacing convention. This can leave padding after the last vertical glyph.
      (let ((end-x (if (and (not rotated) (not vertical-layout)) (ceiling pen) (round (* pen axis-x))))
            (end-y (round (* pen axis-y))))
        (setf left (min left end-x) right (max right end-x)
              top (min top end-y) bottom (max bottom end-y)))
      (values (nreverse glyphs)
              (pixelisp:make-rect left top (max 1 (- right left)) (max 1 (- bottom top)))))))

(defun get-rect (font text &key size (style style-default) (rotation (rotation font)))
  (nth-value 1 (%layout font text size style rotation)))
(defun %blend-glyph-pixel (surface position color coverage)
  "Composite one glyph pixel using straight alpha, including transparent backgrounds."
  (multiple-value-bind (red green blue alpha) (pixelisp.internal:rgba color)
    (let ((source-alpha (* (/ alpha 255.0) (/ coverage 255.0))))
      (when (plusp source-alpha)
        (multiple-value-bind (back-red back-green back-blue back-alpha)
            (pixelisp.internal:rgba (px.surface:get-at surface position))
          (let* ((target-alpha (/ back-alpha 255.0))
                 (remainder (* target-alpha (- 1 source-alpha)))
                 (output-alpha (+ source-alpha remainder))
                 (channels (mapcar (lambda (source target)
                                    (round (/ (+ (* source source-alpha) (* target remainder)) output-alpha)))
                                  (list red green blue) (list back-red back-green back-blue))))
            (px.surface:set-at surface position (append channels (list (round (* 255 output-alpha)))))))))))

(defun render (font text &optional (foreground '(255 255 255 255)) background &key size (style style-default) (rotation (rotation font)))
  "Return a rendered Surface and baseline-relative Rect as two values."
  (multiple-value-bind (glyphs rect) (%layout font text size style rotation)
    (let ((surface (px.surface:make-surface (list (px.rect:width rect) (px.rect:height rect)) :alpha t))
          (complete nil))
      (unwind-protect
           (progn
             (when background (px.surface:fill surface background))
             (dolist (glyph glyphs)
               (destructuring-bind (left top coverage) glyph
                 (dotimes (y (array-dimension coverage 0))
                   (dotimes (x (array-dimension coverage 1))
                     (%blend-glyph-pixel surface
                                         (list (- (+ left x) (px.rect:x rect)) (- (+ top y) (px.rect:y rect)))
                                         foreground (aref coverage y x))))))
             (setf complete t)
             (values surface rect))
        ;; A malformed color or failed pixel write must not leak this new owner.
        (unless complete (pixelisp.internal:dispose surface))))))
(defun render-to (font target destination text &optional (foreground '(255 255 255)) background &key size (style style-default) (rotation (rotation font)))
  "Render to TARGET at a top-left destination, or baseline when ORIGIN is true."
  (pixelisp.internal:ensure-live font)
  (let ((coordinates (%destination-xy destination)))
    (multiple-value-bind (surface rect) (render font text foreground background :size size :style style :rotation rotation)
      (let ((position (if (origin font)
                          (list (+ (first coordinates) (px.rect:x rect))
                                (+ (second coordinates) (px.rect:y rect)))
                          coordinates)))
        (unwind-protect (px.surface:blit target surface position)
          (pixelisp.internal:dispose surface))))))
(defun %destination-xy (destination)
  "Validate a point or Rect destination before allocating a rendered surface."
  (let ((coordinates
          (if (typep destination 'pixelisp:rect)
              (list (pixelisp:rect-x destination) (pixelisp:rect-y destination))
              (and (typep destination 'sequence)
                   (>= (length destination) 2)
                   (list (elt destination 0) (elt destination 1))))))
    (unless (and coordinates (every #'integerp coordinates))
      (error "DEST must be a Rect or provide integer X and Y coordinates."))
    coordinates))
(defun render-raw (font text &key size invert (style style-default) (rotation (rotation font)))
  "Return a packed 8-bit alpha mask and its dimensions as two values."
  (multiple-value-bind (surface rect) (render font text '(255 255 255) nil :size size :style style :rotation rotation)
    (unwind-protect
         (let* ((width (px.surface:width surface)) (height (px.surface:height surface))
                (bytes (make-array (* width height) :element-type '(unsigned-byte 8))))
           (dotimes (y height) (dotimes (x width)
             (setf (aref bytes (+ x (* y width)))
                   (let ((coverage (nth-value 3 (pixelisp.internal:rgba (px.surface:get-at surface (list x y))))))
                     (if invert (- 255 coverage) coverage)))))
           (values bytes (list width height)))
      (pixelisp.internal:dispose surface))))

(defun %raw-target-info (target)
  "Validate a writable integer array or byte buffer view before rendering."
  (cond
    ((typep target 'px.buffer:buffer-view)
     (pixelisp.internal:ensure-live target)
     (let ((dimensions (px.buffer:dimensions target))
           (element-type (px.buffer:element-type target)))
       (unless (and (= (length dimensions) 2)
                    (equal element-type '(unsigned-byte 8))
                    (px.buffer::view-writer target))
         (error "TARGET must be a writable rank-two unsigned-byte-8 buffer view."))
       (values (first dimensions) (second dimensions) :view)))
    ((and (arrayp target) (= (array-rank target) 2))
     (unless (and (subtypep (array-element-type target) 'integer)
                  (subtypep '(integer 0 255) (array-element-type target)))
       (error "TARGET must be a rank-two integer array able to hold values from 0 through 255."))
     (values (array-dimension target 0) (array-dimension target 1) :array))
    (t (error "TARGET must be a rank-two integer array or byte buffer view."))))
(defun render-raw-to (font target text &key (dest '(0 0)) size invert (style style-default) (rotation (rotation font)))
  "Write nonzero glyph coverage into TARGET and return the font's original bounds.

TARGET is indexed in Pixelisp's X,Y axis order. Arrays use AREF and buffer views
use their indexed byte accessors. DEST is top-left unless FONT's ORIGIN is true,
when it denotes the baseline. The returned baseline-relative Rect is unchanged by
DEST and is returned in full even when TARGET clips the writes."
  ;; Do all input/target checks and rasterization before the first target write.
  (pixelisp.internal:ensure-live font)
  (let ((coordinates (%destination-xy dest)))
    (multiple-value-bind (target-width target-height target-kind) (%raw-target-info target)
      (multiple-value-bind (bytes dimensions) (render-raw font text :size size :style style :rotation rotation)
        (let* ((bounds (get-rect font text :size size :style style :rotation rotation))
               (glyph-width (first dimensions)) (glyph-height (second dimensions))
               (x0 (if (origin font) (+ (first coordinates) (px.rect:x bounds)) (first coordinates)))
               (y0 (if (origin font) (+ (second coordinates) (px.rect:y bounds)) (second coordinates)))
               (left (max 0 x0)) (top (max 0 y0))
               (right (min target-width (+ x0 glyph-width)))
               (bottom (min target-height (+ y0 glyph-height))))
          (when (and (< left right) (< top bottom))
            (loop for y from top below bottom do
              (loop for x from left below right
                    for coverage = (aref bytes (+ (- x x0) (* (- y y0) glyph-width)))
                    unless (zerop coverage) do
                      (let ((value (if invert (- 255 coverage) coverage)))
                        (if (eq target-kind :view)
                            (setf (px.buffer:view-ref target x y) value)
                            (setf (aref target x y) value))))))
          bounds)))))

(pushnew #'quit pixelisp.internal:*shutdown-hooks*)
