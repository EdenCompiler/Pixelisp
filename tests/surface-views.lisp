;;;; Surface buffer views expose native pixels with explicit, scoped ownership.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test surface-buffer-views-read-write-and-lock-owner
  (px.surface:with-surface (surface '(2 2) :alpha t)
    (px.surface:set-at surface '(1 1) '(20 40 60 80))
    (let ((buffer (px.surface:get-buffer surface))
          (bytes (px.surface:get-view surface #\0))
          (flat (px.surface:get-view surface #\1))
          (packed (px.surface:get-view surface))
          (rgb (px.surface:get-view surface "3"))
          (red (px.surface:get-view surface #\R)))
      (unwind-protect
           (progn
             (is (= 16 (first (px.buffer:dimensions buffer))))
             (is (= 16 (first (px.buffer:dimensions bytes))))
             (is (= 4 (first (px.buffer:dimensions flat))))
             (is (equal '(2 2) (px.buffer:dimensions packed)))
             (is (equal '(2 2 3) (px.buffer:dimensions rgb)))
             (is (= 20 (px.buffer:view-ref rgb 1 1 0)))
             (is (= 40 (px.buffer:view-ref rgb 1 1 1)))
             (is (= 20 (px.buffer:view-ref red 1 1)))
             (setf (px.buffer:view-ref red 1 1) 99)
             (setf (px.buffer:view-ref bytes 0) 17)
             (setf (px.buffer:view-ref flat 0) (px.surface:map-rgb surface '(1 2 3 4)))
             (is (equal '(1 2 3 4)
                        (px.color:to-list (px.surface:get-at surface '(0 0)))))
             (is (= 99 (first (px.color:to-list (px.surface:get-at surface '(1 1))))))
             (is (px.surface:locked-p surface))
             (signals px:resource-in-use (px:dispose surface)))
        (dolist (view (list red rgb packed flat bytes buffer))
          (px.buffer:close view)))
      (is (not (px.surface:locked-p surface)))
      (signals px:disposed-resource (px.buffer:view-ref buffer 0))
      (px:dispose surface)
      (signals px:disposed-resource (px.surface:get-view surface)))))

(test surface-buffer-padded-subsurface-and-discontinuous-view-rejection
  (px.surface:with-surface (parent '(4 3) :alpha t)
    (px.surface:set-at parent '(1 1) '(10 20 30 40))
    (px:with-resource (child (px.surface:subsurface parent '(1 1 2 2)))
      (let ((buffer (px.surface:get-buffer child))
            (green nil))
        (unwind-protect
             (progn
               ;; Include row padding while clipping to the root allocation.
               (is (= 28 (first (px.buffer:dimensions buffer))))
               (is (= 10 (px.buffer:view-ref buffer 0)))
               (setf (px.buffer:view-ref buffer 1) 77)
               (setf green (px.surface:get-view parent #\g))
               (is (= 77 (px.buffer:view-ref green 1 1)))
               (signals px:resource-in-use (px:dispose parent)))
          (when green (px.buffer:close green))
          (px.buffer:close buffer)))
    (px:with-resource (child (px.surface:subsurface parent '(1 0 2 2)))
      (signals px:unsupported-feature (px.surface:get-view child #\0))
      (is (not (px.surface:locked-p child)))
      (signals px:unsupported-feature (px.surface:get-view child #\1))
      (is (not (px.surface:locked-p child)))))))

(test surface-buffer-nested-subsurface-is-bounded-by-root-storage
  (px.surface:with-surface (parent '(4 3) :alpha t)
    (px:with-resource (child (px.surface:subsurface parent '(1 1 3 2)))
      (px:with-resource (nested (px.surface:subsurface child '(1 1 1 1)))
        (px.buffer:with-view (buffer (px.surface:get-buffer nested))
          ;; Absolute start is (2,2), leaving only two root pixels (8 bytes).
          (is (= 8 (first (px.buffer:dimensions buffer))))
          (is (= 16 (px.surface:get-pitch nested))))))))

(test surface-buffer-channel-views-follow-bgra-layout
  (cffi:with-foreign-object (storage :uint8 8)
    (dotimes (index 8) (setf (cffi:mem-aref storage :uint8 index) 0))
    (px:with-resource (surface (px.image:from-buffer storage '(2 1) :bgra :byte-count 8))
      (px.surface:set-at surface '(0 0) '(200 10 30 128))
      (let ((rgb (px.surface:get-view surface #\3))
            (alpha (px.surface:get-view surface "A")))
        (unwind-protect
             (progn
               (is (= -1 (third (px.buffer:strides rgb))))
               (is (= 200 (px.buffer:view-ref rgb 0 0 0)))
               (is (= 10 (px.buffer:view-ref rgb 0 0 1)))
               (is (= 30 (px.buffer:view-ref rgb 0 0 2)))
               (is (= 128 (px.buffer:view-ref alpha 0 0)))
               (setf (px.buffer:view-ref rgb 0 0 2) 90)
               (is (= 90 (third (px.color:to-list (px.surface:get-at surface '(0 0))))))
          (px.buffer:close alpha)
          (px.buffer:close rgb)))))))

(test surface-buffer-alpha-view-rejected-with-lock-cleanup
  (px.surface:with-surface (surface '(1 1))
    (signals px:unsupported-feature (px.surface:get-view surface #\a))
    (is (not (px.surface:locked-p surface)))
    (signals error (px.surface:get-view surface "invalid"))
    (is (not (px.surface:locked-p surface)))))

(test surface-buffer-views-preserve-24-bit-pixels
  (let ((native (sdl2:create-rgb-surface 4 1 24 :r-mask #xff0000
                                        :g-mask #xff00 :b-mask #xff :a-mask 0)))
    (px:with-resource (surface (pixelisp.internal:wrap-surface native :owned t :alpha nil
                                                               :preserve-format t))
      (let ((packed (px.surface:get-view surface #\2))
            (rgb (px.surface:get-view surface #\3))
            (red (px.surface:get-view surface #\r)))
        (unwind-protect
             (progn
               (setf (px.buffer:view-ref packed 2 0)
                     (px.surface:map-rgb surface '(12 34 56)))
               (is (= 24 (px.surface:get-bitsize surface)))
               (is (equal '(unsigned-byte 24) (px.buffer:element-type packed)))
               (is (equal '(4 1) (px.buffer:dimensions packed)))
               (is (= 12 (px.buffer:view-ref rgb 2 0 0)))
               (is (= 34 (px.buffer:view-ref rgb 2 0 1)))
               (is (= 56 (px.buffer:view-ref rgb 2 0 2)))
               (is (= 12 (px.buffer:view-ref red 2 0)))
               (is (= (px.surface:get-bytesize surface)
                      (first (px.buffer:strides packed)))))
          (px.buffer:close red)
          (px.buffer:close rgb)
          (px.buffer:close packed))))))
