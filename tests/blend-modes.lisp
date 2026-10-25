(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test custom-blend-mode-encoding-and-validation
  ;; SDL canonicalizes the standard no-blend and alpha-blend combinations.
  (is (= 0 (px.sdl2.video:compose-custom-blend-mode
            '(:one :zero :add) '(:one :zero :add))))
  (is (= 1 (px.sdl2.video:compose-custom-blend-mode
            '(:src-alpha :one-minus-src-alpha :add)
            '(:one :one-minus-src-alpha :add))))
  ;; A noncanonical mode preserves the SDL packed enum bits. Verified against
  ;; SDL_ComposeCustomBlendMode via ctypes using enum values from SDL2 headers.
  (is (= #x01220121
         (px.sdl2.video:compose-custom-blend-mode
          #(:one :zero :add) #(:one :zero :subtract))))
  (is (= #x01220121
         (px.sdl2.video:compose-custom-blend-mode
          '(2 1 1) '(2 1 2))))
  (is (= #x01210252
         (px.sdl2.video:compose-custom-blend-mode
          '(:src-alpha :one :subtract) '(:one :zero :add))))
  (signals type-error
    (px.sdl2.video:compose-custom-blend-mode '(:bad :zero :add) '(:one :zero :add)))
  (signals type-error
    (px.sdl2.video:compose-custom-blend-mode '(:one :zero :add :add) '(:one :zero :add)))
  (signals type-error
    (px.sdl2.video:compose-custom-blend-mode '(:one :zero :add) '(:one :zero 42))))

(test renderer-drivers-and-instance-info
  (px:with-init (:video t)
    (let ((drivers (px.sdl2.video:get-drivers)))
      (is (listp drivers))
      (when drivers
        (is (stringp (getf (first drivers) :name)))
        (is (integerp (getf (first drivers) :flags)))
        (is (listp (getf (first drivers) :texture-formats)))
        (is (integerp (getf (first drivers) :max-texture-width)))
        (is (integerp (getf (first drivers) :max-texture-height))))))
  (px:with-init (:video t)
    (px.sdl2.video:with-window (window :size '(8 8) :hidden t)
      (signals type-error (px.sdl2.video:get-renderer-info window))
      (px.sdl2.video:with-renderer (renderer window)
        (let ((info (px.sdl2.video:get-renderer-info renderer)))
          (is (stringp (getf info :name)))
          (is (integerp (getf info :flags)))
          (is (listp (getf info :texture-formats))))))))

(test custom-blend-mode-renders-when-backend-supports-it
  (px:with-init (:video t)
    (px.sdl2.video:with-window (window :size '(4 4) :hidden t)
      (px.sdl2.video:with-renderer (renderer window :accelerated
                                       (not (null (uiop:getenv "PIXELISP_TEST_X11"))))
        (block supported-renderer
          (let ((mode (px.sdl2.video:compose-custom-blend-mode
                       '(:one :one-minus-src-alpha :add)
                       '(:one :one-minus-src-alpha :add))))
            ;; SDL renderer backends vary in custom blend support.
            (handler-case
                (setf (px.sdl2.video:draw-blend-mode renderer) mode)
              (px:error ()
                (skip "This SDL renderer does not support the custom blend mode.")
                (return-from supported-renderer nil)))
            (px.sdl2.video:clear renderer '(20 40 60 255))
            ;; The source channels are already premultiplied by alpha.
            (setf (px.sdl2.video:draw-color renderer) '(100 20 40 128))
            (px.sdl2.video:fill-rect renderer '(0 0 4 4))
            (let ((copy (px.sdl2.video:to-surface renderer)))
              (unwind-protect
                   (is (equal '(110 40 70 255)
                              (px.color:to-list (px.surface:get-at copy '(1 1)))))
                (px.surface:dispose copy)))))))))

(test image-accepts-custom-blending-without-changing-shared-texture
  (px:with-init (:video t)
    (px.sdl2.video:with-window (window :size '(2 2) :hidden t)
      (px.sdl2.video:with-renderer (renderer window :accelerated
                                       (not (null (uiop:getenv "PIXELISP_TEST_X11"))))
        (px.surface:with-surface (source '(1 1) :alpha t)
          (px.surface:fill source '(100 20 40 128))
          (px:with-resource (texture (px.sdl2.video:texture-from-surface renderer source))
            (setf (px.sdl2.video:texture-color texture) '(200 220 240)
                  (px.sdl2.video:texture-alpha texture) 180)
            (let* ((image (px.sdl2.video:make-image texture))
                   (before (px.sdl2.video:texture-blend-mode texture))
                   (custom (px.sdl2.video:compose-custom-blend-mode
                             '(:one :one-minus-src-alpha :add)
                             '(:one :one-minus-src-alpha :add))))
              (is (= custom (setf (px.sdl2.video:image-blend-mode image) custom)))
              (signals type-error (setf (px.sdl2.video:image-blend-mode image) -1))
              (is (= custom (px.sdl2.video:image-blend-mode image)))
              (px.sdl2.video:clear renderer '(20 40 60 255))
              ;; A backend may reject the custom mode. In either case, image
              ;; drawing must restore all modifiers of the shared texture.
              (let ((supported
                      (unwind-protect
                           (handler-case
                               (progn (setf (px.sdl2.video:texture-blend-mode texture) custom) t)
                             (px:error () nil))
                        (setf (px.sdl2.video:texture-blend-mode texture) before))))
                (if supported
                    (progn
                      (px.sdl2.video:draw-image renderer image :destination '(0 0))
                      (px:with-resource (pixels (px.sdl2.video:to-surface renderer))
                        (is (equal '(110 40 70 255)
                                   (px.color:to-list (px.surface:get-at pixels '(0 0)))))))
                    (signals px:error
                      (px.sdl2.video:draw-image renderer image :destination '(0 0)))))
              (is (eql before (px.sdl2.video:texture-blend-mode texture)))
              (is (equal '(200 220 240) (px.sdl2.video:texture-color texture)))
              (is (= 180 (px.sdl2.video:texture-alpha texture))))))))))
