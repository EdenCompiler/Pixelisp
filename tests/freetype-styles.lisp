(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test freetype-style-flags-validate-and-style-overrides-are-scoped
  (let ((font (px.freetype:make-font nil 22)))
    (unwind-protect
         (multiple-value-bind (normal-mask normal-size)
             (px.freetype:render-raw font "Style" :style px.freetype:style-normal)
           (is (= px.freetype:style-normal (px.freetype:style font)))
           (setf (px.freetype:underline font) t
                 (px.freetype:wide font) t)
           (is (px.freetype:underline font))
           (is (px.freetype:wide font))
           (setf (px.freetype:style font) px.freetype:style-default)
           (is (equalp (logior px.freetype:style-underline px.freetype:style-wide)
                       (px.freetype:style font)))
           (signals error (setf (px.freetype:style font) 16))
           (signals error (setf (px.freetype:strength font) -1))
           (setf (px.freetype:strength font) 0)
           (is (= 0 (px.freetype:strength font)))
           (setf (px.freetype:strength font) (/ 1.0 36))
           (signals error (setf (px.freetype:underline-adjustment font) 3))
           (multiple-value-bind (override-mask override-size)
               (px.freetype:render-raw font "Style" :style px.freetype:style-normal)
             (is (equalp normal-mask override-mask))
             (is (equalp normal-size override-size)))
           (is (px.freetype:underline font))
           (is (px.freetype:wide font)))
      (px:dispose font))))

(test freetype-outline-styles-change-pixels-and-report-render-bounds
  (let ((font (px.freetype:make-font nil 24))
        (target (px.surface:make-surface '(120 70) :alpha t)))
    (unwind-protect
         (multiple-value-bind (normal normal-size)
             (px.freetype:render-raw font "Ag" :style px.freetype:style-normal)
           (setf (px.freetype:style font)
                 (logior px.freetype:style-underline px.freetype:style-wide))
           (dolist (flag (list px.freetype:style-oblique px.freetype:style-strong px.freetype:style-wide))
             (multiple-value-bind (styled styled-size)
                 (px.freetype:render-raw font "Ag" :style flag)
               (is (not (and (equalp normal-size styled-size) (equalp normal styled))))))
           (let* ((flags (logior px.freetype:style-underline px.freetype:style-wide))
                  (bounds (px.freetype:get-rect font "Ag" :style flags))
                  (raw-target (make-array '(120 70) :element-type '(unsigned-byte 8) :initial-element 0))
                  (raw-bounds (px.freetype:render-raw-to font raw-target "Ag" :dest '(4 5) :style flags)))
             (is (equalp bounds raw-bounds))
             (multiple-value-bind (rendered rendered-bounds)
                 (px.freetype:render font "Ag" '(255 255 255) nil :style flags)
               (unwind-protect
                    (progn
                      (is (equalp bounds rendered-bounds))
                      (is (= (px.rect:width bounds) (px.surface:width rendered)))
                      (is (= (px.rect:height bounds) (px.surface:height rendered))))
                 (px:dispose rendered)))
             (is (typep (px.freetype:render-to font target '(4 5) "Ag" '(255 255 255) nil :style flags)
                        'pixelisp:rect))
             (is (some #'plusp (loop for x below 120 append
                                 (loop for y below 70 collect (aref raw-target x y)))))
             (is (= flags (px.freetype:style font)))))
      (px:dispose target)
      (px:dispose font))))

(test freetype-bitmap-fonts-reject-outline-synthesis-before-changing-style
  (let ((font (px.freetype:make-font
               (asdf:system-relative-pathname "pixelisp/tests" "tests/fixtures/tiny-mono.bdf") 8)))
    (unwind-protect
         (progn
           (signals px:unsupported-feature
             (setf (px.freetype:style font) px.freetype:style-strong))
           (is (= px.freetype:style-normal (px.freetype:style font)))
           (signals px:unsupported-feature
             (setf (px.freetype:style font) px.freetype:style-wide))
           (signals px:unsupported-feature (setf (px.freetype:strength font) 0.1))
           (signals px:unsupported-feature
             (px.freetype:render-raw font "" :style px.freetype:style-oblique))
           (is (= px.freetype:style-normal (px.freetype:style font))))
      (px:dispose font))))

(test freetype-style-properties-check-font-lifetime
  (let ((font (px.freetype:make-font nil 18)))
    (px:dispose font)
    (signals px:disposed-resource (setf (px.freetype:underline-adjustment font) 0.5))
    (signals px:disposed-resource (px.freetype:style font))))

(test freetype-render-releases-a-partially-painted-surface
  (px:with-resource (font (px.freetype:make-font nil 18))
    (let ((before (length pixelisp.internal:*resources*)))
      (signals error (px.freetype:render font "A" '(:invalid-color)))
      (is (= before (length pixelisp.internal:*resources*))))))
