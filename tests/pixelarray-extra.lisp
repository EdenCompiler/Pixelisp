;;;; PixelArray distance operations, native color decoding, and dependent views.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test pixelarray-distance-options-and-no-partial-writes
  (px.surface:with-surface (surface '(2 1) :alpha t)
    (px.surface:set-at surface '(0 0) '(0 0 0 0))
    (px.surface:set-at surface '(1 0) '(100 0 0 255))
    (px.pixelarray:with-pixel-array (pixels surface)
      ;; Red-only weighting rejects the second pixel; green-only accepts it.
      (is (equalp #2A((1) (0))
                  (px.pixelarray:extract pixels '(0 0 0) :distance 0.1
                                        :weights '(1 0 0))))
      (is (equalp #2A((1) (1))
                  (px.pixelarray:extract pixels '(0 0 0) :distance 0.1
                                        :weights '(0 1 0))))
      ;; Alpha is ignored once distance matching is enabled.
      (is (equalp #2A((1) (0))
                  (px.pixelarray:extract pixels '(0 0 0) :distance 0.01)))
      (let ((before (px.surfarray:array2d surface)))
        (signals error (px.pixelarray:replace pixels '(0 0 0) '(255 0 0)
                                              :distance 0.1 :weights '(0 0 0)))
        (is (equalp before (px.surfarray:array2d surface)))))))

(test pixelarray-compare-decodes-native-formats
  (px.surface:with-surface (first '(1 1) :alpha t)
    (px.surface:set-at first '(0 0) '(200 10 30 128))
    (cffi:with-foreign-object (storage :uint8 4)
      ;; BGRA bytes encode the same RGBA color in a different native layout.
      (setf (cffi:mem-aref storage :uint8 0) 30
            (cffi:mem-aref storage :uint8 1) 10
            (cffi:mem-aref storage :uint8 2) 200
            (cffi:mem-aref storage :uint8 3) 128)
      (let ((second (px.image:from-buffer storage '(1 1) :bgra :byte-count 4)))
        (unwind-protect
             (px.pixelarray:with-pixel-array (a first)
               (px.pixelarray:with-pixel-array (b second)
                 (is (equalp #2A((1)) (px.pixelarray:compare a b)))
                 (let ((copy (px.pixelarray:make-surface b)))
                   (unwind-protect
                        (is (equal '(200 10 30 128)
                                   (px.color:to-list (px.surface:get-at copy '(0 0)))))
                     (px:dispose copy)))))
          (px:dispose second))))))

(test pixelarray-negative-slice-transpose-and-lifetime
  (px.surface:with-surface (surface '(3 2))
    (px.pixelarray:with-pixel-array (pixels surface)
      (setf (px.pixelarray:ref pixels 0 1) (px.surface:map-rgb surface '(10 20 30)))
      (px.buffer:with-view (reversed (px.buffer:slice pixels '(2 0) '(3 2) '(-1 1)))
        (px.buffer:with-view (transposed (px.pixelarray:transpose reversed))
          (is (equal '(2 3) (px.buffer:dimensions transposed)))
          (is (= (px.pixelarray:ref pixels 0 1) (px.pixelarray:ref transposed 1 2)))
          (setf (px.pixelarray:ref transposed 1 2) (px.surface:map-rgb surface '(40 50 60)))
          (is (equal '(40 50 60 255)
                     (px.color:to-list (px.surface:get-at surface '(0 1)))))
          (signals px:resource-in-use (px.pixelarray:close reversed)))))))

(test pixelarray-empty-view-checks-liveness
  (px.surface:with-surface (surface '(1 1))
    (let ((pixels (px.pixelarray:make-pixel-array surface)))
      (unwind-protect
           (let ((empty (px.buffer:slice pixels '(0 0) '(0 0))))
             (px.buffer:close empty)
             (signals px:disposed-resource
               (px.pixelarray:extract empty '(0 0 0))))
        (px.buffer:close pixels)))))

(test pixelarray-copy-preserves-opaque-format-and-rejects-channel-views
  (px.surface:with-surface (source '(2 1))
    (px.surface:set-at source '(1 0) "tomato")
    (px.pixelarray:with-pixel-array (pixels source)
      (px:with-resource (copy (px.pixelarray:make-surface pixels))
        (is (not (px.surface:alpha-p copy)))
        (is (eq :none (px.surface:get-blendmode copy)))
        (is (equal '(255 99 71 255) (px.color:to-list (px.surface:get-at copy '(1 0)))))))
    (px.buffer:with-view (red (px.surfarray:pixels-red source))
      (signals error (px.pixelarray:extract red "tomato")))))
