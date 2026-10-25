;;;; FreeType is a separate optional system, independent of SDL_ttf rendering.
;;;; Each Font owns a face. Loading a glyph reuses FreeType's glyph slot, so we
;;;; copy its coverage bitmap before loading the next glyph. Layout positions
;;;; use baseline coordinates and account for bearings, advances, and kerning.
(defpackage #:pixelisp.freetype
  (:use #:cl) (:nicknames #:px.freetype) (:shadow #:close)
  (:export #:init #:quit #:get-init #:font #:make-font #:sys-font #:sysfont
           #:close #:get-version #:get-fonts #:match-font #:get-default-font
           #:get-metrics #:get-kerning #:get-rect #:render #:render-to #:render-raw
           #:size #:kerning #:antialiased #:origin #:get-sized-height #:get-sized-ascender
           #:get-sized-descender #:name #:render-raw-to))
(in-package #:pixelisp.freetype)
(defvar *initialized* t)
(defclass font (pixelisp.internal:resource)
  ((size :initarg :size :accessor size)
   (kerning :initarg :kerning :initform t :accessor kerning)
   (antialiased :initarg :antialiased :initform t :accessor antialiased)
   (origin :initarg :origin :initform nil :accessor origin)
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
(defun make-font (&optional filename (size 16) &key (kerning t) (antialiased t))
  "Open a directly rendered FreeType face at SIZE pixels."
  (check-type size (real (0) *))
  (init)
  (let* ((path (or filename (get-default-font)))
         (face (freetype2:new-face path))
         (complete nil) (finalizer-cancelled nil))
    (unwind-protect
         (progn
           ;; Keep the dependency's finalizer until native face setup succeeds.
           (freetype2:set-pixel-sizes face 0 (max 1 (round size)))
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
          (setf (freetype2-types:fw-ptr face) (cffi:null-pointer)))))))
(defun font (&optional filename (size 16) &key (kerning t) (antialiased t))
  (make-font filename size :kerning kerning :antialiased antialiased))
(defun sys-font (name size &key bold italic)
  (make-font (or (match-font name :bold bold :italic italic) (get-default-font)) size))
(setf (fdefinition 'sysfont) #'sys-font)
(defun %face (font &optional requested-size)
  (check-type font font)
  (pixelisp.internal:ensure-live font)
  (freetype2:set-pixel-sizes (pixelisp.internal:handle font) 0 (max 1 (round (or requested-size (size font)))))
  (pixelisp.internal:handle font))
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

(defun %layout (font text requested-size)
  "Return glyph coverage placements and their baseline-relative bounding box."
  (let ((face (%face font requested-size)) (pen 0.0) (previous nil) (glyphs nil)
        (left 0) (top 0) (right 0) (bottom 0))
    (loop for character across text do
      (when (and previous (kerning font)) (incf pen (freetype2:get-kerning face previous character)))
      (freetype2:load-char face character)
      (let* ((slot (freetype2:render-glyph face (if (antialiased font) :normal :mono)))
             (bitmap (freetype2-types:ft-glyphslot-bitmap slot))
             (x (+ (round pen) (freetype2-types:ft-glyphslot-bitmap-left slot)))
             (y (- (freetype2-types:ft-glyphslot-bitmap-top slot))))
        (multiple-value-bind (coverage mode) (freetype2:bitmap-to-array bitmap)
          (when (eq mode :mono)
            (dotimes (i (array-total-size coverage)) (setf (row-major-aref coverage i) (* 255 (row-major-aref coverage i)))))
          (push (list x y coverage) glyphs)
          (setf left (min left x) top (min top y)
                right (max right (+ x (array-dimension coverage 1)))
                bottom (max bottom (+ y (array-dimension coverage 0)))))
      (incf pen (freetype2:get-loaded-advance face nil))
      (setf previous character)))
    (values (nreverse glyphs) (pixelisp:make-rect left top (max 1 (- (max right (ceiling pen)) left))
                                                (max 1 (- bottom top))))))
(defun get-rect (font text &key size)
  (nth-value 1 (%layout font text size)))
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

(defun render (font text &optional (foreground '(255 255 255 255)) background &key size)
  "Return a rendered Surface and baseline-relative Rect as two values."
  (multiple-value-bind (glyphs rect) (%layout font text size)
    (let ((surface (px.surface:make-surface (list (px.rect:width rect) (px.rect:height rect)) :alpha t)))
      (when background (px.surface:fill surface background))
      (dolist (glyph glyphs)
        (destructuring-bind (left top coverage) glyph
          (dotimes (y (array-dimension coverage 0))
            (dotimes (x (array-dimension coverage 1))
              (%blend-glyph-pixel surface
                                  (list (- (+ left x) (px.rect:x rect)) (- (+ top y) (px.rect:y rect)))
                                  foreground (aref coverage y x))))))
      (values surface rect))))
(defun render-to (font target destination text &optional (foreground '(255 255 255)) background &key size)
  "Render to TARGET at a top-left destination, or baseline when ORIGIN is true."
  (pixelisp.internal:ensure-live font)
  (let ((coordinates (%destination-xy destination)))
    (multiple-value-bind (surface rect) (render font text foreground background :size size)
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
(defun render-raw (font text &key size invert)
  "Return a packed 8-bit alpha mask and its dimensions as two values."
  (multiple-value-bind (surface rect) (render font text '(255 255 255) nil :size size)
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
(defun render-raw-to (font target text &key (dest '(0 0)) size invert)
  "Write nonzero glyph coverage into TARGET and return the font's original bounds.

TARGET is indexed in Pixelisp's X,Y axis order. Arrays use AREF and buffer views
use their indexed byte accessors. DEST is top-left unless FONT's ORIGIN is true,
when it denotes the baseline. The returned baseline-relative Rect is unchanged by
DEST and is returned in full even when TARGET clips the writes."
  ;; Do all input/target checks and rasterization before the first target write.
  (pixelisp.internal:ensure-live font)
  (let ((coordinates (%destination-xy dest)))
    (multiple-value-bind (target-width target-height target-kind) (%raw-target-info target)
      (multiple-value-bind (bytes dimensions) (render-raw font text :size size)
        (let* ((bounds (get-rect font text :size size))
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
