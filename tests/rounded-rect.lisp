;;;; Per-corner rounded rectangles: focused CPU pixel and damage fixtures.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test rounded-rect-radii-inherit-and-square-one-corner
  (with-graphics-surfaces ((surface (px.surface:make-surface '(10 10) :alpha t)))
    (px.draw:rect surface '(255 0 0) '(1 1 8 8) :border-radius 3)
    (is (equal '(0 0 0 0) (graphics-rgba surface '(1 1))))
    (is (equal '(255 0 0 255) (graphics-rgba surface '(4 1))))
    (px.surface:fill surface '(0 0 0 0))
    (px.draw:rect surface '(0 255 0) '(1 1 8 8) :border-radius 3
                  :border-top-right-radius 0)
    (is (equal '(0 0 0 0) (graphics-rgba surface '(1 1))))
    (is (equal '(0 255 0 255) (graphics-rgba surface '(8 1))))))

(test rounded-rect-radii-scale-to-fit-and-outline-insets
  (with-graphics-surfaces ((surface (px.surface:make-surface '(12 10) :alpha t)))
    ;; Two radius-8 top corners are scaled to fit the ten-pixel-wide edge.
    (px.draw:rect surface '(255 0 0) '(1 1 10 8)
                  :border-top-left-radius 8 :border-top-right-radius 8)
    (is (equal '(0 0 0 0) (graphics-rgba surface '(1 1))))
    (is (equal '(255 0 0 255) (graphics-rgba surface '(6 2))))
    (px.surface:fill surface '(0 0 0 0))
    (px.draw:rect surface '(0 0 255) '(1 1 10 8) :width 2 :border-radius 4)
    (is (equal '(0 0 255 255) (graphics-rgba surface '(5 1))))
    (is (equal '(0 0 0 0) (graphics-rgba surface '(1 1))))
    (is (equal '(0 0 0 0) (graphics-rgba surface '(5 4))))
    ;; Oversized inward outlines consume the interior while staying in bounds.
    (px.surface:fill surface '(0 0 0 0))
    (px.draw:rect surface '(255 255 0) '(1 1 4 4) :width 20 :border-radius 2)
    (is (equal '(0 0 0 0) (graphics-rgba surface '(1 1))))
    (is (equal '(255 255 0 255) (graphics-rgba surface '(2 2))))))

(test rounded-rect-clipping-empty-and-negative-width
  (with-graphics-surfaces ((surface (px.surface:make-surface '(8 8) :alpha t)))
    (px.surface:set-clip surface '(2 2 3 3))
    (let ((damage (px.draw:rect surface '(255 0 0) '(0 0 8 8)
                                :border-radius 3 :border-bottom-right-radius 0)))
      (is (= 2 (px:rect-x damage)))
      (is (= 2 (px:rect-y damage)))
      (is (= 3 (px:rect-width damage)))
      (is (= 3 (px:rect-height damage))))
    (px.surface:fill surface '(0 0 0 0))
    (let ((damage (px.draw:rect surface '(255 0 0) '(3 3 0 4)
                                :border-top-left-radius 100)))
      (is (= 0 (px:rect-width damage)))
      (is (= 0 (px:rect-height damage))))
    (let ((damage (px.draw:rect surface '(255 0 0) '(0 0 8 8) :width -1)))
      (is (= 0 (px:rect-width damage)))
      (is (= 0 (px:rect-height damage))))
    (is (equal '(0 0 0 0) (graphics-rgba surface '(2 2))))
    (px.surface:set-clip surface nil)
    (signals error
      (px.draw:rect surface '(255 0 0) '(1 1 5 5) :border-top-left-radius 'invalid))
    (is (equal '(0 0 0 0) (graphics-rgba surface '(1 1))))))
