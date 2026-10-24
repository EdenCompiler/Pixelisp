;;;; pygame 2.6.1 reference cases for Mask.to_surface behavior.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test mask-to-surface-default-colors-and-transparent-channels
  (let* ((mask (px.mask:make-mask '(2 1)))
         (image nil))
    (px.mask:set-at mask '(0 0))
    (setf image (px.mask:to-surface mask))
    (unwind-protect
         (progn
           (is (equal '(255 255 255 255) (px.color:to-list (px.surface:get-at image '(0 0)))))
           ;; pygame's default unset color is opaque black.
           (is (equal '(0 0 0 255) (px.color:to-list (px.surface:get-at image '(1 0)))))
           (px.mask:set-at mask '(0 0))
           (px.mask:to-surface mask :surface image :set-color '(17 29 41 0))
           (is (equal '(17 29 41 0) (px.color:to-list (px.surface:get-at image '(0 0))))))
      (px:dispose image))))

(test mask-to-surface-offset-clips-and-preserves-skipped-pixels
  (let ((mask (px.mask:make-mask '(3 2) :fill t)))
    (px.surface:with-surface (target '(4 3) :alpha t)
      (px.surface:fill target '(8 16 24 32))
      (px.surface:set-clip target '(1 1 2 1))
      (is (eq target (px.mask:to-surface mask :surface target :dest '(-1 1)
                                         :set-color '(200 100 50 0) :unset-color nil)))
      ;; Destination x=-1 maps mask x=2 to target x=1. Clip selects only y=1.
      (is (equal '(200 100 50 0) (px.color:to-list (px.surface:get-at target '(1 1)))))
      (is (equal '(8 16 24 32) (px.color:to-list (px.surface:get-at target '(0 1)))))
      (is (equal '(8 16 24 32) (px.color:to-list (px.surface:get-at target '(1 0))))))))

(test mask-to-surface-short-source-planes-use-color-fallback
  (let ((mask (px.mask:make-mask '(3 2) :fill t)))
    (px.surface:with-surface (target '(3 2) :alpha t)
      (px.surface:with-surface (plane '(1 1) :alpha t)
        (px.surface:set-at plane '(0 0) '(14 28 42 0))
        (px.mask:to-surface mask :surface target :set-surface plane
                            :set-color '(90 80 70 60) :unset-color nil)
        (is (equal '(14 28 42 0) (px.color:to-list (px.surface:get-at target '(0 0)))))
        (is (equal '(90 80 70 60) (px.color:to-list (px.surface:get-at target '(1 0)))))
        (is (equal '(90 80 70 60) (px.color:to-list (px.surface:get-at target '(2 1)))))))))

(test mask-to-surface-aliased-source-reads-original-pixels
  (px.surface:with-surface (parent '(5 1) :alpha t)
    (loop for x below 5 for red in '(10 20 30 40 50)
          do (px.surface:set-at parent (list x 0) (list red 0 0 255)))
    (let ((mask (px.mask:make-mask '(4 1) :fill t)))
      (px:with-resource (source (px.surface:subsurface parent '(0 0 4 1)))
        (px:with-resource (target (px.surface:subsurface parent '(1 0 4 1)))
          (px.mask:to-surface mask :surface target :set-surface source :unset-color nil)))
      (is (equal '(10 10 20 30 40)
                 (loop for x below 5 collect (px.color:r (px.surface:get-at parent (list x 0)))))))))

(test mask-to-surface-rejects-format-mismatch
  (let ((mask (px.mask:make-mask '(1 1))))
    (px.surface:with-surface (target '(1 1) :alpha t)
      (px.surface:with-surface (opaque '(1 1))
        (px.surface:fill target '(11 22 33 44))
        (signals error
          (px.mask:to-surface mask :surface target :set-surface opaque))
        (is (equal '(11 22 33 44) (px.color:to-list (px.surface:get-at target '(0 0)))))
        ;; With an implicit result, a format failure must dispose its temporary.
        (let ((before (length pixelisp.internal:*resources*)))
          (signals error (px.mask:to-surface mask :set-surface opaque))
          (is (= before (length pixelisp.internal:*resources*))))))))

(test mask-to-surface-validates-colors-before-writing
  (let ((mask (px.mask:make-mask '(2 1) :fill t)))
    (px.surface:with-surface (target '(2 1) :alpha t)
      (px.surface:fill target '(11 22 33 44))
      (signals error
        (px.mask:to-surface mask :surface target :set-color '(256 2 3)))
      (is (equal '((11 22 33 44) (11 22 33 44))
                 (loop for x below 2 collect
                   (px.color:to-list (px.surface:get-at target (list x 0)))))))))

(test mask-to-surface-checks-liveness-for-empty-masks
  (let ((mask (px.mask:make-mask '(0 0))))
    (px.surface:with-surface (target '(1 1) :alpha t)
      (px:dispose target)
      (signals px:disposed-resource
        (px.mask:to-surface mask :surface target :set-color nil :unset-color nil))))
  (let ((mask (px.mask:make-mask '(0 0)))
        (source (px.surface:make-surface '(1 1) :alpha t)))
    (px:dispose source)
    (signals px:disposed-resource
      (px.mask:to-surface mask :set-surface source))))
