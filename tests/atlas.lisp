(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test image-atlas-nested-crops-draw-and-isolate-texture-state
  (px:with-init (:video t)
    (px.sdl2.video:with-window (window :size '(8 3) :hidden t)
      (px.sdl2.video:with-renderer (renderer window)
        (let* ((surface (px.surface:make-surface '(4 1) :alpha t))
               (texture nil) (pixels nil))
          (unwind-protect
               (progn
                 (px.surface:set-at surface '(0 0) '(230 20 10 255))
                 (px.surface:set-at surface '(1 0) '(230 20 10 255))
                 (px.surface:set-at surface '(2 0) '(10 220 30 255))
                 (px.surface:set-at surface '(3 0) '(10 220 30 255))
                 (setf texture (px.sdl2.video:texture-from-surface renderer surface))
                 (let* ((atlas (px.sdl2.video:make-image texture))
                        (parent (px.sdl2.video:make-image atlas '(1 0 3 1)))
                        (leaf (px.sdl2.video:make-image parent '(1 0 2 1))))
                   ;; The nested local (1,0) crop resolves to texture region (2,0,2,1).
                   (is (equal '(2 0 2 1)
                              (list (px.rect:x (px.sdl2.video:image-source-rect leaf))
                                    (px.rect:y (px.sdl2.video:image-source-rect leaf))
                                    (px.rect:width (px.sdl2.video:image-source-rect leaf))
                                    (px.rect:height (px.sdl2.video:image-source-rect leaf)))))
                   (let ((anchored (px.sdl2.video:image-get-rect leaf :center '(5 2))))
                     (is (= 4 (px.rect:x anchored)))
                     (is (= 2 (px.rect:y anchored)))
                     (is (= 2 (px.rect:x (px.sdl2.video:image-get-rect leaf)))))
                   (let ((copy (px.sdl2.video:image-source-rect leaf)))
                     (setf (px.rect:x copy) 99)
                     (is (= 2 (px.rect:x (px.sdl2.video:image-source-rect leaf)))))
                   ;; Setter and draw-time source are relative to this view's bounds.
                   (setf (px.sdl2.video:image-source-rect leaf) '(2 0 1 1))
                   (signals error (setf (px.sdl2.video:image-source-rect leaf) '(4 0 1 1)))
                   (setf (px.sdl2.video:image-source-rect leaf) '(2 0 2 1)
                         (px.sdl2.video:image-color leaf) #(255 128 255)
                         (px.sdl2.video:image-alpha leaf) 128
                         (px.sdl2.video:image-blend-mode leaf) :add)
                   (px.sdl2.video:clear renderer '(0 0 0 255))
                   (px.sdl2.video:draw-image renderer leaf :destination '(3 1 2 1))
                   (px.sdl2.video:draw-image renderer leaf :destination '(0 1))
                   (setf pixels (px.sdl2.video:to-surface renderer))
                   (let ((drawn (px.color:to-list (px.surface:get-at pixels '(3 1)))))
                     ;; RGB tint, then alpha modulation, then additive blending.
                     ;; Allow one byte of backend-specific rounding.
                     (is (<= 4 (first drawn) 6))
                     (is (<= 54 (second drawn) 56))
                     (is (<= 14 (third drawn) 16))
                     (is (equal drawn (px.color:to-list (px.surface:get-at pixels '(0 1))))))
                   (is (equal '(0 0 0 255)
                              (px.color:to-list (px.surface:get-at pixels '(2 1)))))
                   ;; Drawing a view temporarily changes and then restores the shared texture.
                   (is (equal '(255 255 255) (px.sdl2.video:texture-color texture)))
                   (is (= 255 (px.sdl2.video:texture-alpha texture)))
                   (is (eq :blend (px.sdl2.video:texture-blend-mode texture)))
                   ;; Errors after the view modifiers are applied must restore shared state too.
                   (signals error (px.sdl2.video:draw-image renderer leaf :destination '(0 0 1)))
                   (is (equal '(255 255 255) (px.sdl2.video:texture-color texture)))
                   (is (= 255 (px.sdl2.video:texture-alpha texture)))
                   (is (eq :blend (px.sdl2.video:texture-blend-mode texture)))
                   (signals error (px.sdl2.video:draw-image renderer leaf :source '(2 0 1 1))))
                 (signals error (px.sdl2.video:make-image texture '(4 0 1 1))))
            (when pixels (px.surface:dispose pixels))
            (when texture (px.sdl2.video:close texture))
            (px.surface:dispose surface)))))))

(test image-options-validation-owner-and-texture-lifetime
  (px:with-init (:video t)
    (px.sdl2.video:with-window (first-window :size '(3 3) :hidden t)
      (px.sdl2.video:with-window (second-window :size '(3 3) :hidden t)
        (px.sdl2.video:with-renderer (first-renderer first-window)
          (px.sdl2.video:with-renderer (second-renderer second-window)
            (let* ((texture (px.sdl2.video:make-texture first-renderer '(2 2)))
                   (replacement (px.sdl2.video:make-texture second-renderer '(2 2)))
                   (image (px.sdl2.video:make-image texture)))
              (unwind-protect
                   (progn
                     (setf (px.sdl2.video:image-angle image) 45
                           (px.sdl2.video:image-origin image) '(1 1)
                           (px.sdl2.video:image-flip-x image) t
                           (px.sdl2.video:image-flip-y image) nil
                           (px.sdl2.video:image-color image) '(1 2 3)
                           (px.sdl2.video:image-alpha image) 128
                           (px.sdl2.video:image-blend-mode image) :add)
                     (is (eq texture (px.sdl2.video:image-texture image)))
                     (signals error (setf (px.sdl2.video:image-texture image) replacement))
                     (is (= 45d0 (px.sdl2.video:image-angle image)))
                     (is (equal '(1 1) (px.sdl2.video:image-origin image)))
                     (is (px.sdl2.video:image-flip-x image))
                     (is (not (px.sdl2.video:image-flip-y image)))
                     (signals type-error (setf (px.sdl2.video:image-angle image) "90"))
                     (signals type-error (setf (px.sdl2.video:image-color image) '(1 2 256)))
                     (signals type-error (setf (px.sdl2.video:image-alpha image) 300))
                     (signals type-error (setf (px.sdl2.video:image-flip-x image) :yes))
                     (signals type-error (setf (px.sdl2.video:image-blend-mode image) :bad))
                     (signals type-error (setf (px.sdl2.video:image-origin image) '(1 2 3)))
                     (signals px:error (px.sdl2.video:draw-image second-renderer image))
                     (px.sdl2.video:close texture)
                     ;; The view retains the wrapper, but closing its texture owner invalidates it.
                     (signals px:disposed-resource (px.sdl2.video:image-get-rect image)))
                (px.sdl2.video:close texture)
                (px.sdl2.video:close replacement)))))))))
