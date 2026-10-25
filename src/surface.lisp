;;;; Software surfaces and the small native adapter they need.
;;;;
;;;; An ordinary surface owns its SDL allocation. A subsurface owns only SDL
;;;; metadata and retains its parent. Locks propagate up that ownership chain,
;;;; preventing explicit disposal of pixels while a descendant view is in use.
(in-package #:pixelisp.internal)
(defun %ptr (object)
  (cond ((null object) (cffi:null-pointer))
        ((cffi:pointerp object) object)
        (t (autowrap:ptr object))))
(cffi:defcfun ("SDL_GetError" %get-error) :string)
(defun native-error (operation &optional message)
  (error 'pixelisp:initialization-error :operation operation
         :message (or message (%get-error))))
(cffi:defcstruct native-rect (x :int) (y :int) (w :int) (h :int))
(cffi:defcfun ("SDL_LockSurface" %lock-surface) :int (surface :pointer))
(cffi:defcfun ("SDL_UnlockSurface" %unlock-surface) :void (surface :pointer))
(cffi:defcfun ("SDL_MapRGBA" %map-rgba) :uint32 (format :pointer) (r :uint8) (g :uint8) (b :uint8) (a :uint8))
(cffi:defcfun ("SDL_GetRGBA" %get-rgba) :void (pixel :uint32) (format :pointer)
  (r :pointer) (g :pointer) (b :pointer) (a :pointer))
(cffi:defcfun ("SDL_PixelFormatEnumToMasks" %pixel-format-masks) :int
  (format :uint32) (bits :pointer) (r :pointer) (g :pointer) (b :pointer) (a :pointer))
(cffi:defcfun ("SDL_SetSurfaceBlendMode" %set-blend) :int (surface :pointer) (blend :int))
(cffi:defcfun ("SDL_SetSurfaceRLE" %set-surface-rle) :int (surface :pointer) (enabled :int))
(cffi:defcfun ("SDL_GetSurfaceBlendMode" %get-blend) :int (surface :pointer) (blend :pointer))
(cffi:defcfun ("SDL_SetClipRect" %set-clip) :int (surface :pointer) (rect :pointer))
(cffi:defcfun ("SDL_FillRect" %fill-rect) :int (surface :pointer) (rect :pointer) (color :uint32))
(cffi:defcfun ("SDL_UpperBlit" %blit) :int (source :pointer) (area :pointer) (target :pointer) (dest :pointer))
(cffi:defcfun ("SDL_CreateRGBSurfaceFrom" %surface-from) :pointer
  (pixels :pointer) (w :int) (h :int) (depth :int) (pitch :int)
  (r :uint32) (g :uint32) (b :uint32) (a :uint32))
(cffi:defcfun ("SDL_FreeSurface" %free-surface) :void (surface :pointer))
(cffi:defcfun ("SDL_CreateRGBSurfaceWithFormatFrom" %surface-from-format) :pointer
  (pixels :pointer) (w :int) (h :int) (depth :int) (pitch :int) (format :uint32))
(defmacro with-native-rect ((name rectangle) &body body)
  `(let ((value (as-rect ,rectangle)))
     (cffi:with-foreign-object (,name '(:struct native-rect))
       (setf (cffi:foreign-slot-value ,name '(:struct native-rect) 'x) (pixelisp:rect-x value)
             (cffi:foreign-slot-value ,name '(:struct native-rect) 'y) (pixelisp:rect-y value)
             (cffi:foreign-slot-value ,name '(:struct native-rect) 'w) (pixelisp:rect-width value)
             (cffi:foreign-slot-value ,name '(:struct native-rect) 'h) (pixelisp:rect-height value))
       ,@body)))

(in-package #:pixelisp.surface)
(defclass surface (pixelisp.internal:resource)
  ((width :initarg :width :reader width) (height :initarg :height :reader height)
   (alpha-p :initarg :alpha :initform nil :reader alpha-p)
   (owned-p :initarg :owned :initform t :reader owned-p)
   (parent :initarg :parent :initform nil :reader parent)
   (offset :initarg :offset :initform '(0 0) :reader surface-offset)
   (locks :initform 0 :accessor locks)
   (clip :initarg :clip :accessor clip-rect)
   (alpha :initform 255 :accessor alpha-value)
   (colorkey :initform nil :accessor colorkey)
   ;; This is the requested hint, as in pygame. SDL may temporarily turn
   ;; encoding off while pixels are accessed, so do not infer it from flags.
   (rle-hint :initform nil :accessor rle-hint)))
(defmethod pixelisp.internal:ensure-live :before ((object surface))
  ;; A subsurface owns only its SDL metadata. Its pixels belong to its parent.
  (when (typep (parent object) 'pixelisp.internal:resource)
    (pixelisp.internal:ensure-live (parent object))))
(defun check-surface (surface)
  (check-type surface surface)
  (pixelisp.internal:ensure-live surface)
  surface)
(defun pixelisp.internal:surface-handle (surface)
  (check-surface surface) (pixelisp.internal:handle surface))
(defun make-surface (size &key (alpha nil))
  "Create an owned 32-bit software image. ALPHA enables per-pixel transparency."
  (multiple-value-bind (w h) (pixelisp.internal:pair size)
    (check-type w (integer 1 *)) (check-type h (integer 1 *))
    (let* ((native (sdl2:create-rgb-surface w h 32 :r-mask #xff :g-mask #xff00
                                          :b-mask #xff0000 :a-mask (if alpha #xff000000 0)))
           (object (make-instance 'surface :handle native :width w :height h :alpha alpha
                                  :clip (pixelisp:make-rect 0 0 w h))))
      (when (cffi:null-pointer-p (pixelisp.internal::%ptr native))
        (pixelisp.internal:native-error 'make-surface))
      (pixelisp.internal::%set-blend (pixelisp.internal::%ptr native) (if alpha 1 0))
      (pixelisp.internal:register-resource object)
      (fill object (if alpha '(0 0 0 0) '(0 0 0))) object)))
(setf (fdefinition 'pixelisp:make-surface) #'make-surface)
(defun pixelisp.internal:wrap-surface (native &key (owned t) (alpha t) parent preserve-format)
  "Normalize a native image or retain its format. OWNED consumes it even on failure."
  (let ((raw (pixelisp.internal::%ptr native)))
    (when (cffi:null-pointer-p raw) (pixelisp.internal:native-error 'wrap-surface))
    ;; From here, this function is responsible for the input allocation. Cancel
    ;; binding finalizers before either transferring it or freeing it ourselves.
    (when (and owned (not (cffi:pointerp native)))
      (trivial-garbage:cancel-finalization native))
    (let ((wrapped (if (cffi:pointerp native)
                       (autowrap:wrap-pointer raw 'sdl2-ffi:sdl-surface) native))
          (result nil)
          (source-retained-p nil)
          (complete-p nil))
      (unwind-protect
           (progn
             (if preserve-format
                 ;; Foreign imports keep their owner's pixels, pitch and format.
                 (progn
                   (setf result
                         (make-instance 'surface :handle wrapped
                           :width (sdl2:surface-width wrapped) :height (sdl2:surface-height wrapped)
                           :alpha alpha :owned owned :parent parent
                           :clip (pixelisp:make-rect 0 0 (sdl2:surface-width wrapped)
                                                        (sdl2:surface-height wrapped))))
                   ;; The result owns RAW now, including if registration fails.
                   (setf source-retained-p t)
                   (pixelisp.internal:register-resource result))
                 (progn
                   (setf result (make-surface (list (sdl2:surface-width wrapped)
                                                          (sdl2:surface-height wrapped))
                                             :alpha alpha))
                   ;; Conversion must copy raw channels without applying source
                   ;; blending, modulation or color keys.
                   (let ((converted (sdl2:convert-surface-format wrapped :abgr8888)))
                     (unwind-protect
                          (dotimes (y (height result))
                            (dotimes (x (width result))
                              (let ((pixel (cffi:mem-ref
                                            (cffi:inc-pointer (sdl2:surface-pixels converted)
                                              (+ (* y (sdl2:surface-pitch converted)) (* x 4)))
                                            :uint32)))
                                (set-at result (list x y)
                                        (list (ldb (byte 8 0) pixel) (ldb (byte 8 8) pixel)
                                              (ldb (byte 8 16) pixel) (ldb (byte 8 24) pixel))))))
                       (sdl2:free-surface converted)))))
             (setf complete-p t)
             result)
        ;; A partial destination and the accepted input are separate allocations.
        ;; Free the input even if disposing the destination itself signals.
        (unwind-protect
             (unless complete-p
               (when result (pixelisp.internal:dispose result)))
          (when (and owned (not source-retained-p))
            (pixelisp.internal::%free-surface raw)))))))
(defmethod pixelisp.internal:dispose ((object surface))
  (when (plusp (locks object))
    (error 'pixelisp:resource-in-use :operation 'dispose :message "Close pixel views or unlock the surface first."))
  (when (owned-p object)
    (pixelisp.internal::%free-surface (pixelisp.internal::%ptr (pixelisp.internal:handle object)))))
(setf (fdefinition 'dispose) #'pixelisp.internal:dispose)
(defmacro with-surface ((name size &rest args) &body body)
  `(pixelisp:with-resource (,name (make-surface ,size ,@args)) ,@body))
(defun size (surface) (list (width surface) (height surface)))
(setf (fdefinition 'get-size) #'size (fdefinition 'get-width) #'width (fdefinition 'get-height) #'height)
(defun get-parent (surface)
  "Return the immediate parent of a subsurface, or NIL for independently owned images."
  (check-surface surface)
  ;; A foreign buffer import may retain a non-surface storage owner. It is not
  ;; a geometric parent and is deliberately hidden by this public query.
  (when (typep (parent surface) 'surface) (parent surface)))
(defun get-abs-parent (surface)
  "Return the top-level surface that owns this surface's pixel coordinates."
  (check-surface surface)
  (loop for current = surface then ancestor
        for ancestor = (get-parent current)
        while ancestor finally (return current)))
(defun get-offset (surface)
  "Return a fresh (x y) position inside the immediate parent, or (0 0)."
  (check-surface surface)
  (copy-list (surface-offset surface)))
(defun get-abs-offset (surface)
  "Return a fresh (x y) position relative to the top-level surface."
  (check-surface surface)
  (loop for current = surface then (get-parent current)
        while current
        sum (first (surface-offset current)) into x
        sum (second (surface-offset current)) into y
        finally (return (list x y))))
(defun get-pitch (surface)
  "Return the byte distance between adjacent rows, including inherited padding."
  (check-surface surface)
  (sdl2:surface-pitch (pixelisp.internal:handle surface)))
(defun %format-description (surface)
  "Read format metadata through SDL rather than assuming native C struct offsets."
  (check-surface surface)
  (cffi:with-foreign-objects ((bits :int) (r :uint32) (g :uint32) (b :uint32) (a :uint32))
    (when (zerop (pixelisp.internal::%pixel-format-masks
                  (plus-c:c-ref (pixelisp.internal:handle surface) sdl2-ffi:sdl-surface :format :format)
                  bits r g b a))
      (pixelisp.internal:native-error 'get-masks))
    (values (cffi:mem-ref bits :int)
            (list (cffi:mem-ref r :uint32) (cffi:mem-ref g :uint32)
                  (cffi:mem-ref b :uint32) (cffi:mem-ref a :uint32)))))
(defun get-bitsize (surface)
  "Return the native pixel depth in bits; current public formats are all 32-bit."
  (nth-value 0 (%format-description surface)))
(defun get-bytesize (surface)
  "Return the number of storage bytes per pixel."
  (ceiling (get-bitsize surface) 8))
(defun get-masks (surface)
  "Return a fresh list of the packed red, green, blue, and alpha bit masks."
  (nth-value 1 (%format-description surface)))
(defun %mask-shift (mask)
  (if (zerop mask) 0
      (loop for shift from 0 below 32
            when (logbitp shift mask) return shift)))
(defun get-shifts (surface)
  "Return fresh (red green blue alpha) bit shifts from the native pixel layout."
  (mapcar #'%mask-shift (get-masks surface)))
(defun get-losses (surface)
  "Return fresh per-channel precision losses (8 minus channel mask bit count)."
  (mapcar (lambda (mask) (- 8 (logcount mask))) (get-masks surface)))
(defun get-blendmode (surface)
  "Return the native SDL blend mode as :NONE, :BLEND, :ADD, :MOD, or :MUL.
Unrecognized SDL modes are returned as their exact integer value."
  (check-surface surface)
  (cffi:with-foreign-object (mode :int)
    (when (minusp (pixelisp.internal::%get-blend
                   (pixelisp.internal::%ptr (pixelisp.internal:handle surface)) mode))
      (pixelisp.internal:native-error 'get-blendmode))
    (let ((mode (cffi:mem-ref mode :int)))
      (case mode (0 :none) (1 :blend) (2 :add) (4 :mod) (8 :mul) (otherwise mode)))))
(defun map-rgb (surface color)
  "Convert an RGB(A) color to this surface's native unsigned packed pixel value."
  (check-surface surface)
  (multiple-value-bind (r g b a) (pixelisp.internal:rgba color)
    (pixelisp.internal::%map-rgba
     (pixelisp.internal:%ptr (sdl2:surface-format (pixelisp.internal:handle surface))) r g b a)))
(defun unmap-rgb (surface pixel)
  "Convert a native packed pixel to a fresh Color; signed 32-bit values are accepted."
  (check-surface surface)
  (check-type pixel (integer -2147483648 4294967295))
  (cffi:with-foreign-objects ((r :uint8) (g :uint8) (b :uint8) (a :uint8))
    (pixelisp.internal::%get-rgba
     (ldb (byte 32 0) pixel)
     (pixelisp.internal:%ptr (sdl2:surface-format (pixelisp.internal:handle surface))) r g b a)
    (pixelisp:make-color (cffi:mem-ref r :uint8) (cffi:mem-ref g :uint8)
                         (cffi:mem-ref b :uint8) (cffi:mem-ref a :uint8))))
(defun get-rect (surface &rest anchor-args)
  "Return the surface rectangle positioned by any pygame Rect anchor keyword.
Accepts :TOPLEFT (the legacy spelling), :TOP-LEFT, and corresponding compact
or hyphenated spellings for other point anchors, plus scalar :X/:LEFT, :Y/:TOP,
:RIGHT/:BOTTOM, and :CENTER-X/:CENTER-Y anchors (also :CENTERX/:CENTERY).
Scalar real values are truncated to match Lisp rectangle setters. If several
anchors are given, they are applied in caller order; the last wins."
  (check-surface surface)
  (unless (evenp (length anchor-args))
    (error "GET-RECT expects anchor/value keyword pairs: ~S." anchor-args))
  (let ((points nil)
        (r (pixelisp:make-rect 0 0 (width surface) (height surface))))
    ;; Parse and validate every value first, so an invalid later anchor cannot
    ;; leave any observable partially positioned rectangle behind.
    (loop for (keyword value) on anchor-args by #'cddr do
      (unless (keywordp keyword) (error "GET-RECT anchor must be a keyword: ~S." keyword))
      (let* ((anchor (case keyword
                       ((:topleft :top-left) :topleft)
                       ((:topright :top-right) :topright)
                       ((:bottomleft :bottom-left) :bottomleft)
                       ((:bottomright :bottom-right) :bottomright)
                       ((:midtop :mid-top) :midtop)
                       ((:midleft :mid-left) :midleft)
                       ((:midbottom :mid-bottom) :midbottom)
                       ((:midright :mid-right) :midright)
                       ((:x :left) :left)
                       ((:y :top) :top)
                       (:right :right)
                       (:bottom :bottom)
                       ((:center-x :centerx) :center-x)
                       ((:center-y :centery) :center-y)
                       (:center :center)
                       (otherwise (error "Unknown GET-RECT anchor keyword ~S." keyword))))
             (position (if (member anchor '(:left :top :right :bottom :center-x :center-y))
                           (progn (check-type value real) (truncate value))
                           (multiple-value-list (pixelisp.internal:pair value)))))
        (push (cons anchor position) points)))
    (dolist (entry (nreverse points) r)
      (let ((point (cdr entry)))
        (ecase (car entry)
          (:topleft (setf (px.rect:top-left r) point))
          (:topright (setf (px.rect:top-right r) point))
          (:bottomleft (setf (px.rect:bottom-left r) point))
          (:bottomright (setf (px.rect:bottom-right r) point))
          (:midtop (setf (px.rect:mid-top r) point))
          (:midleft (setf (px.rect:mid-left r) point))
          (:midbottom (setf (px.rect:mid-bottom r) point))
          (:midright (setf (px.rect:mid-right r) point))
          (:left (setf (px.rect:left r) point))
          (:top (setf (px.rect:top r) point))
          (:right (setf (px.rect:right r) point))
          (:bottom (setf (px.rect:bottom r) point))
          (:center-x (setf (px.rect:center-x r) point))
          (:center-y (setf (px.rect:center-y r) point))
          (:center (setf (px.rect:center r) point)))))))
(defun lock (surface)
  (check-surface surface)
  ;; A child's pixels are borrowed. Pin every ancestor for the same lifetime.
  (when (typep (parent surface) 'surface) (lock (parent surface)))
  (handler-case
      (progn
        (when (zerop (locks surface))
          (when (minusp (pixelisp.internal::%lock-surface (pixelisp.internal::%ptr (pixelisp.internal:handle surface))))
            (pixelisp.internal:native-error 'lock)))
        (incf (locks surface)) surface)
    (error (condition)
      (when (typep (parent surface) 'surface) (unlock (parent surface)))
      (error condition))))
(defun unlock (surface)
  (check-surface surface)
  (when (plusp (locks surface))
    (when (zerop (decf (locks surface)))
      (pixelisp.internal::%unlock-surface (pixelisp.internal::%ptr (pixelisp.internal:handle surface))))
    (when (typep (parent surface) 'surface) (unlock (parent surface)))) surface)
(defun locked-p (surface) (check-surface surface) (plusp (locks surface)))
(defun get-locked (surface) (locked-p surface))
(defun must-lock-p (surface)
  "Return whether SDL currently marks SURFACE as requiring a pixel lock."
  (check-surface surface)
  ;; SDL_MUSTLOCK is a header macro: (surface->flags & SDL_RLEACCEL) != 0.
  ;; SDL_RLEACCEL is 0x2 in SDL2. See SDL2/SDL_MUSTLOCK.
  (not (zerop (logand (plus-c:c-ref (pixelisp.internal:handle surface)
                                     sdl2-ffi:sdl-surface :flags)
                      #x2))))
(defun rle-enabled-p (surface)
  "Return the requested RLE hint, even while SDL temporarily decodes pixels."
  (check-surface surface)
  (rle-hint surface))
(defun %descendant-surface-p (candidate ancestor)
  (loop for current = (parent candidate) then (and (typep current 'surface) (parent current))
        while current
        thereis (eq current ancestor)))
(defun %validate-rle-change (surface enabled operation)
  (check-type enabled boolean)
  (when (/= (if enabled 1 0) (if (rle-hint surface) 1 0))
    (when (plusp (locks surface))
      (error 'pixelisp:resource-in-use :operation operation
             :message "Close pixel views and unlock the surface before changing RLE."))
    (when enabled
      (unless (and (owned-p surface) (null (parent surface))
                   ;; SDL's PREALLOC flag means pixels are externally owned,
                   ;; even when Pixelisp owns the SDL_Surface wrapper.
                   (zerop (logand (plus-c:c-ref (pixelisp.internal:handle surface)
                                                sdl2-ffi:sdl-surface :flags)
                                  #x1)))
        (error 'pixelisp:unsupported-feature :operation operation
               :message "RLE can only be enabled on an independently owned surface."))
      (when (some (lambda (candidate)
                   (and (typep candidate 'surface)
                        (not (eq candidate surface))
                        (not (pixelisp.internal:resource-disposed-p candidate))
                        (%descendant-surface-p candidate surface)))
                  pixelisp.internal::*resources*)
        (error 'pixelisp:resource-in-use :operation operation
               :message "Dispose child subsurfaces before enabling RLE.")))))
(defun set-rle (surface enabled)
  "Set SDL's RLE acceleration hint. Return ENABLED after SDL accepts it.

SDL documents that RLE surfaces may need locking before pixel access; the
requested hint is cached because SDL can temporarily decode a surface. See
https://wiki.libsdl.org/SDL2/SDL_SetSurfaceRLE and SDL2/SDL_MUSTLOCK."
  (check-surface surface)
  (%validate-rle-change surface enabled 'set-rle)
  (unless (= (if enabled 1 0) (if (rle-hint surface) 1 0))
    (when (minusp (pixelisp.internal::%set-surface-rle
                   (pixelisp.internal::%ptr (pixelisp.internal:handle surface))
                   (if enabled 1 0)))
      (pixelisp.internal:native-error 'set-rle))
    (setf (rle-hint surface) enabled))
  enabled)
(defun pixel-pointer (surface x y)
  (cffi:inc-pointer (sdl2:surface-pixels (pixelisp.internal:handle surface))
                    (+ (* y (sdl2:surface-pitch (pixelisp.internal:handle surface))) (* x 4))))
(defun get-at (surface position)
  "Read an RGBA color, checking bounds and the complete owner chain."
  (check-surface surface)
  (multiple-value-bind (x y) (pixelisp.internal:pair position)
    (unless (and (integerp x) (integerp y) (<= 0 x) (< x (width surface)) (<= 0 y) (< y (height surface)))
      (error "Pixel ~S is outside surface ~S." position (size surface)))
    (lock surface)
    (unwind-protect
         (cffi:with-foreign-objects ((r :uint8) (g :uint8) (b :uint8) (a :uint8))
           (pixelisp.internal::%get-rgba
            (cffi:mem-ref (pixel-pointer surface x y) :uint32)
            (pixelisp.internal::%ptr (sdl2:surface-format (pixelisp.internal:handle surface))) r g b a)
           (pixelisp:make-color (cffi:mem-ref r :uint8) (cffi:mem-ref g :uint8)
                                (cffi:mem-ref b :uint8) (cffi:mem-ref a :uint8)))
      (unlock surface))))
(defun get-at-mapped (surface position)
  "Read the packed native pixel at POSITION, independently of the drawing clip."
  (check-surface surface)
  (multiple-value-bind (x y) (pixelisp.internal:pair position)
    (unless (and (integerp x) (integerp y) (<= 0 x) (< x (width surface))
                 (<= 0 y) (< y (height surface)))
      (error "Pixel ~S is outside surface ~S." position (size surface)))
    (lock surface)
    (unwind-protect (cffi:mem-ref (pixel-pointer surface x y) :uint32)
      (unlock surface))))
(defun set-at (surface position color)
  "Write one pixel inside the current clip; out-of-clip writes do nothing."
  (check-surface surface)
  (multiple-value-bind (x y) (pixelisp.internal:pair position)
    (when (and (integerp x) (integerp y) (px.rect:collide-point (clip-rect surface) position))
      (pixelisp.internal:write-surface-pixel surface position color))) color)
(defun pixelisp.internal:write-surface-pixel (surface position color)
  "Write a bounded pixel without drawing clipping, for array and buffer copies."
  (check-surface surface)
  (multiple-value-bind (x y) (pixelisp.internal:pair position)
    (unless (and (integerp x) (integerp y) (<= 0 x) (< x (width surface))
                 (<= 0 y) (< y (height surface)))
      (error "Pixel ~S is outside surface ~S." position (size surface)))
    (multiple-value-bind (r g b a) (pixelisp.internal:rgba color)
      (lock surface)
      (unwind-protect
           (setf (cffi:mem-ref (pixel-pointer surface x y) :uint32)
                 (pixelisp.internal::%map-rgba
                  (pixelisp.internal::%ptr (sdl2:surface-format (pixelisp.internal:handle surface))) r g b a))
        (unlock surface)))) color)
(defun get-clip (surface) (check-surface surface) (px.rect:copy (clip-rect surface)))
(defun set-clip (surface &optional rectangle)
  (check-surface surface)
  (setf (clip-rect surface) (if rectangle (px.rect:clip (get-rect surface) (pixelisp.internal:as-rect rectangle)) (get-rect surface)))
  (pixelisp.internal::with-native-rect (r (clip-rect surface))
    (pixelisp.internal::%set-clip (pixelisp.internal::%ptr (pixelisp.internal:handle surface)) r))
  (get-clip surface))
(defun %blend-mode (flag operation)
  "Decode Lisp blend keywords into an operation and whether alpha participates."
  (case flag
    ((nil 0 :blend-alpha-sdl2) (values nil nil))
    ((:blend-add :blend-rgb-add) (values :add nil))
    ((:blend-sub :blend-rgb-sub) (values :subtract nil))
    ((:blend-mult :blend-rgb-mult) (values :multiply nil))
    ((:blend-min :blend-rgb-min) (values :minimum nil))
    ((:blend-max :blend-rgb-max) (values :maximum nil))
    (:blend-rgba-add (values :add t))
    (:blend-rgba-sub (values :subtract t))
    (:blend-rgba-mult (values :multiply t))
    (:blend-rgba-min (values :minimum t))
    (:blend-rgba-max (values :maximum t))
    (:blend-premultiplied
     (if (eq operation 'blit) (values :premultiplied t)
         (error 'pixelisp:unsupported-feature :operation operation
                :message "Premultiplied blending is available for blits only.")))
    (otherwise
     (error 'pixelisp:unsupported-feature :operation operation
            :message (format nil "Unknown surface blend flag: ~S." flag)))))

(defun %blend-channel (destination source operation)
  "Combine octets, saturating arithmetic at the channel boundaries."
  (ecase operation
    (:add (min 255 (+ destination source)))
    (:subtract (max 0 (- destination source)))
    ;; Round the product upward after dividing by 256, preserving white as an
    ;; identity. This is the integer convention of pygame's channel effects.
    (:multiply (floor (+ (* destination source) 255) 256))
    (:minimum (min destination source))
    (:maximum (max destination source))))

(defun %blend-color (destination source operation include-alpha)
  (let ((destination (px.color:to-list destination))
        (source (px.color:to-list source)))
    (if (eq operation :premultiplied)
        (let ((alpha (fourth source)))
          ;; Transparent source pixels must remain a no-op, including their
          ;; hidden RGB values. Other inputs are assumed already premultiplied.
          (if (zerop alpha) destination
              (mapcar (lambda (dst src)
                        (min 255 (+ src (- dst (floor (* (1+ dst) alpha) 256)))))
                      destination source)))
        (loop for dst in destination for src in source for channel from 0
              collect (if (or (< channel 3) include-alpha)
                          (%blend-channel dst src operation) dst)))))

(defun %fill-blended (surface color area operation include-alpha)
  ;; One outer lock keeps the buffer stable throughout the operation. Pixel
  ;; helpers can safely nest locks without repeatedly locking native storage.
  (lock surface)
  (unwind-protect
       (loop for y from (px.rect:top area) below (px.rect:bottom area) do
         (loop for x from (px.rect:left area) below (px.rect:right area)
               for position = (list x y) do
                 (set-at surface position
                         (%blend-color (get-at surface position) color operation include-alpha))))
    (unlock surface))
  area)

(defun fill (surface color &optional rectangle &key special-flags)
  "Fill a clipped area, optionally applying a RGB/RGBA channel blend effect.
Pass NIL for RECTANGLE to use the full clip with :SPECIAL-FLAGS. Return damage."
  (check-surface surface)
  (let ((area (px.rect:clip (clip-rect surface) (if rectangle (pixelisp.internal:as-rect rectangle) (get-rect surface)))))
    (multiple-value-bind (operation include-alpha) (%blend-mode special-flags 'fill)
      ;; Decode/validate before writing any pixels, even for an empty clip.
      (when operation
        (let ((color (multiple-value-call #'pixelisp:make-color (pixelisp.internal:rgba color))))
          (return-from fill (%fill-blended surface color area operation include-alpha)))))
    (multiple-value-bind (r g b a) (pixelisp.internal:rgba color)
      (pixelisp.internal::with-native-rect (rect area)
        (when (minusp (pixelisp.internal::%fill-rect
                       (pixelisp.internal::%ptr (pixelisp.internal:handle surface)) rect
                       (pixelisp.internal::%map-rgba
                        (pixelisp.internal::%ptr (sdl2:surface-format (pixelisp.internal:handle surface))) r g b a)))
          (pixelisp.internal:native-error 'fill)))) area))
(defun get-alpha (surface) (check-surface surface) (alpha-value surface))
(defun set-alpha (surface alpha &key (rle nil rle-p))
  "Set blanket alpha, optionally changing SDL's RLE acceleration hint.
The optional :RLE behavior follows pygame's Surface.set_alpha flags argument;
RLE sources can be faster to blit and slower to modify. See
https://www.pygame.org/docs/ref/surface.html#pygame.Surface.set_alpha."
  (check-surface surface)
  (when alpha (check-type alpha (unsigned-byte 8)))
  (when rle-p (%validate-rle-change surface rle 'set-alpha))
  (when rle-p (set-rle surface rle))
  (sdl2:set-alpha-mod (pixelisp.internal:handle surface) (or alpha 255))
  (pixelisp.internal::%set-blend (pixelisp.internal::%ptr (pixelisp.internal:handle surface))
                               (if (or (alpha-p surface) (and alpha (< alpha 255))) 1 0))
  (setf (alpha-value surface) alpha))
(defun get-colorkey (surface)
  "Return an independent Color for the native transparent key, or NIL."
  (check-surface surface)
  (when (colorkey surface)
    (multiple-value-call #'pixelisp:make-color (pixelisp.internal:rgba (colorkey surface)))))
(defun set-colorkey (surface color &key (rle nil rle-p))
  "Set a transparent color and optionally SDL's RLE acceleration hint.
The optional :RLE behavior follows pygame's Surface.set_colorkey flags
argument; RLE sources can be faster to blit and slower to modify. See
https://www.pygame.org/docs/ref/surface.html#pygame.Surface.set_colorkey."
  (check-surface surface)
  (when rle-p (%validate-rle-change surface rle 'set-colorkey))
  (let ((key (when color (multiple-value-call #'pixelisp:make-color (pixelisp.internal:rgba color)))))
    (when rle-p (set-rle surface rle))
    (sdl2:set-color-key (pixelisp.internal:handle surface) (if key :true :false)
                       (if key (multiple-value-bind (r g b a) (pixelisp.internal:rgba key)
                                 (pixelisp.internal::%map-rgba
                                  (pixelisp.internal::%ptr (sdl2:surface-format (pixelisp.internal:handle surface))) r g b a)) 0))
    (setf (colorkey surface) key)) color)
(defun %blit-native (target source dest area)
  "Copy SOURCE onto TARGET, applying SOURCE transparency and TARGET clipping."
  (check-surface source) (check-surface target)
  (when (or (locked-p source) (locked-p target))
    (error 'pixelisp:resource-in-use :operation 'blit :message "Blitting a locked surface is not allowed."))
  (multiple-value-bind (x y) (pixelisp.internal:pair dest)
    (let* ((src (if area (pixelisp.internal:as-rect area) (get-rect source)))
           (dst (pixelisp:make-rect x y (px.rect:width src) (px.rect:height src))))
      (pixelisp.internal::with-native-rect (sr src)
        (pixelisp.internal::with-native-rect (dr dst)
          (when (minusp (pixelisp.internal::%blit
                         (pixelisp.internal::%ptr (pixelisp.internal:handle source)) sr
                         (pixelisp.internal::%ptr (pixelisp.internal:handle target)) dr))
            (pixelisp.internal:native-error 'blit))
          (pixelisp:make-rect
           (cffi:foreign-slot-value dr '(:struct pixelisp.internal::native-rect) 'pixelisp.internal::x)
           (cffi:foreign-slot-value dr '(:struct pixelisp.internal::native-rect) 'pixelisp.internal::y)
           (cffi:foreign-slot-value dr '(:struct pixelisp.internal::native-rect) 'pixelisp.internal::w)
           (cffi:foreign-slot-value dr '(:struct pixelisp.internal::native-rect) 'pixelisp.internal::h)))))))
(defun %blit-regions (target source dest area)
  "Return corresponding source/destination rectangles after both clips."
  (multiple-value-bind (x y) (pixelisp.internal:pair dest)
    (let* ((requested (if area (pixelisp.internal:as-rect area) (get-rect source)))
           (source-area (px.rect:clip requested (get-rect source)))
           (destination (pixelisp:make-rect
                         (+ x (- (px.rect:left source-area) (px.rect:left requested)))
                         (+ y (- (px.rect:top source-area) (px.rect:top requested)))
                         (px.rect:width source-area) (px.rect:height source-area)))
           (damage (px.rect:clip destination (clip-rect target))))
      (values (pixelisp:make-rect
               (+ (px.rect:left source-area) (- (px.rect:left damage) (px.rect:left destination)))
               (+ (px.rect:top source-area) (- (px.rect:top damage) (px.rect:top destination)))
               (px.rect:width damage) (px.rect:height damage))
              damage))))

(defun %blit-blended (target source dest area operation include-alpha)
  (multiple-value-bind (source-area damage) (%blit-regions target source dest area)
    (let* ((width (px.rect:width damage)) (height (px.rect:height damage))
           (pixels (make-array (* width height))))
      ;; Snapshot the clipped source first. Self-blits, sibling subsurfaces,
      ;; and overlapping foreign imports must all read the original pixels.
      (lock source)
      (unwind-protect
           (dotimes (y height)
             (dotimes (x width)
               (setf (aref pixels (+ x (* y width)))
                     (get-at source (list (+ x (px.rect:left source-area))
                                          (+ y (px.rect:top source-area)))))))
        (unlock source))
      (lock target)
      (unwind-protect
           (dotimes (y height)
             (dotimes (x width)
               (let ((position (list (+ x (px.rect:left damage)) (+ y (px.rect:top damage)))))
                 (set-at target position
                         (%blend-color (get-at target position)
                                       (aref pixels (+ x (* y width))) operation
                                       (and include-alpha (alpha-p source)))))))
        (unlock target)))
    damage))

(defun blit (target source dest &key area special-flags)
  "Draw SOURCE with clipping and transparency, or a :SPECIAL-FLAGS blend effect.
Channel effects use stored pixel values, ignoring the source key and modulation."
  (check-surface source) (check-surface target)
  (when (or (locked-p source) (locked-p target))
    (error 'pixelisp:resource-in-use :operation 'blit :message "Blitting a locked surface is not allowed."))
  (multiple-value-bind (operation include-alpha) (%blend-mode special-flags 'blit)
    (if (and operation (or (not (eq operation :premultiplied)) (alpha-p source)))
        (%blit-blended target source dest area operation include-alpha)
        (%blit-native target source dest area))))

(defun %blit-operation (target operation)
  "Apply one list/vector blit entry in keyword or pygame positional form."
  (unless (and (typep operation 'sequence) (not (stringp operation)))
    (error "A blit operation must be a list or vector, got ~S." operation))
  (let ((arguments (coerce operation 'list)))
    (if (and (>= (length arguments) 3) (keywordp (third arguments)))
        ;; Preserve the established Lisp spelling: (source dest :area ...).
        (apply #'blit target arguments)
        ;; Match Surface.blit(source, dest, area=None, special_flags=0).
        (progn
          (unless (<= 2 (length arguments) 4)
            (error "A positional blit operation needs 2 to 4 items: ~S." operation))
          (destructuring-bind (source dest &optional area special-flags) arguments
            (blit target source dest :area area :special-flags special-flags))))))

(defun blits (surface operations &key (return-rects t))
  "Draw a list/vector of blit entries from left to right.
Each entry is (source destination &key :area :special-flags), or pygame-style
(source destination [area [special-flags]]); entries may also be vectors.
Return a list of damage Rects in operation order, or NIL when RETURN-RECTS is
false. A bad entry signals an error after any earlier entries have rendered."
  (check-surface surface)
  (unless (and (typep operations 'sequence) (not (stringp operations)))
    (error "BLITS operations must be a list or vector, got ~S." operations))
  (if return-rects
      (loop for operation across (coerce operations 'vector)
            collect (%blit-operation surface operation))
      (progn
        (loop for operation across (coerce operations 'vector)
              do (%blit-operation surface operation))
        nil)))

(defun premul-alpha (surface)
  "Return an independent surface whose RGB channels are multiplied by pixel alpha.
Use the result with :BLEND-PREMULTIPLIED. This does not mutate the input."
  (check-surface surface)
  (let ((result (copy surface)))
    (handler-case
        (progn
          (when (alpha-p surface)
            (dotimes (y (height surface))
              (dotimes (x (width surface))
                (let* ((position (list x y)) (color (get-at surface position))
                       (alpha (pixelisp:color-a color)))
                  (set-at result position
                          (append (mapcar (lambda (channel) (floor (* (1+ channel) alpha) 256))
                                          (subseq (px.color:to-list color) 0 3))
                                  (list alpha))))))
            ;; The new pixel representation is governed by alpha, not the old
            ;; RGB color key, whose components may have changed during conversion.
            (set-colorkey result nil))
          result)
      (error (condition) (dispose result) (error condition)))))
(defun copy (surface)
  (check-surface surface)
  (let ((result (make-surface (size surface) :alpha (alpha-p surface))))
    (dotimes (y (height surface)) (dotimes (x (width surface)) (set-at result (list x y) (get-at surface (list x y)))))
    (set-alpha result (get-alpha surface)) (set-colorkey result (get-colorkey surface))
    (when (rle-enabled-p surface) (set-rle result t)) result))
(defun convert (surface) (let ((out (make-surface (size surface))))
                    (dotimes (y (height surface)) (dotimes (x (width surface)) (set-at out (list x y) (get-at surface (list x y))))) out))
(defun convert-alpha (surface)
  (let ((out (make-surface (size surface) :alpha t)))
    (dotimes (y (height surface)) (dotimes (x (width surface)) (set-at out (list x y) (get-at surface (list x y))))) out))
(defun subsurface (surface rectangle)
  "Create a shared view with its parent's pixel format and row pitch."
  (check-surface surface)
  (loop for ancestor = surface then (and (typep ancestor 'surface) (parent ancestor))
        while (typep ancestor 'surface)
        when (rle-hint ancestor) do
          (error 'pixelisp:unsupported-feature :operation 'subsurface
                 :message "Disable RLE on the owning surface before creating a subsurface."))
  (let* ((r (pixelisp.internal:as-rect rectangle))
         (w (px.rect:width r)) (h (px.rect:height r)))
    (unless (and (plusp w) (plusp h) (px.rect:contains (get-rect surface) r))
      (error "Subsurface rectangle must be nonempty and contained in its parent."))
    (let* ((raw (pixelisp.internal::%surface-from-format
                 (pixel-pointer surface (px.rect:x r) (px.rect:y r)) w h 32
                 (sdl2:surface-pitch (pixelisp.internal:handle surface))
                 (plus-c:c-ref (pixelisp.internal:handle surface) sdl2-ffi:sdl-surface :format :format)))
           (native (autowrap:wrap-pointer raw 'sdl2-ffi:sdl-surface)))
      (when (cffi:null-pointer-p raw) (pixelisp.internal:native-error 'subsurface))
      (let ((child (pixelisp.internal:register-resource
                    (make-instance 'surface :handle native :width w :height h :alpha (alpha-p surface)
                                   :parent surface :offset (list (px.rect:x r) (px.rect:y r))
                                   :clip (pixelisp:make-rect 0 0 w h)))))
        (set-alpha child (get-alpha surface))
        (set-colorkey child (get-colorkey surface)) child))))
(defun scroll (surface dx dy)
  (let ((snapshot (copy surface)))
    (unwind-protect
         (let ((clip (get-clip surface)))
           (loop for y from (px.rect:top clip) below (px.rect:bottom clip) do
             (loop for x from (px.rect:left clip) below (px.rect:right clip)
                   for sx = (- x dx) for sy = (- y dy)
                   when (px.rect:collide-point clip (list sx sy))
                     do (set-at surface (list x y) (get-at snapshot (list sx sy))))))
      (dispose snapshot))) surface)
(defun get-bounding-rect (surface &optional (min-alpha 1))
  "Find the smallest rectangle containing non-keyed pixels above MIN-ALPHA."
  (let ((left (width surface)) (top (height surface)) (right 0) (bottom 0)
        (key (when (get-colorkey surface)
               (subseq (px.color:to-list (get-colorkey surface)) 0 3))))
    (dotimes (y (height surface))
      (dotimes (x (width surface))
        (let ((color (get-at surface (list x y))))
          (when (and (>= (pixelisp:color-a color) min-alpha)
                     (not (and key (equal key (subseq (px.color:to-list color) 0 3)))))
            (setf left (min left x) top (min top y)
                  right (max right (1+ x)) bottom (max bottom (1+ y)))))))
    (if (zerop right) (pixelisp:make-rect 0 0 0 0) (pixelisp:make-rect left top (- right left) (- bottom top)))))
