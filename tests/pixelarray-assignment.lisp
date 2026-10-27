;;;; PixelArray color setters and safe, broadcast-aware bulk assignment.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test pixelarray-setf-ref-maps-colors-and-keeps-packed-getter
  (px.surface:with-surface (surface '(2 1) :alpha t)
    (px.pixelarray:with-pixel-array (pixels surface)
      (setf (px.pixelarray:ref pixels 0 0) "#12345678"
            (px.pixelarray:ref pixels 1 0) (px:make-color 200 10 20 255))
      (is (equal '(18 52 86 120)
                 (px.color:to-list (px.surface:get-at surface '(0 0)))))
      (is (equal '(200 10 20 255)
                 (px.color:to-list (px.surface:get-at surface '(1 0)))))
      (is (integerp (px.pixelarray:ref pixels 0 0))
          "PixelArray reads remain native packed integers."))))

(test pixelarray-signed-32-bit-assignment-is-packed
  (px.surface:with-surface (surface '(1 1) :alpha t)
    (px.pixelarray:with-pixel-array (pixels surface)
      (setf (px.pixelarray:ref pixels 0 0) -1)
      (is (= #xffffffff (px.pixelarray:ref pixels 0 0))))))

(test pixelarray-assign-color-array-and-singleton-broadcast
  (px.surface:with-surface (surface '(2 2) :alpha t)
    (px.pixelarray:with-pixel-array (pixels surface)
      (px.pixelarray:assign pixels "navy")
      (px.pixelarray:assign pixels #(1 2 3))
      (is (equal '(1 2 3 255)
                 (px.color:to-list (px.surface:get-at surface '(0 0)))))
      (px.pixelarray:assign pixels #2A(("red") ("lime")))
      (is (equal '(255 0 0 255) (px.color:to-list (px.surface:get-at surface '(0 0)))))
      (is (equal '(0 255 0 255) (px.color:to-list (px.surface:get-at surface '(1 1)))))
      (px.pixelarray:assign pixels #2A(("white" "black")))
      (is (equal '(255 255 255 255) (px.color:to-list (px.surface:get-at surface '(1 0)))))
      (is (equal '(0 0 0 255) (px.color:to-list (px.surface:get-at surface '(1 1))))))))

(test pixelarray-assign-remaps-alternate-24-bit-masks-and-fills-16-bit
  (px.surface:with-surface (source '(1 1) :depth 24
                                   :masks '(#xff0000 #x00ff00 #x0000ff 0))
    (px.surface:with-surface (target '(1 1) :depth 24
                                     :masks '(#x0000ff #x00ff00 #xff0000 0))
      (px.surface:set-at source '(0 0) '(20 130 240))
      (px.pixelarray:with-pixel-array (source-pixels source)
        (px.pixelarray:with-pixel-array (target-pixels target)
          (px.pixelarray:assign target-pixels source-pixels)
          (is (equal '(20 130 240 255)
                     (px.color:to-list (px.surface:get-at target '(0 0))))))))
  (px.surface:with-surface (surface '(2 1) :depth 16)
    (px.pixelarray:with-pixel-array (pixels surface)
      (px.pixelarray:assign pixels #(255 0 0))
      (is (equal '(255 0 0 255)
                 (px.color:to-list (px.surface:get-at surface '(1 0)))))))))

(test pixelarray-overlapping-assignment-snapshots-source
  (px.surface:with-surface (surface '(4 1))
    (px.pixelarray:with-pixel-array (pixels surface)
      (dotimes (x 4) (setf (px.pixelarray:ref pixels x 0) (1+ x)))
      (px.buffer:with-view (left (px.buffer:slice pixels '(0 0) '(3 1)))
        (px.buffer:with-view (right (px.buffer:slice pixels '(1 0) '(3 1)))
          (px.pixelarray:assign right left)))
      (is (equal '(1 1 2 3)
                 (loop for x below 4 collect (px.pixelarray:ref pixels x 0)))))))

(test pixelarray-assign-preserves-indices-across-indexed-palettes
  (px.surface:with-surface (source '(1 1) :depth 8)
    (px.surface:with-surface (target '(1 1) :depth 8)
      (px.surface:set-palette-at source 9 '(255 0 0))
      (px.surface:set-palette-at target 9 '(0 0 255))
      (px.pixelarray:with-pixel-array (source-pixels source)
        (px.pixelarray:with-pixel-array (target-pixels target)
          (setf (px.pixelarray:ref source-pixels 0 0) 9)
          (px.pixelarray:assign target-pixels source-pixels)
          (is (= 9 (px.pixelarray:ref target-pixels 0 0)))
          (is (equal '(0 0 255 255)
                     (px.color:to-list (px.surface:get-at target '(0 0))))))))))

(test pixelarray-singleton-broadcast-and-transposed-overlap
  (px.surface:with-surface (surface '(2 2))
    (px.pixelarray:with-pixel-array (pixels surface)
      (setf (px.pixelarray:ref pixels 0 0) 1
            (px.pixelarray:ref pixels 0 1) 2)
      (px.buffer:with-view (column (px.buffer:slice pixels '(0 0) '(1 2)))
        (px.pixelarray:assign pixels column))
      (is (equal '(1 1 2 2)
                 (loop for y below 2 append
                   (loop for x below 2 collect (px.pixelarray:ref pixels x y)))))
      (setf (px.pixelarray:ref pixels 0 0) 1
            (px.pixelarray:ref pixels 0 1) 2
            (px.pixelarray:ref pixels 1 0) 3
            (px.pixelarray:ref pixels 1 1) 4)
      (px.buffer:with-view (reversed (px.buffer:slice pixels '(1 0) '(2 2) '(-1 1)))
        (px.buffer:with-view (transposed (px.pixelarray:transpose reversed))
          (px.pixelarray:assign reversed transposed)))
      (is (equal '(4 3 2 1)
                 (loop for y below 2 append
                   (loop for x below 2 collect (px.pixelarray:ref pixels x y))))))))

(test pixelarray-assign-validation-is-atomic-and-view-aware
  (px.surface:with-surface (surface '(2 2))
    (px.pixelarray:with-pixel-array (pixels surface)
      (px.pixelarray:assign pixels 7)
      (let ((before (px.surfarray:array2d surface)))
        (signals error (px.pixelarray:assign pixels #2A((1 2) (3 "not a color"))))
        (signals error (px.pixelarray:assign pixels #2A((1 2 3))))
        (is (equalp before (px.surfarray:array2d surface))))
      (px.buffer:with-view (channels (px.surfarray:pixels3d surface))
        (signals error (px.pixelarray:assign pixels channels))
        (signals error (px.pixelarray:assign channels pixels))))))

(test pixelarray-assign-rejects-closed-source-and-target
  (px.surface:with-surface (surface '(1 1))
    (let ((source (px.pixelarray:make-pixel-array surface))
          (target (px.pixelarray:make-pixel-array surface)))
      (unwind-protect
           (progn
             (px.pixelarray:close source)
             (signals px:disposed-resource (px.pixelarray:assign target source))
             (px.pixelarray:close target)
             (signals px:disposed-resource (px.pixelarray:assign target 1)))
        (unless (px.buffer:closed-p source) (px.pixelarray:close source))
        (unless (px.buffer:closed-p target) (px.pixelarray:close target))))))

(test pixelarray-operations-reject-forged-metadata-matching-buffer-views
  (px.surface:with-surface (surface '(1 1))
    (let* ((writer-called nil)
          (fake (px.buffer:make-view
                 :owner surface
                 :dimensions (list (px.surface:width surface) (px.surface:height surface))
                 :strides (list (px.surface:get-bytesize surface) (px.surface:get-pitch surface))
                 :element-type `(unsigned-byte ,(* 8 (px.surface:get-bytesize surface)))
                 :reader (lambda (x y) (declare (ignore x y)) 0)
                 :writer (lambda (value x y)
                           (declare (ignore value x y))
                           (setf writer-called t)))))
      (unwind-protect
           (progn
             (signals error (px.pixelarray:assign fake 7))
             (is (not writer-called)))
        (px.buffer:close fake)))))
