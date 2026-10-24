;;;; Raw views address storage; drawing clips apply only to drawing operations.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test raw-pixel-writes-ignore-drawing-clip
  (px.surface:with-surface (surface '(3 3) :alpha t)
    (px.surface:set-clip surface '(1 1 1 1))
    (px.buffer:with-view (pixels (px.surfarray:pixels3d surface))
      (setf (px.buffer:view-ref pixels 0 0 0) 123))
    (is (= 123 (px:color-r (px.surface:get-at surface '(0 0)))))
    (px.surfarray:blit-array surface (make-array '(3 3 3) :element-type '(unsigned-byte 8) :initial-element 42))
    (is (= 42 (px:color-g (px.surface:get-at surface '(2 2)))))
    (is (equal '(1 1) (list (px.rect:x (px.surface:get-clip surface))
                            (px.rect:y (px.surface:get-clip surface)))))))

(test buffer-shape-and-strides-are-protected
  (px.surface:with-surface (surface '(2 2))
    (px.buffer:with-view (pixels (px.surfarray:pixels2d surface))
      (setf (first (px.buffer:dimensions pixels)) 1000000
            (first (px.buffer:strides pixels)) 1000000)
      (is (equal '(2 2) (px.buffer:dimensions pixels)))
      (is (= 4 (first (px.buffer:strides pixels))))
      (signals type-error (px.buffer:view-ref pixels 2 0)))))

(test imported-channels-expose-accurate-byte-layout
  (cffi:with-foreign-object (storage :uint8 16)
    (dotimes (index 16) (setf (cffi:mem-aref storage :uint8 index) 0))
    (let ((surface (px.image:from-buffer storage '(2 2) :bgra :byte-count 16)))
      (unwind-protect
           (px.buffer:with-view (pixels (px.surfarray:pixels3d surface))
             (is (equal '(4 8 -1) (px.buffer:strides pixels)))
             (is (= 2 (px.buffer:byte-offset pixels)))
             (setf (px.buffer:view-ref pixels 1 1 0) 11
                   (px.buffer:view-ref pixels 1 1 1) 22
                   (px.buffer:view-ref pixels 1 1 2) 33)
             (is (= 33 (cffi:mem-aref storage :uint8 12)))
             (is (= 11 (cffi:mem-aref storage :uint8 14)))
             (px.buffer:with-view (slice (px.buffer:slice pixels '(1 1 0) '(2 1 3) '(-1 1 1)))
               (is (= 14 (px.buffer:byte-offset slice)))
               (is (equal '(-4 8 -1) (px.buffer:strides slice)))
               (is (= 11 (px.buffer:view-ref slice 0 0 0)))))
        (px:dispose surface)))))

(test opaque-alpha-copies-have-no-mutable-channel
  (px.surface:with-surface (surface '(2 1))
    (is (= 255 (aref (px.surfarray:array-alpha surface) 0 0)))
    (signals px:unsupported-feature (px.surfarray:pixels-alpha surface))
    (is (not (px.surface:locked-p surface)))))

(test buffer-construction-validates-before-pinning
  (px.surface:with-surface (surface '(1 1))
    (let ((parent (px.surfarray:pixels2d surface)))
      (signals error (px.buffer:make-view :owner parent :dimensions '(1) :strides '(1 2) :reader #'identity))
      (signals error (px.buffer:make-view :owner parent :dimensions '(1) :reader :not-a-function))
      (px.buffer:close parent)
      (is (not (px.surface:locked-p surface))))))

(test empty-views-still-check-closed-owners
  (let* ((owner (pixelisp.internal:register-resource (make-instance 'pixelisp.internal:resource)))
         (view (px.buffer:make-view :owner owner :dimensions '(0) :reader #'identity)))
    (unwind-protect
         (progn
           (px:dispose owner)
           (signals px:disposed-resource (px.buffer:to-array view))
           (signals px:disposed-resource (px.buffer:make-view :owner owner :dimensions '(0) :reader #'identity)))
      (px:dispose view) (px:dispose owner))))

(test slice-sequences-and-empty-slice-validation
  (px.surface:with-surface (surface '(2 2))
    (px.buffer:with-view (pixels (px.surfarray:pixels2d surface))
      (px.buffer:with-view (slice (px.buffer:slice pixels #(1 0) #(2 1) #(-1 1)))
        (is (equal '(2 1) (px.buffer:dimensions slice)))
        (is (= 4 (px.buffer:byte-offset slice))))
      (signals error (px.buffer:slice pixels '(-1 0) '(0 0)))
      (signals error (px.buffer:slice pixels '(0 0) '(0 0) '(0 1))))))

(test color-key-metadata-does-not-alias-caller-values
  (px.surface:with-surface (surface '(1 1))
    (let ((channels (list 255 0 255)))
      (px.surface:set-colorkey surface channels)
      (setf (first channels) 0)
      (is (= 255 (px:color-r (px.surface:get-colorkey surface)))))
    (let ((key (px.surface:get-colorkey surface)))
      (setf (px:color-r key) 0)
      (is (= 255 (px:color-r (px.surface:get-colorkey surface)))))))
