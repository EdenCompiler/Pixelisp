;;;; Small pixel fixtures make clipping, alpha preservation, and transform
;;;; orientation visible without a window, screenshot comparison, or GPU driver.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defmacro with-graphics-surfaces (bindings &body body)
  "Dispose test surfaces even when an assertion or native operation signals."
  (if bindings
      `(pixelisp:with-resource ,(first bindings)
         (with-graphics-surfaces ,(rest bindings) ,@body))
      `(progn ,@body)))

(defun graphics-rgba (surface position)
  (multiple-value-list (pixelisp.internal:rgba (px.surface:get-at surface position))))

(test vector-arithmetic-and-degeneracies
  (let ((vector (px:make-vector2 3 4)))
    (is (= 5 (px.math:length vector)))
    (is (= 25 (px.math:length-squared vector)))
    (is (= 11 (px.math:dot vector '(1 2))))
    (is (= 2 (px.math:cross vector '(1 2))))
    (is (equal '(6 8) (px.math:components (px.math:multiply vector 2))))
    (is (< (abs (- 1 (px.math:length (px.math:normalize vector)))) 1d-8))
    (is (equal '(3 4) (px.math:components vector)))
    (px.math:normalize-ip vector)
    (is (px.math:is-normalized-p vector)))
  (signals error (px.math:normalize (px:make-vector2)))
  (signals error (px.math:dot '(1 2) '(1 2 3)))
  (signals error (px.math:project (px:make-vector2 2 3) (px:make-vector2))))

(test vector-rotation-projection-and-interpolation
  (let ((rotated (px.math:rotate (px:make-vector2 1 0) 90)))
    (is (< (abs (px.math:x rotated)) 1d-8))
    (is (< (abs (- 1 (px.math:y rotated))) 1d-8)))
  (let ((cross (px.math:cross (px:make-vector3 1 0 0) (px:make-vector3 0 1 0))))
    (is (equal '(0 0 1) (px.math:components cross))))
  (is (equal '(2 0) (px.math:components (px.math:project (px:make-vector2 2 3) (px:make-vector2 1 0)))))
  (is (equalp '(2 -3) (px.math:components (px.math:reflect (px:make-vector2 2 3) (px:make-vector2 0 1)))))
  (is (equal '(5 10) (px.math:components (px.math:lerp (px:make-vector2 0 0) (px:make-vector2 10 20) 1/2)))))

(test draw-clipping-and-unbounded-segments
  (with-graphics-surfaces ((surface (px.surface:make-surface '(8 8) :alpha t)))
    (px.surface:set-clip surface (px:make-rect 2 2 3 3))
    (let ((damage (px.draw:line surface '(255 0 0) '(-1000000 3) '(1000000 3))))
      (is (= 2 (px:rect-x damage)))
      (is (= 3 (px:rect-width damage))))
    (is (equal '(255 0 0 255) (graphics-rgba surface '(2 3))))
    (is (equal '(0 0 0 0) (graphics-rgba surface '(1 3))))
    (is-false (px.surface:locked-p surface))
    (px.draw:rect surface '(0 255 0 100) '(0 0 8 8))
    (is (equal '(0 255 0 100) (graphics-rgba surface '(4 4))))
    (is (equal '(0 0 0 0) (graphics-rgba surface '(5 4))))))

(test draw-fill-outline-and-polygon
  (with-graphics-surfaces ((surface (px.surface:make-surface '(12 12) :alpha t)))
    (px.draw:rect surface '(255 0 0) '(1 1 10 10) :width 2)
    (is (equal '(255 0 0 255) (graphics-rgba surface '(1 1))))
    (is (equal '(0 0 0 0) (graphics-rgba surface '(5 5))))
    (px.draw:polygon surface '(0 255 0) '((3 3) (9 3) (6 9)))
    (is (equal '(0 255 0 255) (graphics-rgba surface '(6 4))))
    (px.draw:ellipse surface '(0 0 255) '(4 4 4 4))
    (is (equal '(0 0 255 255) (graphics-rgba surface '(5 5))))
    (px.draw:circle surface '(255 255 255) '(6 6) 2 :width 1)
    (is (equal '(255 255 255 255) (graphics-rgba surface '(8 6))))
    (signals error (px.draw:polygon surface '(1 2 3) '((1 2) (3 4))))))

(test draw-zero-radius-circle-is-empty
  (with-graphics-surfaces ((surface (px.surface:make-surface '(3 3) :alpha t)))
    (px.surface:fill surface '(1 2 3 4))
    ;; A point-sized circle is empty in the pygame reference. Check both the
    ;; reported damage and the pixels so a renderer change cannot hide a write.
    (let ((damage (px.draw:circle surface '(255 255 0) '(1 1) 0)))
      (is (= 0 (px:rect-width damage)))
      (is (= 0 (px:rect-height damage))))
    (loop for y below 3 do
      (loop for x below 3 do
        (is (equal '(1 2 3 4) (graphics-rgba surface (list x y))))))))

(test draw-antialiasing-and-gfxdraw
  (with-graphics-surfaces ((surface (px.surface:make-surface '(12 12) :alpha t)))
    (px.draw:aaline surface '(255 255 255 255) '(1 1) '(9 4))
    (is (< 0 (fourth (graphics-rgba surface '(3 1))) 255))
    (px.gfxdraw:box surface 0 7 2 9 '(20 30 40 50))
    (is (equal '(20 30 40 50) (graphics-rgba surface '(2 9))))
    (px.gfxdraw:bezier surface '((1 6) (6 1) (10 6)) 20 '(255 0 255))
    (is-false (px.surface:locked-p surface))))

(test transforms-copy-pixels-instead-of-blending
  (with-graphics-surfaces ((source (px.surface:make-surface '(2 3) :alpha t)))
    (loop for y below 3 do
      (loop for x below 2 do
        (px.surface:set-at source (list x y) (list (+ 10 (* y 2) x) 20 30 80))))
    (px.surface:set-alpha source 100)
    (with-graphics-surfaces ((flipped (px.transform:flip source t nil))
                            (scaled (px.transform:scale source '(4 6)))
                            (rotated (px.transform:rotate source 90)))
      (is (equal '(11 20 30 80) (graphics-rgba flipped '(0 0))))
      (is (equal '(10 20 30 80) (graphics-rgba scaled '(0 0))))
      (is (equal '(15 20 30 80) (graphics-rgba scaled '(3 5))))
      (is (= 100 (px.surface:get-alpha flipped)))
      (is (equal '(3 2) (px.surface:size rotated)))
      (is (equal '(11 20 30 80) (graphics-rgba rotated '(0 0))))
      (is (equal '(14 20 30 80) (graphics-rgba rotated '(2 1))))
      (is (equal '(10 20 30 80) (graphics-rgba source '(0 0)))))))

(test filtered-transforms-and-color-operations
  (with-graphics-surfaces ((source (px.surface:make-surface '(2 2) :alpha t)))
    (px.surface:set-at source '(0 0) '(0 0 0 0))
    (px.surface:set-at source '(1 0) '(100 0 0 85))
    (px.surface:set-at source '(0 1) '(200 0 0 170))
    (px.surface:set-at source '(1 1) '(255 0 0 255))
    (with-graphics-surfaces ((average (px.transform:smoothscale source '(1 1)))
                            (large (px.transform:scale2x source))
                            (gray (px.transform:grayscale source)))
      (is (equal '(139 0 0 128) (graphics-rgba average '(0 0))))
      (is (equal '(4 4) (px.surface:size large)))
      (let ((channels (graphics-rgba gray '(1 1))))
        (is (= (first channels) (second channels) (third channels)))
        (is (= 255 (fourth channels))))
      (is (= 1 (px.transform:threshold nil source '(100 0 0 85)
                                       :threshold '(0 0 0 0) :set-behavior 0))))))

(test mask-alpha-threshold-and-colorkey
  (with-graphics-surfaces ((source (px.surface:make-surface '(4 1) :alpha t)))
    (loop for x below 4 for alpha in '(0 127 128 255)
          do (px.surface:set-at source (list x 0) (list x 0 0 alpha)))
    (let ((mask (px.mask:from-surface source)))
      (is (= 2 (px.mask:count mask)))
      (is (= 0 (px.mask:get-at mask '(1 0))))
      (is (= 1 (px.mask:get-at mask '(2 0)))))
    (px.surface:set-colorkey source '(2 0 0))
    (let ((mask (px.mask:from-surface source)))
      (is (= 3 (px.mask:count mask)))
      (is (= 1 (px.mask:get-at mask '(0 0))))
      (is (= 0 (px.mask:get-at mask '(2 0)))))))

(test mask-overlap-copy-and-mutation
  (let ((first (px:make-mask '(3 3) :fill t)) (second (px:make-mask '(2 2) :fill t)))
    (is (= 4 (px.mask:overlap-area first second '(1 1))))
    (is (= 1 (px.mask:overlap-area first second '(-1 -1))))
    (is-false (px.mask:overlap first second '(3 0)))
    (is (equal '(1 1) (px.mask:overlap first second '(1 1))))
    (is (= 4 (px.mask:count (px.mask:overlap-mask first second '(1 1)))))
    (let ((copy (px.mask:copy first)))
      (px.mask:erase copy second '(1 1))
      (is (= 5 (px.mask:count copy)))
      (is (= 9 (px.mask:count first)))
      (px.mask:invert copy)
      (is (= 4 (px.mask:count copy)))
      (px.mask:clear copy)
      (px.mask:draw copy second '(-1 -1))
      (is (= 1 (px.mask:count copy))))
    (signals error (px.mask:get-at first '(3 0)))))

(test mask-components-and-centroid
  (let ((mask (px:make-mask '(6 4))))
    (px.mask:set-at mask '(0 0))
    (px.mask:set-at mask '(1 1))
    (px.mask:set-at mask '(5 3))
    (is (= 2 (length (px.mask:connected-components mask))))
    (is (= 2 (px.mask:count (px.mask:connected-component mask))))
    (is (= 1 (px.mask:count (px.mask:connected-component mask '(5 3)))))
    (is (= 2 (length (px.mask:get-bounding-rects mask))))
    (is (equal '(2 1) (px.mask:centroid mask)))
    (is (= 12 (px.mask:count (px.mask:scale mask '(12 8)))))))

(test mask-convolution-offset-and-destination-size
  (let* ((first (px:make-mask '(2 2)))
         (second (px:make-mask '(1 1)))
         (destination (px:make-mask '(2 2))))
    (px.mask:set-at first '(0 0))
    (px.mask:set-at second '(0 0))
    ;; Position arrays are accepted anywhere the mask API takes an offset.
    (is (eq destination (px.mask:convolve first second destination #(1 0))))
    (is (= 1 (px.mask:get-at destination '(1 0))))
    (signals error (px.mask:convolve first second (px:make-mask '(1 1))))))

(test mask-angle-uses-fractional-centroid
  ;; The integer centroid is (1, 0), but the actual center is (4/3, 2/3).
  ;; Rounding it before computing covariance changes the principal axis.
  (let ((mask (px:make-mask '(5 3))))
    (px.mask:set-at mask '(0 0))
    (px.mask:set-at mask '(4 0))
    (px.mask:set-at mask '(0 2))
    (is (< (abs (- (/ (* 90d0 (atan 2/3)) pi) (px.mask:angle mask))) 1d-8))))

(defclass graphics-moving-sprite (px.sprite:sprite) ())
(defmethod px.sprite:update ((sprite graphics-moving-sprite) &rest arguments)
  (incf (px:rect-x (px.sprite:rect sprite)) (or (first arguments) 1)))

(test sprite-memberships-layers-and-update
  (let* ((first (make-instance 'graphics-moving-sprite :rect (px:make-rect 0 0 2 2) :layer 2))
         (second (px:make-sprite :rect (px:make-rect 1 1 2 2) :layer -1))
         (group (px.sprite:make-layered-group first second))
         (other (px:make-group first)))
    (is (equal (list second first) (px.sprite:sprites group)))
    (px.sprite:update group 4)
    (is (= 4 (px:rect-x (px.sprite:rect first))))
    (px.sprite:change-layer group first -2)
    (is (equal (list first second) (px.sprite:sprites group)))
    (is (px.sprite:has-p other first))
    (px.sprite:kill first)
    (is-false (px.sprite:alive-p first))
    (is (= 0 (px.sprite:group-size other)))
    (is (= 1 (px.sprite:group-size group)))))

(test sprite-collision-and-dirty-background-restoration
  (with-graphics-surfaces ((image (px.surface:make-surface '(2 2)))
                          (target (px.surface:make-surface '(8 4)))
                          (background (px.surface:make-surface '(8 4))))
    (px.surface:fill image '(255 0 0))
    (px.surface:fill background '(0 0 0))
    (let* ((sprite (px.sprite:make-dirty-sprite :image image :rect (px:make-rect 0 0 2 2)))
           (other (px:make-sprite :rect (px:make-rect 1 1 2 2)))
           (group (px.sprite:make-layered-dirty-group sprite)))
      (is (px.sprite:collide-rect sprite other))
      (is (equal (list sprite) (px.sprite:sprite-collide other group)))
      (is-true (not (null (px.sprite:draw group target background))))
      (is-false (px.sprite:draw group target))
      (setf (px:rect-x (px.sprite:rect sprite)) 4)
      (px.sprite:draw group target)
      (is (equal '(0 0 0 255) (graphics-rgba target '(0 0))))
      (is (equal '(255 0 0 255) (graphics-rgba target '(4 0))))
      (setf (px.sprite:visible-p sprite) nil)
      (px.sprite:draw group target)
      (is (equal '(0 0 0 255) (graphics-rgba target '(4 0)))))))
