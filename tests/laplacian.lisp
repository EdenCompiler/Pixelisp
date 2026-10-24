;;;; The eight-neighbor Laplacian uses deterministic opaque white padding for
;;;; missing samples. Keep these tiny fixtures literal and readable.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test laplacian-kernel-channels-and-raw-storage
  (px.surface:with-surface (source '(5 5) :alpha t)
    (px.surface:fill source '(0 0 0 0))
    (px.surface:set-at source '(2 2) '(40 30 20 16))
    (px.surface:with-surface (edges '(5 5) :alpha t)
      ;; The center lies outside this clip, but raw transform output still writes it.
      (px.surface:set-clip edges '(0 0 1 1))
      (is (eq edges (px.transform:laplacian source edges)))
      ;; Eight times the center pixel, since all eight neighbors are zero.
      (is (equal '(255 240 160 128)
                 (px.color:to-list (px.surface:get-at edges '(2 2)))))
      (is (equal '(0 0 0 0) (px.color:to-list (px.surface:get-at edges '(1 1))))))))

(test laplacian-white-missing-neighbors
  (px.surface:with-surface (source '(3 3) :alpha t)
    (px.surface:fill source '(255 255 255 255))
    (px:with-resource (edges (px.transform:laplacian source))
      ;; A flat image has zero response both inside and at the white-padded edge.
      (dolist (point '((0 0) (1 0) (2 1) (1 1) (2 2)))
        (is (equal '(0 0 0 0)
                   (px.color:to-list (px.surface:get-at edges point))))))))

(test laplacian-destination-and-aliasing
  (px.surface:with-surface (source '(3 3) :alpha t)
    (px.surface:fill source '(0 0 0 0))
    (px.surface:set-at source '(1 1) '(20 30 40 50))
    (px.surface:with-surface (destination '(3 3) :alpha t)
      (px.surface:fill destination '(99 98 97 96))
      (is (eq destination (px.transform:laplacian source destination)))
      (is (equal '(160 240 255 255)
                 (px.color:to-list (px.surface:get-at destination '(1 1)))))
      ;; In-place output is computed from a source snapshot, not prior results.
      (is (eq source (px.transform:laplacian source source)))
      (is (equal '(160 240 255 255)
                 (px.color:to-list (px.surface:get-at source '(1 1))))))))

(test laplacian-rejects-incompatible-destination-before-writing
  (px.surface:with-surface (source '(2 2) :alpha t)
    (px.surface:fill source '(10 20 30 40))
    (px.surface:with-surface (wrong-size '(1 2) :alpha t)
      (px.surface:fill wrong-size '(91 92 93 94))
      (signals error (px.transform:laplacian source wrong-size))
      (is (equal '(91 92 93 94)
                 (px.color:to-list (px.surface:get-at wrong-size '(0 0)))))))
  (let ((disposed (px.surface:make-surface '(2 2) :alpha t)))
    (px.surface:dispose disposed)
    (signals px:disposed-resource
      (px.transform:laplacian disposed))))
