;;;; pygame 2.6.1 reference cases for Mask.get_rect anchor support.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test mask-get-rect-default-and-empty-dimensions
  (dolist (size '((0 0) (0 4) (5 0) (3 2)))
    (let* ((rect (px.mask:get-rect (px.mask:make-mask size)))
           (actual (list (px.rect:x rect) (px.rect:y rect)
                         (px.rect:width rect) (px.rect:height rect))))
      (is (equal (append '(0 0) size) actual)))))

(test mask-get-rect-supports-rect-anchor-keywords
  (let ((mask (px.mask:make-mask '(7 5))))
    (is (equal '(13 17 7 5)
               (let ((r (px.mask:get-rect mask :center '(16 19))))
                 (list (px.rect:x r) (px.rect:y r) (px.rect:width r) (px.rect:height r)))))
    (is (equal '(4 8 7 5)
               (let ((r (px.mask:get-rect mask :top-left #(4 8))))
                 (list (px.rect:x r) (px.rect:y r) (px.rect:width r) (px.rect:height r)))))
    (is (equal '(10 20 7 5)
               (let ((r (px.mask:get-rect mask :right 17 :bottom 25)))
                 (list (px.rect:x r) (px.rect:y r) (px.rect:width r) (px.rect:height r)))))
    ;; Later anchors win, matching Rect's sequential keyword assignment.
    (is (equal '(8 9 7 5)
               (let ((r (px.mask:get-rect mask :topleft '(1 2) :x 8 :y 9)))
                 (list (px.rect:x r) (px.rect:y r) (px.rect:width r) (px.rect:height r)))))))

(test mask-get-rect-rejects-invalid-anchors
  (let ((mask (px.mask:make-mask '(2 2))))
    (signals error (px.mask:get-rect mask :center))
    (signals error (px.mask:get-rect mask :not-an-anchor '(0 0)))
    (signals error (px.mask:get-rect mask :left '(1 2)))
    (signals error (px.mask:get-rect mask :center '(1)))))
