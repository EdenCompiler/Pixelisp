(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test freetype-face-information-and-scaling
  (px:with-resource (font (px.freetype:make-font nil 20))
    (is (px.freetype:scalable-p font))
    (is-false (px.freetype:fixed-width-p font))
    (is (= 0 (px.freetype:fixed-sizes font)))
    (is (null (px.freetype:get-sizes font)))
    ;; These are design units, so selecting another render size cannot change
    ;; them. Pixel metrics, however, must grow when we double the requested size.
    (let ((units (list (px.freetype:height font) (px.freetype:ascender font)
                       (px.freetype:descender font)))
          (small (px.freetype:get-sized-glyph-height font 12)))
      (is (< small (px.freetype:get-sized-glyph-height font 24)))
      (is (= 20 (px.freetype:size font)))
      (is (plusp (first units)))
      (is (plusp (second units)))
      (is (minusp (third units)))
      (is (equal units (list (px.freetype:height font) (px.freetype:ascender font)
                             (px.freetype:descender font))))))
  (signals type-error (px.freetype:get-sizes (px:make-rect 0 0 1 1)))
  (let ((font (px.freetype:make-font)))
    (px:dispose font)
    (dolist (query (list #'px.freetype:fixed-width-p #'px.freetype:scalable-p
                         #'px.freetype:fixed-sizes #'px.freetype:height
                         #'px.freetype:ascender #'px.freetype:descender
                         #'px.freetype:get-sizes #'px.freetype:get-sized-glyph-height))
      (signals px:disposed-resource (funcall query font)))))

(test freetype-bitmap-strike-information-is-copied
  ;; A tiny, authored BDF makes this test independent of installed system fonts.
  (let ((path (asdf:system-relative-pathname "pixelisp/tests" "tests/fixtures/tiny-mono.bdf")))
    (px:with-resource (font (px.freetype:make-font path 8))
      (is-false (px.freetype:scalable-p font))
      (is (px.freetype:fixed-width-p font))
      (is (= 1 (px.freetype:fixed-sizes font)))
      (let ((records (px.freetype:get-sizes font)))
        (is (equalp '((8 8 5 8.0d0 8.0d0)) records))
        (setf (caar records) 99)
        (is (= 8 (caar (px.freetype:get-sizes font)))))
      (is (some #'plusp (px.freetype:render-raw font "A"))))))
