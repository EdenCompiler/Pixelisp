;;;; Fixed pixel expectations come from pygame 2.6.1, not the blend helpers.
;;;; Tiny images also make ownership, clipping, and aliasing failures obvious.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test channel-blend-effects
  (px.surface:with-surface (target '(1 1) :alpha t)
    (px.surface:with-surface (source '(1 1) :alpha t)
      (px.surface:fill source '(200 50 128 40))
      ;; Channel effects combine stored values: blanket alpha and the key do
      ;; not turn this into an ordinary alpha-composited blit.
      (px.surface:set-alpha source 3)
      (px.surface:set-colorkey source '(200 50 128))
      (dolist (fixture '((:blend-rgb-add (255 130 188 120))
                         (:blend-rgb-sub (0 30 0 120))
                         (:blend-rgb-mult (79 16 30 120))
                         (:blend-rgb-min (100 50 60 120))
                         (:blend-rgb-max (200 80 128 120))
                         (:blend-rgba-add (255 130 188 160))
                         (:blend-rgba-sub (0 30 0 80))
                         (:blend-rgba-mult (79 16 30 19))
                         (:blend-rgba-min (100 50 60 40))
                         (:blend-rgba-max (200 80 128 120))))
        (px.surface:fill target '(100 80 60 120))
        (px.surface:blit target source '(0 0) :special-flags (first fixture))
        (is (equal (second fixture) (px.color:to-list (px.surface:get-at target '(0 0)))))
        (px.surface:fill target '(100 80 60 120))
        (px.surface:fill target '(200 50 128 40) nil :special-flags (first fixture))
        (is (equal (second fixture) (px.color:to-list (px.surface:get-at target '(0 0)))))))))

(test blend-clipping-and-source-area
  (px.surface:with-surface (target '(4 3) :alpha t)
    (px.surface:with-surface (source '(3 3) :alpha t)
      (px.surface:fill target '(10 20 30 40))
      (px.surface:fill source '(50 60 70 80))
      (px.surface:set-at source '(1 1) '(100 110 120 130))
      (px.surface:set-clip target '(2 1 1 1))
      ;; The off-image source area moves the first actual source pixel one
      ;; place right and down. Destination clipping then selects source (1,1).
      (let ((damage (px.surface:blit target source '(0 -1) :area '(-1 -1 3 3)
                                     :special-flags :blend-rgba-add)))
        (is (equal '(2 1 1 1) (list (px.rect:x damage) (px.rect:y damage)
                                   (px.rect:width damage) (px.rect:height damage)))))
      (is (equal '(110 130 150 170) (px.color:to-list (px.surface:get-at target '(2 1)))))
      (is (equal '(10 20 30 40) (px.color:to-list (px.surface:get-at target '(1 1)))))
      (px.surface:fill target '(1 2 3 4) nil :special-flags :blend-rgba-sub)
      (is (equal '(109 128 147 166) (px.color:to-list (px.surface:get-at target '(2 1)))))
      (is (not (px.surface:locked-p target)))
      (is (not (px.surface:locked-p source))))))

(test blend-overlapping-subsurfaces-read-original-source
  (px.surface:with-surface (parent '(4 1))
    (loop for x below 4 for red in '(10 20 30 40)
          do (px.surface:set-at parent (list x 0) (list red 0 0)))
    (px:with-resource (source (px.surface:subsurface parent '(0 0 3 1)))
      (px:with-resource (target (px.surface:subsurface parent '(1 0 3 1)))
        (px.surface:blit target source '(0 0) :special-flags :blend-add)))
    (is (equal '(10 30 50 70)
               (loop for x below 4 collect (px:color-r (px.surface:get-at parent (list x 0))))))))

(test blend-opaque-source-preserves-destination-alpha
  (px.surface:with-surface (source '(1 1))
    (px.surface:with-surface (target '(1 1) :alpha t)
      (px.surface:fill source '(255 255 255))
      (px.surface:fill target '(1 50 200 80))
      (px.surface:blit target source '(0 0) :special-flags :blend-rgba-mult)
      (is (equal '(1 50 200 80) (px.color:to-list (px.surface:get-at target '(0 0))))))))

(test blend-errors-leave-storage-and-locks-unchanged
  (px.surface:with-surface (surface '(1 1) :alpha t)
    (px.surface:fill surface '(10 20 30 40))
    (signals px:unsupported-feature
      (px.surface:fill surface '(1 2 3) nil :special-flags :unknown))
    (signals px:unsupported-feature
      (px.surface:fill surface '(1 2 3) nil :special-flags :blend-premultiplied))
    (signals px:unsupported-feature
      (px.surface:blit surface surface '(0 0) :special-flags :unknown))
    (signals type-error
      (px.surface:fill surface '(256 0 0) nil :special-flags :blend-add))
    (is (equal '(10 20 30 40) (px.color:to-list (px.surface:get-at surface '(0 0)))))
    (is (not (px.surface:locked-p surface)))
    (px.buffer:with-view (view (px.surfarray:pixels2d surface))
      (is (equal '(1 1) (px.buffer:dimensions view)))
      (signals px:resource-in-use
        (px.surface:blit surface surface '(0 0) :special-flags :blend-add)))))

(test premultiplied-conversion-and-compositing
  (px.surface:with-surface (source '(3 1) :alpha t)
    (loop for x below 3 for alpha in '(0 128 255) do
      (px.surface:set-at source (list x 0) (list 200 50 128 alpha)))
    (px.surface:set-alpha source 64)
    (px.surface:set-colorkey source '(200 50 128))
    (px:with-resource (converted (px.surface:premul-alpha source))
      (is (equal '(0 0 0 0) (px.color:to-list (px.surface:get-at converted '(0 0)))))
      (is (equal '(100 25 64 128) (px.color:to-list (px.surface:get-at converted '(1 0)))))
      (is (equal '(200 50 128 255) (px.color:to-list (px.surface:get-at converted '(2 0)))))
      (is (= 64 (px.surface:get-alpha converted)))
      (is (null (px.surface:get-colorkey converted)))
      (is (equal '(200 50 128 0) (px.color:to-list (px.surface:get-at source '(0 0)))))
      (px.surface:with-surface (target '(3 1) :alpha t)
        (px.surface:fill target '(100 80 60 120))
        (px.surface:blit target converted '(0 0) :special-flags :blend-premultiplied)
        (is (equal '(100 80 60 120) (px.color:to-list (px.surface:get-at target '(0 0)))))
        (is (equal '(150 65 94 188) (px.color:to-list (px.surface:get-at target '(1 0)))))
        (is (equal '(200 50 128 255) (px.color:to-list (px.surface:get-at target '(2 0)))))))))
