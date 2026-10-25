(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defun %freetype-layout-occupied-pixels (font text rotation)
  "Return alpha-covered pixels in baseline-relative coordinates."
  (multiple-value-bind (mask dimensions)
      (px.freetype:render-raw font text :rotation rotation)
    (let* ((bounds (px.freetype:get-rect font text :rotation rotation))
           (width (first dimensions)) (height (second dimensions)) (points nil))
      (dotimes (y height)
        (dotimes (x width)
          (when (plusp (aref mask (+ x (* y width))))
            (push (list (+ x (px.rect:x bounds)) (+ y (px.rect:y bounds))) points))))
      points)))

(test freetype-rotation-normalizes-and-per-call-overrides-are-scoped
  (let ((font (px.freetype:make-font nil 24)))
    (unwind-protect
         (progn
           (setf (px.freetype:rotation font) -45)
           (is (= 315 (px.freetype:rotation font)))
           (setf (px.freetype:rotation font) 725)
           (is (= 5 (px.freetype:rotation font)))
           (signals type-error (setf (px.freetype:rotation font) 1.5))
           (let ((stored (px.freetype:rotation font))
                 (upright (px.freetype:get-rect font "Rotate" :rotation 0))
                 (turned (px.freetype:get-rect font "Rotate" :rotation 90)))
             (is (= stored (px.freetype:rotation font)))
             (is (not (equalp upright turned)))
             (is (minusp (px.rect:y turned)))
             (is (= 5 (px.freetype:rotation font))))
           (setf (px.freetype:rotation font) 0)
           (multiple-value-bind (mask dimensions)
               (px.freetype:render-raw font "Rotate" :rotation 90)
             (is (plusp (length mask)))
             (is (plusp (first dimensions)))
             (is (plusp (second dimensions)))
             (is (= 0 (px.freetype:rotation font)))))
      (px:dispose font))))

