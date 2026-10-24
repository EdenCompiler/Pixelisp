;;;; Pygame-compatible arithmetic and the normalized I1I2I3 color property.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test color-arithmetic-is-saturated-channelwise-and-nonmutating
  (let* ((left (px:make-color 250 10 80 200))
         (right (px:make-color 20 30 40 100))
         (sum (px.color:add left right))
         (difference (px.color:subtract left right))
         (product (px.color:multiply left right)))
    (is (equal '(255 40 120 255) (px.color:to-list sum)))
    (is (equal '(230 0 40 100) (px.color:to-list difference)))
    (is (equal '(255 255 255 255) (px.color:to-list product)))
    (is (not (eq left sum)))
    (is (equal '(250 10 80 200) (px.color:to-list left)))
    (is (equal '(20 30 40 100) (px.color:to-list right))))
  (is (equal '(0 75 0 38)
             (px.color:to-list (px.color:floor-divide '(100 150 200 77) '(0 2 0 2)))))
  (is (equal '(0 50 0 17)
             (px.color:to-list (px.color:modulo '(100 150 200 77) '(0 100 0 60)))))
  (is (equal '(155 105 55 178)
             (px.color:to-list (px.color:invert '(100 150 200 77)))))
  ;; Ordinary parseable values work at the same boundary as Color operands.
  (let ((result (px.color:add "#01020304" '(1 2 3 4))))
    (is (equal '(2 4 6 8) (px.color:to-list result)))))

(test color-i1i2i3-getter-uses-normalized-ohta-components
  (is (equal '(1/3 1/2 -1/4) (px.color:i1i2i3 (px:make-color 255 0 0))))
  (is (equal '(1/3 0 1/2) (px.color:i1i2i3 (px:make-color 0 255 0))))
  (is (equal '(1/3 -1/2 -1/4) (px.color:i1i2i3 (px:make-color 0 0 255))))
  (is (equal '(1 0 0) (px.color:i1i2i3 (px:make-color 255 255 255 0))))
  (is (equal '(0 0 0) (px.color:i1i2i3 (px:make-color 0 0 0 255)))))

(test color-i1i2i3-setter-roundtrips-primary-colors-and-preserves-alpha
  (dolist (entry '(((1/3 1/2 -1/4) (255 0 0 73))
                   ((1/3 0 1/2) (0 255 0 73))
                   ((1/3 -1/2 -1/4) (0 0 255 73))))
    (let ((color (px:make-color 12 34 56 73)))
      (setf (px.color:i1i2i3 color) (first entry))
      (is (equal (second entry) (px.color:to-list color)))))
  (let ((color (px:make-color 100 150 200 87)))
    (setf (px.color:i1i2i3 color) (px.color:i1i2i3 color))
    (is (equal '(100 150 200 87) (px.color:to-list color)))))

(test color-i1i2i3-setter-validates-before-mutation
  (dolist (invalid '((1 0) (1 0 0 0) (1 0 "bad") (-0.01 0 0)
                     (1.01 0 0) (0 0.51 0) (0 0 -0.51)))
    (let ((color (px:make-color 10 20 30 40))
          (before '(10 20 30 40)))
      (signals error (setf (px.color:i1i2i3 color) invalid))
      (is (equal before (px.color:to-list color))))))
