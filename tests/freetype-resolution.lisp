;;;; Direct FreeType point sizes, per-font DPI, and module defaults.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defun %resolution-font-bytes ()
  (let* ((path (asdf:system-relative-pathname "pixelisp" "assets/fonts/DejaVuSans.ttf"))
         (bytes (make-array (with-open-file (stream path :direction :input
                                                        :element-type '(unsigned-byte 8))
                              (file-length stream))
                            :element-type '(unsigned-byte 8))))
    (with-open-file (stream path :direction :input :element-type '(unsigned-byte 8))
      (read-sequence bytes stream))
    bytes))

(test freetype-resolution-scales-point-sizes-and-snapshots-module-default
  (let ((original (px.freetype:get-default-resolution))
        (at-72 nil) (at-144 nil) (memory-font nil))
    (unwind-protect
         (progn
           (is (= 72 (px.freetype:set-default-resolution 0)))
           (setf at-72 (px.freetype:make-font nil 16))
           (is (= 72 (px.freetype:resolution at-72)))
           (let ((height-72 (px.freetype:get-sized-glyph-height at-72)))
             (px.freetype:set-default-resolution 144)
             (setf at-144 (px.freetype:make-font nil 16))
             (is (= 144 (px.freetype:resolution at-144)))
             (is (> (px.freetype:get-sized-glyph-height at-144)
                    (* 1.8 height-72)))
             ;; Updating module defaults does not alter existing font DPI.
             (px.freetype:set-default-resolution 72)
             (is (= 144 (px.freetype:resolution at-144)))
             (is (= height-72 (px.freetype:get-sized-glyph-height at-72))))
           ;; Resolution can be selected independently for an in-memory face.
           (setf memory-font (px.freetype:load-font-bytes (%resolution-font-bytes)
                                                          16 :resolution 144))
           (is (= 144 (px.freetype:resolution memory-font)))
           (is (= 16 (px.freetype:size memory-font))))
      (when memory-font (px:dispose memory-font))
      (when at-144 (px:dispose at-144))
      (when at-72 (px:dispose at-72))
      (px.freetype:set-default-resolution original))))

(test freetype-resolution-preserves-fractional-and-independent-axes
  (px:with-resource (font (px.freetype:make-font nil '(20.25d0 10.5d0)
                                                  :resolution 144))
    (is (equal '(20.25d0 10.5d0) (px.freetype:size font)))
    (let* ((pair-rect (px.freetype:get-rect font "Pixel"))
           (square-rect (px.freetype:get-rect font "Pixel" :size 20.25d0))
           (override-rect (px.freetype:get-rect font "Pixel" :size '(10 10))))
      (is (> (px.rect:height square-rect) (px.rect:height pair-rect)))
      (is (< (px.rect:width override-rect) (px.rect:width square-rect)))
      (is (equal '(20.25d0 10.5d0) (px.freetype:size font)))
      ;; 1/64-point fixed precision retains non-integral sizes.
      (setf (px.freetype:size font) 10.25d0)
      (is (= 10.25d0 (px.freetype:size font))))))

(test freetype-resolution-validates-before-opening-and-bitmap-strikes-stay-bounded
  (let ((resource-count (length pixelisp.internal:*resources*))
        (bitmap (asdf:system-relative-pathname "pixelisp" "tests/fixtures/tiny-mono.bdf")))
    (signals type-error (px.freetype:make-font nil 16 :resolution -1))
    (is (= resource-count (length pixelisp.internal:*resources*)))
    (px:with-resource (font (px.freetype:make-font bitmap 8 :resolution 72))
      (is (= 72 (px.freetype:resolution font)))
      (signals error (setf (px.freetype:size font) 7)))
    ;; The same strike requires half as many points at twice the DPI. A
    ;; nominal point-size match alone must not select an unavailable strike.
    (px:with-resource (font (px.freetype:make-font bitmap 4 :resolution 144))
      (is (= 8 (px.freetype:get-sized-height font)))
      (let ((before (px.freetype:get-rect font "A")))
        (signals error (setf (px.freetype:size font) 8))
        (is (= 4 (px.freetype:size font)))
        (is (equalp before (px.freetype:get-rect font "A")))))
    (signals error (px.freetype:make-font bitmap 8 :resolution 144))
    (is (= resource-count (length pixelisp.internal:*resources*)))))

(test freetype-equal-pixel-sizes-share-styles-raster-and-metrics
  (px:with-resource (font (px.freetype:make-font nil '(12 9) :resolution 144))
    (px:with-resource (reference (px.freetype:make-font nil '(24 18) :resolution 72))
      (dolist (style (list px.freetype:style-normal px.freetype:style-strong
                          px.freetype:style-underline px.freetype:style-oblique
                          px.freetype:style-wide))
        (is (equalp (px.freetype:get-metrics font "Ag")
                    (px.freetype:get-metrics reference "Ag")))
        (multiple-value-bind (raw dimensions) (px.freetype:render-raw font "Ag" :style style)
          (multiple-value-bind (other other-dimensions)
              (px.freetype:render-raw reference "Ag" :style style)
            (is (equal dimensions other-dimensions))
            (is (equalp raw other)))))
      (is (= (px.freetype:get-sized-height font '(7 11))
             (px.freetype:get-sized-height reference '(14 22))))
      (is (equal '(12 9) (px.freetype:size font))))))

(test freetype-resolution-default-validation-and-lifetime
  (let ((original (px.freetype:get-default-resolution)))
    (unwind-protect
         (progn
           (px.freetype:init :resolution 96)
           (is (= 96 (px.freetype:get-default-resolution)))
           (dolist (bad '(-1 1.5 "144" 4294967296))
             (signals type-error (px.freetype:set-default-resolution bad))
             (signals type-error (px.freetype:make-font nil 16 :resolution bad)))
           (is (= 96 (px.freetype:get-default-resolution)))
           (let ((font (px.freetype:font nil 12 :resolution 0)))
             (is (= 96 (px.freetype:resolution font)))
             (px:dispose font)
             (signals px:disposed-resource (px.freetype:resolution font)))
           (signals type-error (px.freetype:resolution :not-a-font)))
      (px.freetype:set-default-resolution original))))
