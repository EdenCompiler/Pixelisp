(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test texture-update-area-format-conversion-and-lifetime
  (px:with-init (:video t)
    (px.sdl2.video:with-window (window :size '(8 4) :hidden t)
      (px.sdl2.video:with-renderer (renderer window)
        (let ((texture (px.sdl2.video:make-texture renderer '(3 1)))
              (source (px.surface:make-surface '(3 1) :alpha t))
              (readback nil))
          (unwind-protect
               (progn
                 ;; make-surface uses different masks from RGBA32 texture storage,
                 ;; so this exercises SDL format conversion as well as upload.
                 (px.surface:fill source '(15 25 35 255))
                 (px.sdl2.video:update-texture texture source)
                 (px.surface:set-at source '(0 0) '(20 210 70 255))
                 (px.sdl2.video:update-texture texture source :area '(1 0 1 1))
                 (px.sdl2.video:clear renderer '(0 0 0 255))
                 (px.sdl2.video:draw-texture renderer texture :destination '(0 0 3 1))
                 (setf readback (px.sdl2.video:to-surface renderer))
                 (is (equal '(20 210 70 255)
                            (px.color:to-list (px.surface:get-at readback '(1 0)))))
                 (is (equal '(15 25 35 255)
                            (px.color:to-list (px.surface:get-at readback '(0 0)))))
                 (signals error (px.sdl2.video:update-texture texture source :area '(3 0 1 1)))
                 (signals error (px.sdl2.video:update-texture texture source :area '(0 0 4 1)))
                 (px.surface:lock source)
                 (signals px:resource-in-use
                   (px.sdl2.video:update-texture texture source :area '(0 0 1 1)))
                 (signals px:resource-in-use (px.surface:dispose source))
                 (px.surface:unlock source)
                 (is (eq :blend (setf (px.sdl2.video:texture-blend-mode texture) :blend)))
                 (is (eq :blend (px.sdl2.video:texture-blend-mode texture)))
                 (signals type-error (px.sdl2.video:texture-blend-mode renderer))
                 (signals type-error (setf (px.sdl2.video:texture-blend-mode renderer) :blend))
                 (is (equal '(0 0 3 1)
                            (list (px.rect:x (px.sdl2.video:texture-get-rect texture))
                                  (px.rect:y (px.sdl2.video:texture-get-rect texture))
                                  (px.rect:width (px.sdl2.video:texture-get-rect texture))
                                  (px.rect:height (px.sdl2.video:texture-get-rect texture)))))
                 (is (= 9 (px.rect:x (px.sdl2.video:texture-get-rect texture :center '(10 5)))))
                 (signals error (px.sdl2.video:texture-get-rect texture :bogus 2))
                 (px.sdl2.video:close texture)
                 (signals px:disposed-resource (px.sdl2.video:texture-blend-mode texture))
                 (signals px:disposed-resource
                   (setf (px.sdl2.video:texture-blend-mode texture) :none)))
            (when readback (px.surface:dispose readback))
            (px.sdl2.video:close texture)
            (px.surface:dispose source)))))))

(test texture-draw-origin-and-owner-check
  (px:with-init (:video t)
    (px.sdl2.video:with-window (window :size '(8 8) :hidden t)
      (px.sdl2.video:with-renderer (renderer window)
        (let ((surface (px.surface:make-surface '(2 1) :alpha t))
              (texture nil))
          (unwind-protect
               (progn
                 (px.surface:fill surface '(255 0 0 255))
                 (setf texture (px.sdl2.video:texture-from-surface renderer surface))
                 ;; A corner pivot turns this horizontal strip vertical.
                 (px.sdl2.video:clear renderer '(0 0 0 255))
                 (px.sdl2.video:draw-texture renderer texture
                                              :destination '(2 2 2 1) :angle 90 :origin '(0 0))
                 (let ((pixels (px.sdl2.video:to-surface renderer)))
                   (unwind-protect
                        (is (equal '(255 0 0 255)
                                   (px.color:to-list (px.surface:get-at pixels '(1 3))))
                     (px.surface:dispose pixels))))
            (when texture (px.sdl2.video:close texture))
            (px.surface:dispose surface))))))))

(test texture-update-converts-bgra-source
  (px:with-init (:video t)
    (px.sdl2.video:with-window (window :size '(2 1) :hidden t)
      (px.sdl2.video:with-renderer (renderer window)
        (cffi:with-foreign-object (memory :uint8 4)
          (dotimes (i 4) (setf (cffi:mem-aref memory :uint8 i) 0))
          (let ((source (px.image:from-buffer memory '(1 1) :bgra :byte-count 4))
                (texture (px.sdl2.video:make-texture renderer '(1 1)))
                (pixels nil))
            (unwind-protect
                 (progn
                   (px.surface:set-at source '(0 0) '(9 80 230 255))
                   (px.sdl2.video:update-texture texture source)
                   (px.sdl2.video:clear renderer '(0 0 0 255))
                   (px.sdl2.video:draw-texture renderer texture :destination '(0 0 1 1))
                   (setf pixels (px.sdl2.video:to-surface renderer))
                   (is (equal '(9 80 230 255)
                              (px.color:to-list (px.surface:get-at pixels '(0 0))))))
              (when pixels (px.surface:dispose pixels))
              (px.sdl2.video:close texture)
              (px.surface:dispose source))))))))

(test draw-texture-rejects-foreign-renderer
  (px:with-init (:video t)
    (px.sdl2.video:with-window (first-window :size '(2 2) :hidden t)
      (px.sdl2.video:with-window (second-window :size '(2 2) :hidden t)
        (px.sdl2.video:with-renderer (first-renderer first-window)
          (px.sdl2.video:with-renderer (second-renderer second-window)
            (let ((texture (px.sdl2.video:make-texture first-renderer '(1 1))))
              (unwind-protect
                   (signals px:error
                     (px.sdl2.video:draw-texture second-renderer texture))
                (px.sdl2.video:close texture)))))))))
