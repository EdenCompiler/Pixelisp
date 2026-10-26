;;;; Packed arrays and live views follow each surface's native pixel width.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test packed-array-copies-cover-native-depths
  (dolist (depth '(8 16 24 32))
    (px.surface:with-surface (surface '(3 2) :depth depth)
      (px.surface:set-at surface '(2 1) '(213 61 127))
      (let ((copy (px.surfarray:array2d surface)))
        (is (equal '(3 2) (array-dimensions copy)))
        (is (typep (aref copy 2 1) '(unsigned-byte 32)))
        (let ((color (px.color:to-list (px.surface:get-at surface '(2 1)))))
          (px.buffer:with-view (packed (px.surface:get-view surface #\2))
            (is (= (aref copy 2 1) (px.buffer:view-ref packed 2 1))))
          (is (= (first color) (aref (px.surfarray:array-red surface) 2 1)))
          (is (= (second color) (aref (px.surfarray:array-green surface) 2 1)))
          (is (= (third color) (aref (px.surfarray:array-blue surface) 2 1))))))))

(test surfarray-live-views-respect-native-format-limits
  (dolist (depth '(8 16 24 32))
    (px.surface:with-surface (surface '(2 1) :depth depth)
      (if (= depth 24)
          (signals px:unsupported-feature (px.surfarray:pixels2d surface))
          (px.buffer:with-view (pixels (px.surfarray:pixels2d surface))
            (is (= (px.surface:get-bytesize surface) (first (px.buffer:strides pixels))))))
      (if (member depth '(24 32))
          (px.buffer:with-view (rgb (px.surfarray:pixels3d surface))
            (is (equal '(2 1 3) (px.buffer:dimensions rgb)))
            (is (= (px.surface:get-bytesize surface) (first (px.buffer:strides rgb))))
            (setf (px.buffer:view-ref rgb 1 0 0) 10)
            (is (= 10 (px:color-r (px.surface:get-at surface '(1 0))))))
          (progn
            (signals px:unsupported-feature (px.surfarray:pixels3d surface))
            (signals px:unsupported-feature (px.surfarray:pixels-red surface)))))))

(test pixelarray-copies-preserve-depth-and-native-pixel-values
  (dolist (depth '(8 16 24 32))
    (px.surface:with-surface (surface '(2 2) :depth depth)
      (px.pixelarray:with-pixel-array (pixels surface)
        (setf (px.pixelarray:ref pixels 1 1)
              (px.surface:map-rgb surface '(121 53 207)))
        (px:with-resource (copy (px.pixelarray:make-surface pixels))
          (is (= depth (px.surface:get-bitsize copy)))
          (is (= (px.pixelarray:ref pixels 1 1)
                 (px.surface::%read-packed-pixel copy 1 1))))))))

(test indexed-pixelarray-copies-preserve-independent-palettes-and-indices
  (px.surface:with-surface (surface '(2 1) :depth 8)
    (px.surface:set-palette-at surface 7 '(200 40 10))
    (px.pixelarray:with-pixel-array (pixels surface)
      (setf (px.pixelarray:ref pixels 1 0) 7)
      (let ((packed-copy (px.surfarray:array2d surface))
            (rgb-copy (px.surfarray:array3d surface)))
        (px:with-resource (copy (px.pixelarray:make-surface pixels))
          (is (= 7 (px.surface::%read-packed-pixel copy 1 0)))
          (px.surface:set-palette-at surface 7 '(1 2 3))
          (is (= 7 (aref packed-copy 1 0)))
          (is (= 200 (aref rgb-copy 1 0 0)))
          (is (= 200 (px:color-r (px.surface:get-at copy '(1 0)))))
          (is (= 1 (px:color-r (px.surface:get-at surface '(1 0))))))))))

(test packed-array-write-validation-does-not-partially-mutate
  (px.surface:with-surface (surface '(2 1) :depth 16)
    (let ((before (px.surfarray:array2d surface))
          (invalid (make-array '(2 1) :initial-contents '((12) (70000)))))
      (signals type-error (px.surfarray:blit-array surface invalid))
      (is (equalp before (px.surfarray:array2d surface))))))

(test low-depth-pixelarray-slices-and-transposes-retain-owners
  (px.surface:with-surface (surface '(3 2) :depth 16)
    (let ((pixels (px.pixelarray:make-pixel-array surface)))
      (unwind-protect
           (let ((slice (px.buffer:slice pixels '(2 0) '(3 2) '(-1 1))))
             (unwind-protect
                  (let ((transposed (px.pixelarray:transpose slice)))
                    (unwind-protect
                         (progn
                           (is (equal '(2 3) (px.buffer:dimensions transposed)))
                           (setf (px.pixelarray:ref transposed 1 2)
                                 (px.surface:map-rgb surface '(180 70 20)))
                           (is (= (px.pixelarray:ref pixels 0 1)
                                  (px.pixelarray:ref transposed 1 2)))
                           (signals px:resource-in-use (px.buffer:close slice))
                           (signals px:resource-in-use (px:dispose surface)))
                      (px.buffer:close transposed)))
               (px.buffer:close slice)))
      (px.buffer:close pixels))
      (is (not (px.surface:locked-p surface))))))

(test pixelarray-integer-colors-retain-signed-32bit-compatibility
  (px.surface:with-surface (surface '(1 1) :alpha t)
    (px.pixelarray:with-pixel-array (pixels surface)
      (setf (px.pixelarray:ref pixels 0 0) #xffffffff)
      (px.pixelarray:replace pixels -1 0)
      (is (= 0 (px.pixelarray:ref pixels 0 0)))))
  (px.surface:with-surface (surface '(1 1) :depth 16)
    (px.pixelarray:with-pixel-array (pixels surface)
      (let ((before (px.pixelarray:ref pixels 0 0)))
        (signals type-error (px.pixelarray:replace pixels -1 0))
        (is (= before (px.pixelarray:ref pixels 0 0)))))))
