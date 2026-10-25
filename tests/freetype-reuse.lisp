(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test freetype-nil-text-reuses-an-owned-successful-layout
  (let ((font (px.freetype:make-font nil 22))
        (target (px.surface:make-surface '(90 50) :alpha t)))
    (unwind-protect
         (progn
           ;; pygame starts with an empty string: first NIL is a valid blank.
           (is (plusp (px.rect:height (px.freetype:get-rect font nil))))
           ;; Metrics leave the current retained layout unchanged.
           (px.freetype:get-metrics font "metric only")
           (is (equalp (px.freetype:get-rect font nil)
                       (px.freetype:get-rect font "")))
           (let* ((mutable (copy-seq "Reuse me"))
                  (bounds (px.freetype:get-rect font mutable :size 22 :rotation 0))
                  (expected (px.freetype:render-raw font mutable :size 22)))
             (setf (char mutable 0) #\X)
             (is (equalp bounds (px.freetype:get-rect font nil :size 22 :rotation 0)))
             (is (equalp expected (px.freetype:render-raw font nil :size 22)))
             ;; A later successful get-rect is the next retained string.
             (px.freetype:get-rect font "rotated" :size 29 :rotation 17
                                   :style px.freetype:style-oblique)
             (multiple-value-bind (expected expected-size)
                 (px.freetype:render-raw font "rotated" :size 29 :rotation 17
                                         :style px.freetype:style-oblique)
               (multiple-value-bind (actual actual-size)
                   (px.freetype:render-raw font nil :size 29 :rotation 17
                                           :style px.freetype:style-oblique)
                 (is (equalp expected-size actual-size))
                 (is (equalp expected actual))))
             ;; Failed layout does not replace the last successfully retained text.
             (signals px:unsupported-feature
               (px.freetype:get-rect font "bad override" :rotation 90
                                     :style px.freetype:style-wide))
             (is (equalp (px.freetype:get-rect font nil :size 29 :rotation 17
                                              :style px.freetype:style-oblique)
                         (px.freetype:get-rect font "rotated" :size 29 :rotation 17
                                              :style px.freetype:style-oblique)))))
      (px:dispose target)
      (px:dispose font))))

(test freetype-nil-text-is-retained-by-rendering-entry-points
  (let ((font (px.freetype:make-font nil 20))
        (surface (px.surface:make-surface '(100 60) :alpha t))
        (array (make-array '(100 60) :element-type '(unsigned-byte 8) :initial-element 0)))
    (unwind-protect
         (progn
           (px:with-resource (rendered (px.freetype:render font "render source"))
             (is (plusp (px.surface:width rendered))))
           (is (equalp (px.freetype:get-rect font nil) (px.freetype:get-rect font "render source")))
           (px.freetype:get-rect font "render-to source")
           (px.freetype:render-to font surface '(2 3) nil)
           (is (equalp (px.freetype:get-rect font nil) (px.freetype:get-rect font "render-to source")))
           (px.freetype:render-raw font "raw source")
           (is (equalp (px.freetype:get-rect font nil) (px.freetype:get-rect font "raw source")))
           (px.freetype:render-raw-to font array "raw-to source")
           (is (equalp (px.freetype:get-rect font nil) (px.freetype:get-rect font "raw-to source")))
           ;; Failed target validation leaves the previously retained text intact.
           (signals error (px.freetype:render-raw-to font
                           (make-array '(4 4) :element-type 'bit) "failed"))
           (is (equalp (px.freetype:get-rect font nil)
                       (px.freetype:get-rect font "raw-to source")))
           ;; A live byte view remains writable with NIL text and retains normal clipping.
           (let ((view (px.surface:get-view surface "A")))
             (unwind-protect
                  (progn
                    (px.freetype:render-raw-to font view nil :dest '(-2 4))
                    (is (px.surface:locked-p surface)))
               (px.buffer:close view))))
      (px:dispose surface)
      (px:dispose font))))

(test freetype-bitmap-strike-control-default-validation-and-lifetime
  (let ((outline (px.freetype:make-font nil 20))
        (bitmap (px.freetype:make-font
                 (asdf:system-relative-pathname "pixelisp/tests" "tests/fixtures/tiny-mono.bdf") 8)))
    (unwind-protect
         (progn
           (is (px.freetype:use-bitmap-strikes outline))
           (let* ((load-char-symbol (find-symbol "LOAD-CHAR" "FREETYPE2"))
                  (original-load-char (symbol-function load-char-symbol))
                  (seen-flags nil))
             (unwind-protect
                  (progn
                    ;; Observe the native flags so this remains meaningful even
                    ;; without a system font that contains embedded strikes.
                    (setf (symbol-function load-char-symbol)
                          (lambda (&rest arguments)
                            (setf seen-flags (third arguments))
                            (apply original-load-char arguments)))
                    (setf (px.freetype:use-bitmap-strikes outline) nil)
                    (is-false (px.freetype:use-bitmap-strikes outline))
                    (px.freetype:render-raw outline "A")
                    (is (member :no-bitmap seen-flags))
                    (setf (px.freetype:use-bitmap-strikes outline) t)
                    (px.freetype:render-raw outline "A")
                    (is (not (member :no-bitmap seen-flags)))
                    ;; FT_LOAD_NO_BITMAP is only added for scalable faces.
                    (setf (px.freetype:use-bitmap-strikes bitmap) nil)
                    (px.freetype:render-raw bitmap "A")
                    (is (not (member :no-bitmap seen-flags)))
                    (signals type-error (setf (px.freetype:use-bitmap-strikes outline) :yes)))
               (setf (symbol-function load-char-symbol) original-load-char)))
           (px:dispose outline)
           (signals px:disposed-resource (px.freetype:use-bitmap-strikes outline))
           (signals px:disposed-resource (setf (px.freetype:use-bitmap-strikes outline) t)))
      (px:dispose outline)
      (px:dispose bitmap))))
