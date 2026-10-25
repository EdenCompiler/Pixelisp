(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test freetype-two-axis-size-keeps-independent-horizontal-and-vertical-ppem
  (let* ((requested (vector 14 30))
         (font (px.freetype:make-font nil requested)))
    (unwind-protect
         (let* ((stored (px.freetype:size font))
                (normal (px.freetype:get-rect font "Wide"))
                (scalar (px.freetype:get-rect font "Wide" :size 22)))
           (is (equal '(14 30) stored))
           ;; The default property owns its pair, rather than returning the
           ;; vector/list originally passed by the caller.
           (setf (aref requested 0) 45)
           (is (equal '(14 30) (px.freetype:size font)))
           (is (> (px.rect:height normal) (px.rect:height scalar)))
           (is (not (equalp normal scalar)))
           (setf (first stored) 99)
           (is (equal '(14 30) (px.freetype:size font)))
           (let ((setf-value (setf (px.freetype:size font) #(20 28))))
             (is (equal '(20 28) setf-value))
             (setf (second setf-value) 3)
             (is (equal '(20 28) (px.freetype:size font))))
           (signals error (setf (px.freetype:size font) #(0 24)))
           (signals type-error (setf (px.freetype:size font) (list (expt 2 40) 24)))
           (is (equal '(20 28) (px.freetype:size font))))
      (px:dispose font))))

(test freetype-two-axis-size-is-used-by-all-raster-paths-and-overrides-stay-scoped
  (let ((font (px.freetype:make-font nil '(13 27)))
        (target (make-array '(100 70) :element-type '(unsigned-byte 8) :initial-element 0))
        (surface (px.surface:make-surface '(100 70) :alpha t)))
    (unwind-protect
         (progn
           (multiple-value-bind (mask dimensions)
               (px.freetype:render-raw font "Axis")
             (is (plusp (length mask)))
             (is (plusp (second dimensions))))
           (is (= 1 (length (px.freetype:get-metrics font "A" :size '(21 33)))))
           (is (plusp (px.freetype:get-sized-height font '(21 33))))
           (is (plusp (px.freetype:get-sized-ascender font '(21 33))))
           (is (minusp (px.freetype:get-sized-descender font '(21 33))))
           (multiple-value-bind (rendered rendered-bounds)
               (px.freetype:render font "Axis" '(255 255 255) nil :size '(21 33))
             (unwind-protect
                  (progn
                    (is (plusp (px.surface:height rendered)))
                    (is (plusp (px.rect:height rendered-bounds))))
               (px:dispose rendered)))
           (is (typep (px.freetype:render-to font surface '(2 3) "Axis"
                                              '(255 255 255) nil :size '(21 33))
                      'pixelisp:rect))
           (let ((default-bounds (px.freetype:get-rect font "Axis"))
                 (bounds (px.freetype:get-rect font "Axis" :size #(25 16))))
             (is (equalp bounds
                         (px.freetype:render-raw-to font target "Axis" :size #(25 16))))
             (is (not (equalp bounds default-bounds)))
             (is (equalp default-bounds (px.freetype:get-rect font "Axis"))))
           (is (equal '(13 27) (px.freetype:size font)))
           (setf (px.freetype:vertical font) t
                 (px.freetype:strong font) t)
           ;; Strong strength follows the vertical ppem. Rotation and vertical
           ;; layout still enter the same sized layout/raster pipeline.
           (is (plusp (px.rect:height (px.freetype:get-rect font "AB" :rotation 15))))
           (multiple-value-bind (mask dimensions)
               (px.freetype:render-raw font "AB" :size '(18 31))
             (is (= (length mask) (* (first dimensions) (second dimensions)))))
           (is (equal '(13 27) (px.freetype:size font))))
      (px:dispose surface)
      (px:dispose font))))

(test freetype-two-axis-bitmap-sizes-validate-without-changing-the-default
  (let ((font (px.freetype:make-font
               (asdf:system-relative-pathname "pixelisp/tests" "tests/fixtures/tiny-mono.bdf") 8))
        (target (make-array '(20 20) :element-type '(unsigned-byte 8) :initial-element 37)))
    (unwind-protect
         (progn
           (signals error (setf (px.freetype:size font) '(7 12)))
           (signals error (px.freetype:render-raw-to font target "A" :size '(7 12)))
           (is (loop for index below (array-total-size target)
                     always (= 37 (row-major-aref target index))))
           (is (= 8 (px.freetype:size font)))
           (let ((default-bounds (px.freetype:get-rect font "A")))
             (is (plusp (px.rect:height (px.freetype:get-rect font "A" :size '(8 0)))))
             (is (equalp default-bounds (px.freetype:get-rect font "A"))))
           (is (= 8 (px.freetype:size font))))
      (px:dispose font))))

(test freetype-size-property-checks-font-lifetime
  (let ((font (px.freetype:make-font nil 18)))
    (px:dispose font)
    (signals px:disposed-resource (px.freetype:size font))
    (signals px:disposed-resource (setf (px.freetype:size font) '(18 24)))))