(test freetype-rotated-raster-is-nonempty-and-matches-render-to-baseline
  (let ((font (px.freetype:make-font nil 26))
        (surface (px.surface:make-surface '(120 100) :alpha t))
        (target (make-array '(120 100) :element-type '(unsigned-byte 8) :initial-element 0)))
    (unwind-protect
         (progn
           (setf (px.freetype:origin font) t)
           (let* ((bounds (px.freetype:get-rect font "A" :rotation 90))
                (baseline '(50 50))
                (painted (px.freetype:render-to font surface baseline "A" '(255 255 255) nil :rotation 90))
                (raw-bounds (px.freetype:render-raw-to font target "A" :dest baseline :rotation 90)))
           (is (= (+ 50 (px.rect:x bounds)) (px.rect:x painted)))
           (is (= (+ 50 (px.rect:y bounds)) (px.rect:y painted)))
           (is (equalp bounds raw-bounds))
           (is (equalp target (px.surfarray:array-alpha surface)))
           (is (loop for index below (array-total-size target)
                     thereis (plusp (row-major-aref target index))))
           (is (minusp (px.rect:y bounds)))))
      (px:dispose surface)
      (px:dispose font))))

(test freetype-diagonal-rotation-has-usable-bounds-and-vertical-layout-advances
  (let ((font (px.freetype:make-font nil 22)))
    (unwind-protect
         (let* ((diagonal (px.freetype:get-rect font "ABC" :rotation 45))
                (single (px.freetype:get-rect font "A"))
                (normal-pixels (%freetype-layout-occupied-pixels font "L" 0))
                (turned-pixels (%freetype-layout-occupied-pixels font "L" 90)))
           (is (plusp (px.rect:width diagonal)))
           (is (plusp (px.rect:height diagonal)))
           ;; A counterclockwise quarter-turn maps screen (x,y) to (y,-x).
           ;; Allow one pixel for FreeType's final raster rounding.
           (is (every (lambda (point)
                        (some (lambda (actual)
                                (and (<= (abs (+ (first point) (second actual))) 1)
                                     (<= (abs (- (second point) (first actual))) 1)))
                              turned-pixels))
                      normal-pixels))
           (setf (px.freetype:vertical font) t)
           (is (px.freetype:vertical font))
           (let ((vertical-single (px.freetype:get-rect font "A"))
                 (vertical-run (px.freetype:get-rect font "ABC")))
             (is (> (px.rect:height vertical-run) (* 2 (px.rect:height vertical-single))))
             ;; The first glyph straddles the vertical pen; subsequent glyphs
             ;; advance down the column without growing its horizontal width.
             (is (minusp (px.rect:x vertical-single)))
             (is (plusp (+ (px.rect:x vertical-single) (px.rect:width vertical-single))))
             (is (< (px.rect:width vertical-run) (+ (px.rect:width single) 10)))))
      (px:dispose font))))

(test freetype-rotated-combinations-and-bitmap-rejection-do-not-change-state
  (let ((outline (px.freetype:make-font nil 20))
        (bitmap (px.freetype:make-font
                 (asdf:system-relative-pathname "pixelisp/tests" "tests/fixtures/tiny-mono.bdf") 8))
        (surface (px.surface:make-surface '(40 30) :alpha t))
        (raw-target (make-array '(40 30) :element-type '(unsigned-byte 8) :initial-element 37)))
    (unwind-protect
         (progn
           (setf (px.freetype:wide outline) t)
           (signals px:unsupported-feature (px.freetype:render-raw outline "A" :rotation 30))
           (is (= 0 (px.freetype:rotation outline)))
           (setf (px.freetype:style outline) px.freetype:style-underline)
           (signals px:unsupported-feature (px.freetype:render-to outline surface '(2 3) "A" '(255 255 255) nil :rotation 30))
           (signals px:unsupported-feature (px.freetype:render-raw-to outline raw-target "A" :rotation 30))
           (is (loop for index below (array-total-size raw-target)
                     always (= 37 (row-major-aref raw-target index))))
           (is (every (lambda (x)
                        (every (lambda (y)
                                 (zerop (nth-value 3 (pixelisp.internal:rgba
                                                     (px.surface:get-at surface (list x y))))))
                               (loop for y below 30 collect y)))
                      (loop for x below 40 collect x)))
           (signals px:unsupported-feature
             (px.freetype:render-raw outline "A" :style px.freetype:style-underline :rotation 90))
           (setf (px.freetype:style outline) px.freetype:style-normal
                 (px.freetype:vertical outline) t)
           (signals px:unsupported-feature
             (px.freetype:render-raw outline "A" :style px.freetype:style-underline))
           (setf (px.freetype:vertical outline) nil)
           (signals px:unsupported-feature (setf (px.freetype:rotation bitmap) 90))
           (signals px:unsupported-feature (px.freetype:get-rect bitmap "A" :rotation 90))
           (is (= 0 (px.freetype:rotation bitmap))))
      (px:dispose surface)
      (px:dispose outline)
      (px:dispose bitmap))))

(test freetype-rotation-and-vertical-properties-check-font-lifetime
  (let ((font (px.freetype:make-font nil 18)))
    (px:dispose font)
    (signals px:disposed-resource (px.freetype:rotation font))
    (signals px:disposed-resource (px.freetype:vertical font))
    (signals px:disposed-resource (setf (px.freetype:rotation font) 90))
    (signals px:disposed-resource (setf (px.freetype:vertical font) t))))

(test freetype-monochrome-rotation-keeps-byte-coverage
  (px:with-resource (font (px.freetype:make-font nil 22))
    (setf (px.freetype:antialiased font) nil)
    (multiple-value-bind (bytes dimensions) (px.freetype:render-raw font "L" :rotation -90)
      (is (= (length bytes) (apply #'* dimensions)))
      (is (some #'plusp bytes))
      (is (every (lambda (value) (member value '(0 255))) bytes)))))
