;;;; Padding changes a text cell, never its baseline-relative glyph pixels.
;;;; Default colors are font-owned values; raw alpha masks stay independent of
;;;; those display choices so they remain useful for collision and image work.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defun %padded-baseline-ink (font text &key size)
  (let ((bounds (px.freetype:get-rect font text :size size)))
    (multiple-value-bind (bytes dimensions) (px.freetype:render-raw font text :size size)
      (loop for y below (second dimensions) append
        (loop for x below (first dimensions)
              for alpha = (aref bytes (+ x (* y (first dimensions))))
              when (plusp alpha) collect
                (list (+ x (px.rect:x bounds)) (+ y (px.rect:y bounds)) alpha))))))

(test freetype-padding-inflates-cells-and-preserves-baseline-ink
  (dolist (dpi '(72 144))
    (px:with-resource (font (px.freetype:make-font nil 24 :resolution dpi))
      (is-false (px.freetype:pad font))
      (dolist (vertical '(nil t))
        (setf (px.freetype:vertical font) vertical)
        (dolist (text '("A" "g" "Ag" " "))
          (setf (px.freetype:pad font) nil)
          (let ((ink (%padded-baseline-ink font text))
                (plain (px.freetype:get-rect font text)))
            (setf (px.freetype:pad font) t)
            (let ((padded (px.freetype:get-rect font text)))
              (is (px.rect:contains padded plain))
              (is (equal ink (%padded-baseline-ink font text)))
              (if vertical
                  (is (> (px.rect:width padded) (px.rect:width plain)))
                  (is (= (px.rect:height padded)
                         (px.freetype:get-sized-glyph-height font)))))))
        ;; Per-call sizes select their own native metrics and do not overwrite
        ;; the default point size stored in the font.
        (let ((plain (%padded-baseline-ink font "Ag" :size 12)))
          (setf (px.freetype:pad font) nil)
          (is (equal plain (%padded-baseline-ink font "Ag" :size 12)))
          (is (= 24 (px.freetype:size font))))))))

(test freetype-padding-origin-and-raw-targets-share-coordinates
  (px:with-resource (font (px.freetype:make-font nil 18))
    (px.surface:with-surface (target '(100 80) :alpha t)
      (setf (px.freetype:pad font) t (px.freetype:origin font) t)
      (let ((array (make-array '(100 80) :element-type '(unsigned-byte 8) :initial-element 0))
            (bounds (px.freetype:get-rect font "Ag")))
        (let ((painted (px.freetype:render-to font target '(30 40) "Ag" "white")))
          (is (= (+ 30 (px.rect:x bounds)) (px.rect:x painted)))
          (is (= (+ 40 (px.rect:y bounds)) (px.rect:y painted))))
        (is (equalp bounds (px.freetype:render-raw-to font array "Ag" :dest '(30 40))))
        (is (equalp array (px.surfarray:array-alpha target)))))))

(test freetype-default-colors-are-copied-and-overrides-stay-scoped
  (px:with-resource (font (px.freetype:make-font nil 20))
    (is (equal '(255 255 255 255) (px.color:to-list (px.freetype:fgcolor font))))
    (is (null (px.freetype:bgcolor font)))
    (let* ((requested (px:make-color 200 30 40))
           (returned (setf (px.freetype:fgcolor font) requested)))
      (setf (px:color-r requested) 9 (px:color-g returned) 8)
      (let ((copy (px.freetype:fgcolor font))) (setf (px:color-b copy) 7))
      (is (equal '(200 30 40 255) (px.color:to-list (px.freetype:fgcolor font)))))
    (let* ((requested (px:make-color 10 20 30))
           (returned (setf (px.freetype:bgcolor font) requested)))
      (setf (px:color-r requested) 9 (px:color-g returned) 8)
      (is (equal '(10 20 30 255) (px.color:to-list (px.freetype:bgcolor font)))))
    (setf (px.freetype:pad font) t)
    (px:with-resource (surface (px.freetype:render font "A"))
      (is (equal '(10 20 30 255) (graphics-rgba surface '(0 0))))
      (is (loop for y below (px.surface:height surface) thereis
            (loop for x below (px.surface:width surface)
                  thereis (equal '(200 30 40 255) (graphics-rgba surface (list x y)))))))
    ;; An explicit NIL background means transparency in Lisp, even when the
    ;; font has a saved background. The default properties themselves stay put.
    (px:with-resource (surface (px.freetype:render font "A" "blue" nil))
      (is (zerop (px:color-a (px.surface:get-at surface '(0 0))))))
    (is (equal '(200 30 40 255) (px.color:to-list (px.freetype:fgcolor font))))
    (is (equal '(10 20 30 255) (px.color:to-list (px.freetype:bgcolor font))))
    (let ((raw (px.freetype:render-raw font "A")))
      (setf (px.freetype:fgcolor font) '(3 4 5 10)
            (px.freetype:bgcolor font) '(90 80 70 255))
      (is (equalp raw (px.freetype:render-raw font "A"))))
    (setf (px.freetype:bgcolor font) nil)
    (is (null (px.freetype:bgcolor font)))))

(test freetype-padding-restrictions-and-property-validation
  (let ((font (px.freetype:make-font nil 20)))
    (unwind-protect
         (progn
           (setf (px.freetype:pad font) t)
           (signals type-error (setf (px.freetype:pad font) :yes))
           (is (px.freetype:pad font))
           (signals px:unsupported-feature (px.freetype:get-rect font "A" :rotation 90))
           (let ((target (make-array '(40 40) :element-type '(unsigned-byte 8) :initial-element 37)))
             (signals px:unsupported-feature
               (px.freetype:render-raw-to font target "A" :rotation 45))
             (is (loop for index below (array-total-size target)
                       always (= 37 (row-major-aref target index)))))
           (signals error (setf (px.freetype:fgcolor font) nil))
           (signals error (setf (px.freetype:bgcolor font) '(256 0 0)))
           (is (null (px.freetype:bgcolor font))))
      (px:dispose font))
    (signals px:disposed-resource (px.freetype:pad font))
    (signals px:disposed-resource (setf (px.freetype:pad font) nil))
    (signals px:disposed-resource (px.freetype:fgcolor font))
    (signals px:disposed-resource (setf (px.freetype:bgcolor font) nil))))
