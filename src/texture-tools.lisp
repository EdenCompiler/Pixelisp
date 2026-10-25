;;;; Small pygame-style helpers for SDL2 textures.
(in-package #:pixelisp.sdl2.video)

(cffi:defcstruct tx-surface-prefix
  (flags :uint32) (format :pointer) (w :int) (h :int) (pitch :int) (pixels :pointer))

(cffi:defcfun ("SDL_UpdateTexture" %tx-update) :int
  (texture :pointer) (rect :pointer) (pixels :pointer) (pitch :int))
(cffi:defcfun ("SDL_GetTextureBlendMode" %tx-blend-get) :int
  (texture :pointer) (blend :pointer))
(cffi:defcfun ("SDL_GetSurfaceBlendMode" %tx-surface-blend-get) :int
  (surface :pointer) (blend :pointer))
(cffi:defcfun ("SDL_SetSurfaceBlendMode" %tx-surface-blend-set) :int
  (surface :pointer) (blend :int))
(cffi:defcfun ("SDL_AllocFormat" %tx-format-alloc) :pointer (format :uint32))
(cffi:defcfun ("SDL_FreeFormat" %tx-format-free) :void (format :pointer))
(cffi:defcfun ("SDL_ConvertSurface" %tx-surface-convert) :pointer
  (surface :pointer) (format :pointer) (flags :uint32))
(cffi:defcfun ("SDL_FreeSurface" %tx-surface-free) :void (surface :pointer))

(defun texture-get-rect (texture &rest anchors)
  "Return a texture-sized rectangle positioned by pygame-style anchor pairs."
  (check-type texture texture)
  (let ((r (apply #'px.rect:make-rect 0 0 (texture-size texture)))
        (known '(:top-left :topleft :top-right :topright
                 :bottom-left :bottomleft :bottom-right :bottomright
                 :mid-top :midtop :mid-left :midleft :mid-bottom :midbottom
                 :mid-right :midright :left :x :top :y :right :bottom
                 :center-x :centerx :center-y :centery :center)))
    (unless (evenp (length anchors)) (error "TEXTURE-GET-RECT expects anchor/value pairs."))
    (loop for (key value) on anchors by #'cddr do
      (unless (member key known) (error "Unknown texture rectangle anchor ~S." key))
      (case key
        ((:top-left :topleft) (setf (px.rect:top-left r) value))
        ((:top-right :topright) (setf (px.rect:top-right r) value))
        ((:bottom-left :bottomleft) (setf (px.rect:bottom-left r) value))
        ((:bottom-right :bottomright) (setf (px.rect:bottom-right r) value))
        ((:mid-top :midtop) (setf (px.rect:mid-top r) value))
        ((:mid-left :midleft) (setf (px.rect:mid-left r) value))
        ((:mid-bottom :midbottom) (setf (px.rect:mid-bottom r) value))
        ((:mid-right :midright) (setf (px.rect:mid-right r) value))
        ((:left :x) (setf (px.rect:left r) (truncate value)))
        ((:top :y) (setf (px.rect:top r) (truncate value)))
        (:right (setf (px.rect:right r) (truncate value)))
        (:bottom (setf (px.rect:bottom r) (truncate value)))
        ((:center-x :centerx) (setf (px.rect:center-x r) (truncate value)))
        ((:center-y :centery) (setf (px.rect:center-y r) (truncate value)))
        (:center (setf (px.rect:center r) value))))
    r))

(defun texture-blend-mode (texture)
  "Return TEXTURE's SDL blend mode as :NONE, :BLEND, :ADD, :MOD, :MUL, or an integer."
  (pixelisp.internal:with-native-context
    (check-type texture texture)
    (cffi:with-foreign-object (mode :int)
      (pixelisp.devices.internal:check-code
       (%tx-blend-get (%pointer texture) mode) 'texture-blend-mode)
      (let ((n (cffi:mem-ref mode :int)))
        (or (car (rassoc n '((:none . 0) (:blend . 1) (:add . 2) (:mod . 4) (:mul . 8)) :test #'eql)) n)))))

(defun (setf texture-blend-mode) (mode texture)
  "Set TEXTURE's SDL blend mode from a keyword or SDL_BlendMode integer."
  (check-type texture texture)
  (let ((value mode)
        (code (if (integerp mode) mode
                  (or (cdr (assoc mode '((:none . 0) (:blend . 1) (:add . 2) (:mod . 4) (:mul . 8))))
                      (error 'type-error :datum mode :expected-type '(member :none :blend :add :mod :mul))))))
    (pixelisp.internal:with-native-context
      (pixelisp.devices.internal:check-code
       (%texture-blend (%pointer texture) code) 'texture-blend-mode))
    value))

(defun update-texture (texture surface &key area)
  "Copy SURFACE pixels into TEXTURE. AREA selects the destination rectangle;
the source pixels begin at SURFACE's top-left, matching pygame 2.6.1."
  (pixelisp.internal:with-native-context
    (check-type texture texture)
    (unless (typep surface 'px.surface:surface)
      (error 'type-error :datum surface :expected-type 'px.surface:surface))
    (when (px.surface:locked-p surface)
      (error 'pixelisp:resource-in-use :operation 'update-texture
             :message "Updating from a locked surface is not allowed."))
    ;; Validate the resource before querying dimensions or calling SDL.
    (pixelisp.internal:surface-handle surface)
    (let* ((w (px.surface:width surface)) (h (px.surface:height surface))
           (rect (when area (pixelisp.internal:as-rect area)))
           (tw (first (texture-size texture))) (th (second (texture-size texture))))
      (unless rect (setf rect (px.rect:make-rect 0 0 tw th)))
      (when (or (minusp (px.rect:x rect)) (minusp (px.rect:y rect))
                (not (plusp (px.rect:width rect))) (not (plusp (px.rect:height rect)))
                (> (+ (px.rect:x rect) (px.rect:width rect)) tw)
                (> (+ (px.rect:y rect) (px.rect:height rect)) th)
                (> (px.rect:width rect) w) (> (px.rect:height rect) h))
        (error "Texture update area ~S is outside the texture or source surface." rect))
      (let* ((src (pixelisp.internal:%ptr (pixelisp.internal:surface-handle surface)))
             (converted (cffi:null-pointer)) (pixel-format (cffi:null-pointer))
             (source src) (locked nil))
        (cffi:with-foreign-objects ((format :uint32) (blend :int))
          (unwind-protect
             (progn
               (px.surface:lock surface) (setf locked t)
               (pixelisp.devices.internal:check-code
                (%texture-query (%pointer texture) format (cffi:null-pointer) (cffi:null-pointer) (cffi:null-pointer))
                'update-texture)
               (let ((surface-format
                       (cffi:mem-ref (cffi:foreign-slot-value src '(:struct tx-surface-prefix) 'format)
                                     :uint32)))
                 (unless (= (cffi:mem-ref format :uint32) surface-format)
                   (pixelisp.devices.internal:check-code (%tx-surface-blend-get src blend) 'update-texture)
                   (setf pixel-format (%tx-format-alloc (cffi:mem-ref format :uint32)))
                   (when (cffi:null-pointer-p pixel-format) (pixelisp.internal:native-error 'update-texture))
                   (setf converted (%tx-surface-convert src pixel-format 0))
                   (when (cffi:null-pointer-p converted) (pixelisp.internal:native-error 'update-texture))
                   (pixelisp.devices.internal:check-code
                    (%tx-surface-blend-set converted (cffi:mem-ref blend :int)) 'update-texture)
                   (setf source converted)))
               (cffi:with-foreign-object (native '(:struct native-rect))
                 (%put-rect native rect)
                 (pixelisp.devices.internal:check-code
                  (%tx-update (%pointer texture) native
                              (cffi:foreign-slot-value source '(:struct tx-surface-prefix) 'pixels)
                              (cffi:foreign-slot-value source '(:struct tx-surface-prefix) 'pitch))
                  'update-texture)))
            (when locked (px.surface:unlock surface))
            (unless (cffi:null-pointer-p converted) (%tx-surface-free converted))
            (unless (cffi:null-pointer-p pixel-format) (%tx-format-free pixel-format)))))
    texture)))
