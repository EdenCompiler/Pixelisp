;;;; Renderer state and readback, kept separate from software window surfaces.
;;;; SDL owns the drawing state; Lisp wrappers retain textures and validate
;;;; ownership before passing handles to C. Loaded after sdl2-ext.lisp.
(in-package #:pixelisp.sdl2.video)

(cffi:defcfun ("SDL_GetRenderTarget" %rt-get-target) :pointer (renderer :pointer))
(cffi:defcfun ("SDL_SetRenderTarget" %rt-set-target) :int (renderer :pointer) (texture :pointer))
(cffi:defcfun ("SDL_RenderTargetSupported" %rt-target-supported) :int (renderer :pointer))
(cffi:defcfun ("SDL_RenderGetViewport" %rt-get-viewport) :void (renderer :pointer) (rect :pointer))
(cffi:defcfun ("SDL_RenderSetViewport" %rt-set-viewport) :int (renderer :pointer) (rect :pointer))
(cffi:defcfun ("SDL_RenderGetLogicalSize" %rt-get-logical-size) :void (renderer :pointer) (w :pointer) (h :pointer))
(cffi:defcfun ("SDL_RenderSetLogicalSize" %rt-set-logical-size) :int (renderer :pointer) (w :int) (h :int))
(cffi:defcfun ("SDL_RenderGetScale" %rt-get-scale) :void (renderer :pointer) (x :pointer) (y :pointer))
(cffi:defcfun ("SDL_RenderSetScale" %rt-set-scale) :int (renderer :pointer) (x :float) (y :float))
(cffi:defcfun ("SDL_GetRenderDrawBlendMode" %rt-get-blend) :int (renderer :pointer) (mode :pointer))
(cffi:defcfun ("SDL_RenderDrawRect" %rt-draw-rect) :int (renderer :pointer) (rect :pointer))
(cffi:defcfun ("SDL_RenderReadPixels" %rt-read-pixels) :int
  (renderer :pointer) (rect :pointer) (format :uint32) (pixels :pointer) (pitch :int))
(cffi:defcfun ("SDL_QueryTexture" %rt-query-texture) :int
  (texture :pointer) (format :pointer) (access :pointer) (w :pointer) (h :pointer))
(cffi:defcfun ("SDL_GetRendererOutputSize" %rt-output-size) :int
  (renderer :pointer) (w :pointer) (h :pointer))

(defparameter +rt-blend-modes+ '((:none . 0) (:blend . 1) (:add . 2) (:mod . 4) (:mul . 8)))
(defun %rt-pointer (renderer)
  (check-type renderer renderer)
  (%pointer renderer))

(defun target-supported-p (renderer)
  "Return whether this renderer backend can draw into target textures."
  (pixelisp.internal:with-native-context (plusp (%rt-target-supported (%rt-pointer renderer)))))

(defun %rt-find-texture (renderer pointer)
  (find-if (lambda (child)
            (and (typep child 'texture)
                 (not (pixelisp.internal:resource-disposed-p child))
                 (cffi:pointer-eq (pixelisp.internal:handle child) pointer)))
          (%children renderer)))

(defun target (renderer)
  "Return the current target texture, or NIL when drawing to the window."
  (pixelisp.internal:with-native-context
    (%rt-find-texture renderer (%rt-get-target (%rt-pointer renderer)))))

(defun (setf target) (value renderer)
  "Set RENDERER's target to an owned target-access texture, or NIL for its window."
  (pixelisp.internal:with-native-context
    (let ((pointer (%rt-pointer renderer)))
      (when value
        (check-type value texture)
        (unless (eq renderer (%parent value))
          (error 'pixelisp:error :operation 'target
                 :message "Texture belongs to a different renderer."))
        (cffi:with-foreign-object (access :int)
          (pixelisp.devices.internal:check-code
           (%rt-query-texture (%pointer value) (cffi:null-pointer) access
                              (cffi:null-pointer) (cffi:null-pointer)) 'target)
          ;; SDL_TEXTUREACCESS_TARGET is 2; static/streaming textures cannot
          ;; be render targets even when they belong to this renderer.
          (unless (= (cffi:mem-ref access :int) 2)
            (error 'pixelisp:error :operation 'target
                   :message "Texture was not created with :TARGET access."))))
      (pixelisp.devices.internal:check-code
       (%rt-set-target pointer (if value (%pointer value) (cffi:null-pointer))) 'target))
    value))

(defmethod pixelisp.internal:dispose :before ((object texture))
  ;; Never leave SDL pointing at storage that is about to be destroyed.
  (pixelisp.internal:with-native-context
    (let ((owner (%parent object)))
      (when (and (typep owner 'renderer)
                 (not (pixelisp.internal:resource-disposed-p owner))
                 (cffi:pointer-eq (%rt-get-target (%pointer owner))
                                  (pixelisp.internal:handle object)))
        (pixelisp.devices.internal:check-code
         (%rt-set-target (%pointer owner) (cffi:null-pointer)) 'dispose-target)))))

(defmacro with-render-target ((renderer texture) &body body)
  "Run BODY with TEXTURE active, restoring the previous target on every exit."
  (let ((r (gensym "RENDERER")) (previous (gensym "PREVIOUS")))
    `(let* ((,r ,renderer)
            (,previous (target ,r)))
       (setf (target ,r) ,texture)
       (unwind-protect (progn ,@body)
         (when (not (pixelisp.internal:resource-disposed-p ,r))
           (setf (target ,r) (if (and ,previous (not (pixelisp.internal:resource-disposed-p ,previous))) ,previous nil)))))))

(defun viewport (renderer)
  "Return the renderer viewport as (X Y WIDTH HEIGHT)."
  (pixelisp.internal:with-native-context
    (cffi:with-foreign-object (rect '(:struct native-rect))
      (%rt-get-viewport (%rt-pointer renderer) rect)
      (loop for slot in '(x y w h) collect (cffi:foreign-slot-value rect '(:struct native-rect) slot)))))
(defun get-viewport (renderer) (viewport renderer))

(defun (setf viewport) (value renderer)
  "Set the renderer viewport, or reset it to the full target with NIL."
  (pixelisp.internal:with-native-context
   (let ((p (%rt-pointer renderer)))
    (if value
        (cffi:with-foreign-object (rect '(:struct native-rect))
          (%put-rect rect value)
          (pixelisp.devices.internal:check-code (%rt-set-viewport p rect) 'viewport))
        (pixelisp.devices.internal:check-code (%rt-set-viewport p (cffi:null-pointer)) 'viewport)))
   value))
(defun set-viewport (renderer &optional value) (setf (viewport renderer) value))

(defun logical-size (renderer)
  "Return the renderer logical size, or (0 0) when logical sizing is disabled."
  (pixelisp.internal:with-native-context
    (cffi:with-foreign-objects ((w :int) (h :int))
      (%rt-get-logical-size (%rt-pointer renderer) w h)
      (list (cffi:mem-ref w :int) (cffi:mem-ref h :int)))))
(defun (setf logical-size) (value renderer)
  "Set logical dimensions from a pair, or pass (0 0) to disable logical sizing."
  (multiple-value-bind (w h) (pixelisp.internal:pair value)
    (unless (and (integerp w) (integerp h) (>= w 0) (>= h 0)
                 (or (and (zerop w) (zerop h)) (and (plusp w) (plusp h))))
      (error 'type-error :datum value :expected-type '(or (cons (integer 1 *) (cons (integer 1 *) null)) (eql (0 0)))))
    (pixelisp.internal:with-native-context
      (pixelisp.devices.internal:check-code (%rt-set-logical-size (%rt-pointer renderer) w h) 'logical-size)))
  value)

(defun renderer-scale (renderer)
  "Return the renderer's X and Y drawing scale."
  (pixelisp.internal:with-native-context
    (cffi:with-foreign-objects ((x :float) (y :float))
      (%rt-get-scale (%rt-pointer renderer) x y)
      (list (cffi:mem-ref x :float) (cffi:mem-ref y :float)))))
(defun (setf renderer-scale) (value renderer)
  "Set positive renderer scale factors from a pair."
  (multiple-value-bind (x y) (pixelisp.internal:pair value)
    (unless (and (realp x) (realp y) (plusp x) (plusp y))
      (error 'type-error :datum value :expected-type '(cons (real 0 *) (cons (real 0 *) null))))
    (pixelisp.internal:with-native-context
      (pixelisp.devices.internal:check-code (%rt-set-scale (%rt-pointer renderer) (coerce x 'single-float) (coerce y 'single-float)) 'renderer-scale)))
  value)

(defun draw-blend-mode (renderer)
  "Return the SDL draw blend mode as :NONE, :BLEND, :ADD, :MOD, :MUL, or its integer value."
  (pixelisp.internal:with-native-context
    (cffi:with-foreign-object (mode :int)
      (pixelisp.devices.internal:check-code (%rt-get-blend (%rt-pointer renderer) mode) 'draw-blend-mode)
      (let ((n (cffi:mem-ref mode :int))) (or (car (rassoc n +rt-blend-modes+)) n)))))
(defun (setf draw-blend-mode) (value renderer)
  "Set SDL's renderer draw blend mode from a supported keyword or SDL integer."
  (let ((mode (if (integerp value) value (or (cdr (assoc value +rt-blend-modes+))
                                             (error 'type-error :datum value :expected-type '(member :none :blend :add :mod :mul))))))
    (pixelisp.internal:with-native-context
      (pixelisp.devices.internal:check-code (%blend-set (%rt-pointer renderer) mode) 'draw-blend-mode)))
  value)

(defun draw-rect (renderer rect)
  "Draw the outline of RECT with the renderer's current draw color."
  (pixelisp.internal:with-native-context
    (cffi:with-foreign-object (p '(:struct native-rect))
      (%put-rect p rect)
      (pixelisp.devices.internal:check-code (%rt-draw-rect (%rt-pointer renderer) p) 'draw-rect)) renderer))

(defun to-surface (renderer &key surface area)
  "Read the current target into a new owned RGBA surface, or overwrite SURFACE.
AREA is in physical target pixels and must lie inside the target. A supplied
surface must have matching dimensions, 32-bit pixels, and no active locks.
SDL writes only the intersection with the renderer's physical viewport;
unread destination pixels are preserved (transparent in a new surface)."
  (pixelisp.internal:with-native-context
    (let* ((pointer (%rt-pointer renderer))
           (active (target renderer))
           (size (if active (texture-size active)
                     (cffi:with-foreign-objects ((w :int) (h :int))
                       (pixelisp.devices.internal:check-code
                        (%rt-output-size pointer w h) 'to-surface)
                       (list (cffi:mem-ref w :int) (cffi:mem-ref h :int)))))
           (rect (pixelisp.internal:as-rect
                  (or area (list 0 0 (first size) (second size)))))
           (x (px.rect:x rect)) (y (px.rect:y rect))
           (w (px.rect:width rect)) (h (px.rect:height rect)))
      (unless (and (plusp w) (plusp h) (<= 0 x) (<= 0 y)
                   (<= (+ x w) (first size)) (<= (+ y h) (second size)))
        (error "Readback area ~S is outside the renderer target ~S." rect size))
      (let ((out (or surface (pixelisp.surface:make-surface (list w h) :alpha t)))
            (complete nil))
        (unwind-protect
             (progn
               (check-type out pixelisp.surface:surface)
               (pixelisp.internal:ensure-live out)
               (unless (and (= (pixelisp.surface:width out) w)
                            (= (pixelisp.surface:height out) h))
                 (error "Destination surface must be ~Dx~D." w h))
               (unless (= (pixelisp.surface:get-bytesize out) 4)
                 (error "Destination surface must use 32-bit pixels."))
               (when (pixelisp.surface:locked-p out)
                 (error 'pixelisp:resource-in-use :operation 'to-surface
                        :message "Destination surface is already locked."))
               (cffi:with-foreign-object (native '(:struct native-rect))
                 (%put-rect native rect)
                 ;; SDL converts into the actual destination format. The pixel
                 ;; pointer includes a subsurface's offset; pitch respects its
                 ;; parent's padded rows. Lock once for the whole native copy.
                 (let* ((handle (pixelisp.internal:surface-handle out))
                        (format (plus-c:c-ref handle sdl2-ffi:sdl-surface :format :format)))
                   (pixelisp.surface:lock out)
                   (unwind-protect
                        (pixelisp.devices.internal:check-code
                         (%rt-read-pixels pointer native format (sdl2:surface-pixels handle)
                                          (sdl2:surface-pitch handle)) 'to-surface)
                     (pixelisp.surface:unlock out))))
               (setf complete t)
               out)
          ;; Supplied destinations belong to the caller, including on failure.
          (when (and (not complete) (null surface))
            (pixelisp.surface:dispose out)))))))
