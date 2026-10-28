;;;; One-dimensional PixelArray selections, metadata, and pixel operations.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test pixelarray-row-and-column-views-share-the-surface
  (px.surface:with-surface (surface '(4 3))
    (px.pixelarray:with-pixel-array (pixels surface)
      (px.buffer:with-view (last-row (px.pixelarray:row pixels -1))
        (px.buffer:with-view (middle-column (px.pixelarray:column pixels 1))
          (is (= 1 (px.pixelarray:ndim last-row)))
          (is (equal '(4) (px.pixelarray:shape last-row)))
          (is (equal '(4) (px.pixelarray:strides last-row)))
          (is (equal '(3) (px.pixelarray:shape middle-column)))
          (is (equal '(16) (px.pixelarray:strides middle-column)))
          (px.buffer:with-view (row-transpose (px.pixelarray:transpose last-row))
            (is (equal '(1 4) (px.pixelarray:shape row-transpose)))
            (is (equal '(16 4) (px.pixelarray:strides row-transpose))))
          (px.buffer:with-view (column-transpose (px.pixelarray:transpose middle-column))
            (is (equal '(1 3) (px.pixelarray:shape column-transpose)))
            (is (equal '(12 16) (px.pixelarray:strides column-transpose))))
          (setf (px.pixelarray:ref last-row 2) #x123456)
          (is (= #x123456 (px.pixelarray:ref pixels 2 2)))
          (setf (px.pixelarray:ref middle-column 0) #xabcdef)
          (is (= #xabcdef (px.pixelarray:ref pixels 1 0)))
          (is (eq surface (px.pixelarray:surface last-row))))))))

(test pixelarray-negative-and-invalid-line-selectors
  (px.surface:with-surface (surface '(3 2))
    (px.pixelarray:with-pixel-array (pixels surface)
      (px.buffer:with-view (first-row (px.pixelarray:row pixels -2))
        (is (equal '(3) (px.pixelarray:shape first-row))))
      (px.buffer:with-view (last-column (px.pixelarray:column pixels -1))
        (is (equal '(2) (px.pixelarray:shape last-column))))
      (signals error (px.pixelarray:row pixels -3))
      (signals error (px.pixelarray:row pixels 2))
      (signals error (px.pixelarray:column pixels 3))
      (signals type-error (px.pixelarray:column pixels 1.5))
      (px.buffer:with-view (line (px.pixelarray:row pixels 0))
        (signals error (px.pixelarray:row line 0))))))

(test pixelarray-line-slice-reverse-transpose-and-copy
  (px.surface:with-surface (surface '(3 2) :depth 16)
    (px.pixelarray:with-pixel-array (pixels surface)
      (px.buffer:with-view (line (px.pixelarray:row pixels 1))
        (setf (px.pixelarray:ref line 0) #x1234
              (px.pixelarray:ref line 1) #x2345
              (px.pixelarray:ref line 2) #x3456)
        (px.buffer:with-view (reverse-line (px.buffer:slice line '(2) '(3) '(-1)))
          (is (equal '(3) (px.pixelarray:shape reverse-line)))
          (is (equal '(-2) (px.pixelarray:strides reverse-line)))
          (is (= #x3456 (px.pixelarray:ref reverse-line 0))))
        (px.buffer:with-view (transposed (px.pixelarray:transpose line))
          (is (equal '(1 3) (px.pixelarray:shape transposed)))
          (is (equal '(6 2) (px.pixelarray:strides transposed)))
          (is (= #x2345 (px.pixelarray:ref transposed 0 1))))
        (px.buffer:with-view (reverse-line
                               (px.buffer:slice line '(2) '(3) '(-1)))
          (px.buffer:with-view (transposed (px.pixelarray:transpose reverse-line))
            (is (equal '(6 -2) (px.pixelarray:strides transposed)))))
        (px.buffer:with-view (empty-line (px.buffer:slice line '(0) '(0)))
          (px.buffer:with-view (empty-transpose (px.pixelarray:transpose empty-line))
            (is (equal '(1 0) (px.pixelarray:shape empty-transpose)))
            (is (equal '(0 2) (px.pixelarray:strides empty-transpose)))))
        (px:with-resource (copy (px.pixelarray:make-surface line))
          (is (equal '(3 1) (px.surface:size copy)))
          (is (= 16 (px.surface:get-bitsize copy)))
          (is (= #x1234 (px.surface:get-at-mapped copy '(0 0))))
          (is (= #x3456 (px.surface:get-at-mapped copy '(2 0)))))))))

(test pixelarray-line-color-methods-preserve-rank
  (px.surface:with-surface (surface '(3 2) :alpha t)
    (px.pixelarray:with-pixel-array (pixels surface)
      (px.buffer:with-view (first-row (px.pixelarray:row pixels 0))
        (px.buffer:with-view (second-row (px.pixelarray:row pixels 1))
          (setf (px.pixelarray:ref first-row 0) "red"
                (px.pixelarray:ref first-row 1) "blue"
                (px.pixelarray:ref first-row 2) "red"
                (px.pixelarray:ref second-row 0) "red"
                (px.pixelarray:ref second-row 1) "red"
                (px.pixelarray:ref second-row 2) "blue")
          (is (equal '(3) (array-dimensions (px.pixelarray:extract first-row "red"))))
          (is (equalp #*101 (px.pixelarray:extract first-row "red")))
          (is (equal '(3) (array-dimensions (px.pixelarray:compare first-row second-row))))
          (is (equalp #*100 (px.pixelarray:compare first-row second-row)))
          (signals error (px.pixelarray:compare first-row pixels))
          (px.pixelarray:replace first-row "red" "green")
          (is (equal '(0 255 0 255)
                     (px.color:to-list (px.surface:get-at surface '(0 0))))))))))

(test pixelarray-line-assignment-broadcast-overlap-and-atomicity
  (px.surface:with-surface (surface '(3 2))
    (px.pixelarray:with-pixel-array (pixels surface)
      (px.buffer:with-view (line (px.pixelarray:row pixels 0))
        (setf (px.pixelarray:ref line 0) 1
              (px.pixelarray:ref line 1) 2
              (px.pixelarray:ref line 2) 3)
        ;; A 1D source is treated as an Nx1 row and broadcast across rows.
        (px.pixelarray:assign pixels line)
        (is (equal '(1 2 3 1 2 3)
                   (loop for y below 2 append
                     (loop for x below 3 collect (px.pixelarray:ref pixels x y)))))
        (px.buffer:with-view (reverse-line
                               (px.buffer:slice line '(2) '(3) '(-1)))
          (px.pixelarray:assign line reverse-line))
        (is (equal '(3 2 1)
                   (loop for x below 3 collect (px.pixelarray:ref line x))))
        (let ((before (px.surfarray:array2d surface)))
          (signals error (px.pixelarray:assign line "not-a-single-color"))
          (is (equalp before (px.surfarray:array2d surface))))
        ;; A rank-two N-by-1 source can also fill a 1D row.
        (px.buffer:with-view (column-shaped
                               (px.buffer:slice pixels '(0 0) '(3 1)))
          (px.pixelarray:assign line column-shaped)
          (is (equal '(3 2 1)
                     (loop for x below 3 collect (px.pixelarray:ref line x)))))
        (px.buffer:with-view (single-pixel (px.buffer:slice line '(1) '(1)))
          (setf (px.pixelarray:ref single-pixel 0) 9)
          (px.pixelarray:assign pixels single-pixel)
          (is (equal '(9 9 9 9 9 9)
                     (loop for y below 2 append
                       (loop for x below 3 collect (px.pixelarray:ref pixels x y))))))))))

(test pixelarray-metadata-is-defensive-and-kind-checked
  (px.surface:with-surface (surface '(2 2))
    (let ((pixels (px.pixelarray:make-pixel-array surface)))
      (unwind-protect
           (progn
             (is (= 2 (px.pixelarray:ndim pixels)))
             (is (= (px.surface:get-bytesize surface) (px.pixelarray:itemsize pixels)))
             (is (equal '(2 2) (px.pixelarray:shape pixels)))
             (is (equal '(4 8) (px.pixelarray:strides pixels)))
             (setf (first (px.pixelarray:shape pixels)) 20
                   (first (px.pixelarray:strides pixels)) 20)
             (is (equal '(2 2) (px.pixelarray:shape pixels)))
             (is (equal '(4 8) (px.pixelarray:strides pixels)))
             (px.pixelarray:close pixels)
             (dolist (accessor (list #'px.pixelarray:surface #'px.pixelarray:itemsize
                                     #'px.pixelarray:ndim #'px.pixelarray:shape
                                     #'px.pixelarray:strides))
               (signals px:disposed-resource (funcall accessor pixels))))
        (unless (px.buffer:closed-p pixels) (px.pixelarray:close pixels)))))
  (px.surface:with-surface (surface '(1 1))
    (px.buffer:with-view (red (px.surfarray:pixels-red surface))
      (signals error (px.pixelarray:shape red)))))

(test pixelarray-line-dependents-pin-parent-and-surface
  (px.surface:with-surface (surface '(2 2))
    (let ((pixels (px.pixelarray:make-pixel-array surface)))
      (let ((line (px.pixelarray:row pixels 0)))
        (signals px:resource-in-use (px.pixelarray:close pixels))
        (signals px:resource-in-use (px:dispose surface))
        (px.pixelarray:close line))
      (px.pixelarray:close pixels)
      (is (not (px.surface:locked-p surface))))))
