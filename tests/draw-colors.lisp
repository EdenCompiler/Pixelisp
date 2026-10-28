;;;; Mapped colors belong to their destination format, not to Color's RRGGBBAA
;;;; notation. Check raw pixels as well as decoded colors: duplicate palette
;;;; entries and unused storage bits would hide a decode/remap regression.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defun mapped-draw-operations ()
  "Small examples of every public drawing primitive."
  (list (lambda (s c) (px.draw:rect s c '(1 1 10 9) :border-radius 2))
        (lambda (s c) (px.draw:line s c '(1 1) '(10 9)))
        (lambda (s c) (px.draw:lines s c t '((1 1) (10 2) (5 10))))
        (lambda (s c) (px.draw:aaline s c '(1 2) '(10 7)))
        (lambda (s c) (px.draw:aalines s c t '((1 1) (10 2) (5 10))))
        (lambda (s c) (px.draw:circle s c '(6 6) 4))
        (lambda (s c) (px.draw:ellipse s c '(1 2 10 8) :width 2))
        (lambda (s c) (px.draw:polygon s c '((1 1) (10 2) (5 10))))
        (lambda (s c) (px.draw:arc s c '(1 1 10 10) 0 pi))))

(defun mapped-draw-pixels (surface)
  (loop for y below (px.surface:height surface) append
    (loop for x below (px.surface:width surface)
          collect (px.surface:get-at-mapped surface (list x y)))))

(test drawing-mapped-colors-across-native-formats
  (dolist (depth '(8 12 15 16 24 32))
    (with-graphics-surfaces
        ((packed (px.surface:make-surface '(12 12) :depth depth :alpha (= depth 32)))
         (channels (px.surface:make-surface '(12 12) :depth depth :alpha (= depth 32))))
      (let* ((pixel (px.surface:map-rgb packed '(200 120 70 170)))
             (color (px.surface:unmap-rgb packed pixel)))
        (dolist (draw (mapped-draw-operations))
          (px.surface:fill packed '(10 20 30 40))
          (px.surface:fill channels '(10 20 30 40))
          (px.surface:set-clip packed '(2 2 8 8))
          (px.surface:set-clip channels '(2 2 8 8))
          (let ((damage (funcall draw packed pixel))
                (other-damage (funcall draw channels color)))
            (is (equal (list (px.rect:top-left damage) (px.rect:size damage))
                       (list (px.rect:top-left other-damage) (px.rect:size other-damage)))))
          (is (equal (mapped-draw-pixels packed) (mapped-draw-pixels channels)))
          (is-false (px.surface:locked-p packed))
          (px.surface:set-clip packed)
          (px.surface:set-clip channels))))))

(test drawing-retains-exact-index-and-unused-bits
  (with-graphics-surfaces ((indexed (px.surface:make-surface '(12 12) :depth 8)))
    (px.surface:set-palette indexed (make-list 256 :initial-element '(0 0 0)))
    (px.surface:set-palette-at indexed 5 '(255 0 0))
    (px.surface:set-palette-at indexed 7 '(255 0 0))
    (dolist (draw (mapped-draw-operations))
      (px.surface:fill indexed 0)
      (funcall draw indexed 7)
      (let ((pixels (mapped-draw-pixels indexed)))
        ;; Antialiasing may choose index 5 for partial coverage. Full samples
        ;; must still retain 7; a wholly decoded operation would never use it.
        (is (member 7 pixels)))))
  (with-graphics-surfaces
      ((surface (px.surface:make-surface '(12 12) :depth 32
                                         :masks '(#xff #xff00 #xff0000 0))))
    (dolist (draw (mapped-draw-operations))
      (px.surface:fill surface 0)
      (funcall draw surface #xa5123456)
      (is (member #xa5123456 (mapped-draw-pixels surface))))))

(test surface-packed-colors-clipping-and-blends
  (with-graphics-surfaces ((surface (px.surface:make-surface '(4 3) :alpha t)))
    (let ((pixel (px.surface:map-rgb surface '(100 150 200 255))))
      (px.surface:fill surface pixel)
      (is (every (lambda (p) (= pixel p)) (mapped-draw-pixels surface)))
      (px.surface:set-clip surface '(1 1 2 1))
      (px.surface:set-at surface '(0 0) 0)
      (is (= pixel (px.surface:get-at-mapped surface '(0 0))))
      (px.surface:set-at surface '(1 1) -1)
      (is (= #xffffffff (px.surface:get-at-mapped surface '(1 1))))
      (px.surface:fill surface (px.surface:map-rgb surface '(10 20 30 40))
                       nil :special-flags :blend-rgba-sub)
      (is (equal '(245 235 225 215) (graphics-rgba surface '(1 1))))
      (is (equal '(90 130 170 215) (graphics-rgba surface '(2 1))))
      (is (= pixel (px.surface:get-at-mapped surface '(0 0)))))))

(test mapped-colors-validate-before-mutation-and-unlock
  (with-graphics-surfaces ((surface (px.surface:make-surface '(12 12) :depth 8)))
    (px.surface:fill surface 9)
    (dolist (invalid '(-1 256 4294967296))
      (dolist (draw (mapped-draw-operations))
        (signals type-error (funcall draw surface invalid))
        (is-false (px.surface:locked-p surface)))
      (signals type-error (px.surface:fill surface invalid))
      (signals type-error (px.surface:set-at surface '(0 0) invalid))
      (is (every (lambda (p) (= p 9)) (mapped-draw-pixels surface))))))

(test mapped-colors-work-in-subviews-and-gfxdraw
  (with-graphics-surfaces ((parent (px.surface:make-surface '(8 8) :depth 16)))
    (px.surface:fill parent 0)
    (pixelisp:with-resource (child (px.surface:subsurface parent '(2 3 4 3)))
      (let ((pixel (px.surface:map-rgb child '(255 100 0))))
        (px.gfxdraw:box child 1 0 2 1 pixel)
        (is (= pixel (px.surface:get-at-mapped parent '(3 3))))
        (is (= 0 (px.surface:get-at-mapped parent '(2 3))))
        (is (= 0 (px.surface:get-at-mapped parent '(3 5))))))
    (is-false (px.surface:locked-p parent))))
