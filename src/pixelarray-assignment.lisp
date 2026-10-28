;;;; Color-aware and bulk assignment for pygame-style PixelArray views.
(in-package #:pixelisp.pixelarray)

(defun (setf ref) (color pixels &rest indices)
  "Store COLOR at PIXELS indices and return the original color value.

Integers are native packed pixel values. Colors, RGB(A) lists or vectors, and
color strings are mapped through the surface format. The raw integer getter
continues to return packed values, just as pygame's PixelArray does."
  (let* ((surface (%validate-pixel-array pixels))
         (packed (%packed-color surface color)))
    (apply #'(setf px.buffer:view-ref) packed pixels indices)
    color))

(defun %color-value-p (value)
  "Whether VALUE represents one color rather than a collection of pixels."
  (or (integerp value) (stringp value) (typep value 'pixelisp:color)
      (and (typep value 'sequence) (member (length value) '(3 4)))))

(defun %array-pixel-value (array x y)
  (aref array (if (= (array-dimension array 0) 1) 0 x)
             (if (= (array-dimension array 1) 1) 0 y)))

(defun %pixel-source-kind (source)
  "Classify SOURCE without mistaking an RGB vector for a pixel collection."
  (cond
    ((typep source 'px.buffer:buffer-view) :pixel-array)
    ((arrayp source)
     (if (= (array-rank source) 2)
         :array
         (if (%color-value-p source)
             :color
             (error "A pixel source array must have rank two."))))
    ((%color-value-p source) :color)
    (t (error "Source must be a color, a rank-two array, or a PixelArray."))))

(defun %assignment-dimensions (target source-dimensions kind)
  "Check broadcasting rules and return TARGET's (width height)."
  (let ((target-dimensions (%pixel-logical-dimensions target)))
    (unless (= (length target-dimensions) 2)
      (error "Assignment target must have two dimensions."))
    (unless (eq kind :color)
      (unless (and (= (length source-dimensions) 2)
                   (every (lambda (from to) (or (= from to) (= from 1)))
                          source-dimensions target-dimensions))
        (error "Source dimensions must match the target or be one along either axis.")))
    target-dimensions))

(defun %source-color-at (target-surface source kind source-surface source-dimensions
                         same-layout-p x y)
  "Read one source value and map it to the target's native packed format."
  (case kind
    (:color (%packed-color target-surface source))
    (:array (%packed-color target-surface (%array-pixel-value source x y)))
    (:pixel-array
     (let* ((sx (if (= (first source-dimensions) 1) 0 x))
            (sy (if (= (second source-dimensions) 1) 0 y))
            (packed (if (= (length (px.buffer:dimensions source)) 1)
                        (px.buffer:view-ref source sx)
                        (px.buffer:view-ref source sx sy))))
       ;; Packed integers are meaningful in the same native depth and masks.
       ;; For indexed formats this intentionally preserves palette indices,
       ;; even when the two surfaces have distinct palettes.
       (if same-layout-p
           packed
           (%packed-color target-surface
                          (px.color:to-list
                           (px.surface:unmap-rgb source-surface packed))))))))

(defun assign (target source)
  "Fill TARGET from SOURCE and return TARGET.

TARGET may be a rank-one or rank-two packed PixelArray slice or transpose.
SOURCE may be one packed integer, color string, RGB(A) list or vector, a
rank-two Lisp array of such values, or another PixelArray. A one-dimensional
PixelArray is treated as an N-by-1 source, so it can fill one row and broadcast
across a two-dimensional target's height. PixelArray dimensions must match
TARGET's logical shape or be one on an axis, in which case that axis
broadcasts. PixelArray sources with matching depth and masks preserve raw values; other layouts
remap their decoded colors. The complete result is
validated and snapshotted before writing, so overlapping views are safe and
bad input never leaves a partly changed target. For PixelArray sources with
the same native depth and channel masks, raw packed values are copied exactly;
this also preserves indexed pixels across distinct palettes. Other layouts
copy visible colors by decoding and remapping."
  (let* ((target-surface (%validate-pixel-array target))
         (kind (%pixel-source-kind source))
         (source-surface (when (eq kind :pixel-array)
                           (%validate-pixel-array source)))
         (source-dimensions
           (case kind
             (:pixel-array (%pixel-logical-dimensions source))
             (:array (array-dimensions source))))
         (same-layout-p
           (and source-surface
                (= (px.surface:get-bitsize target-surface)
                   (px.surface:get-bitsize source-surface))
                (equal (px.surface:get-masks target-surface)
                       (px.surface:get-masks source-surface))))
         (dimensions (%assignment-dimensions target source-dimensions kind)))
    (destructuring-bind (width height) dimensions
      ;; Stage mapped values first: this handles aliasing, and validates every
      ;; element before any byte of the destination gets changed.
      (let ((values (make-array (* width height)
                                :element-type `(unsigned-byte ,(* 8 (px.surface:get-bytesize target-surface))))))
        (dotimes (x width)
          (dotimes (y height)
            (setf (aref values (+ (* x height) y))
                  (%source-color-at target-surface source kind source-surface
                                    source-dimensions same-layout-p x y))))
        (dotimes (x width)
          (dotimes (y height)
            ;; The snapshot has already validated every value, so write the
            ;; packed integers directly without repeating color conversion.
            (%pixel-set-at target (aref values (+ (* x height) y)) x y)))))
  target))

(export 'assign)
