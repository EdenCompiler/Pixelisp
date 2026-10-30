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
(cffi:defcfun ("SDL_CreateRGBSurface" %create-surface) :pointer
  (flags :uint32) (w :int) (h :int) (depth :int)
  (r :uint32) (g :uint32) (b :uint32) (a :uint32))
(cffi:defcfun ("SDL_MasksToPixelFormatEnum" %mask-format) :uint32
  (bits :int) (r :uint32) (g :uint32) (b :uint32) (a :uint32))
(cffi:defcfun ("SDL_SetPaletteColors" %set-palette-colors) :int
  (palette :pointer) (colors :pointer) (first :int) (count :int))
(cffi:defcfun ("SDL_GetColorKey" %get-color-key) :int (surface :pointer) (key :pointer))
;; These public SDL2 structure prefixes also describe custom formats whose
;; masks have no SDL pixel-format enum. CFFI supplies native pointer alignment.
(cffi:defcstruct pixel-format-header
  (format :uint32) (palette :pointer) (bits :uint8) (bytes :uint8) (padding :uint16)
  (r :uint32) (g :uint32) (b :uint32) (a :uint32))
(cffi:defcstruct palette-header (count :int) (colors :pointer))
(cffi:defcstruct palette-color (r :uint8) (g :uint8) (b :uint8) (a :uint8))
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
(defun %default-masks (depth alpha)
  (case depth
    (8 '(0 0 0 0))
    (12 '(#x0f00 #x00f0 #x000f 0))
    (15 '(#x7c00 #x03e0 #x001f 0))
    (16 (if alpha '(#x0f00 #x00f0 #x000f #xf000) '(#xf800 #x07e0 #x001f 0)))
    (24 '(#xff #xff00 #xff0000 0))
    (32 (list #xff #xff00 #xff0000 (if alpha #xff000000 0)))))

(defun %validated-masks (depth alpha masks)
  "Reject overlapping, noncontiguous, or out-of-depth channels before SDL."
  (unless (member depth '(8 12 15 16 24 32))
    (error 'pixelisp:unsupported-feature :operation 'make-surface
           :message "Surface depth must be 8, 12, 15, 16, 24, or 32."))
  (when (and alpha (not (member depth '(16 32))))
    (error 'pixelisp:unsupported-feature :operation 'make-surface
           :message "Per-pixel alpha requires a 16-bit or 32-bit surface."))
  (let ((values (if masks
                    (progn
                      (unless (and (typep masks 'sequence) (not (stringp masks)) (= (length masks) 4))
                        (error "Pixel masks must be a sequence of four integers."))
                      (coerce masks 'list))
                    (%default-masks depth alpha)))
        (used 0))
    (dolist (mask values)
      (unless (and (integerp mask) (<= 0 mask) (< mask (ash 1 depth)))
        (error 'type-error :datum mask :expected-type `(integer 0 ,(1- (ash 1 depth)))))
      (when (plusp mask)
        ;; Removing trailing zero bits turns a contiguous field into 2^n - 1.
        (let* ((lowest-bit (logand mask (- mask)))
               (shift (1- (integer-length lowest-bit)))
               (field (ash mask (- shift))))
          (unless (and (zerop (logand field (1+ field))) (<= (logcount mask) 8))
            (error "Each pixel channel must contain at most eight contiguous bits."))))
      (unless (zerop (logand mask used)) (error "Pixel channel masks must not overlap."))
      (setf used (logior used mask)))
    (when (if (= depth 8) (plusp used) (some #'zerop (subseq values 0 3)))
      (error "Indexed surfaces require zero masks; true-color surfaces require RGB masks."))
    (when (and masks (not (eql (not (zerop (fourth values))) (not (null alpha)))))
      (error "The alpha mask must agree with the :ALPHA argument."))
    (when (zerop (apply #'pixelisp.internal::%mask-format depth values))
      (error 'pixelisp:unsupported-feature :operation 'make-surface
             :message "SDL does not support this combination of depth and channel masks."))
    values))

(declaim (ftype function get-bitsize get-masks set-palette get-palette))
(defun make-surface (size &key (alpha nil) (depth 32) masks)
  "Create an owned image with 8/12/15/16/24/32-bit pixels and optional RGB(A) masks."
  (let ((masks (%validated-masks depth alpha masks)))
  (multiple-value-bind (w h) (pixelisp.internal:pair size)
    (check-type w (integer 1 #x7fffffff)) (check-type h (integer 1 #x7fffffff))
    (let* ((raw (apply #'pixelisp.internal::%create-surface 0 w h depth masks))
           (object nil) (complete nil))
      (when (cffi:null-pointer-p raw)
        (pixelisp.internal:native-error 'make-surface))
      (unwind-protect
           (progn
             (setf object (make-instance 'surface
                             :handle (autowrap:wrap-pointer raw 'sdl2-ffi:sdl-surface)
                             :width w :height h :alpha (not (null alpha))
                             :clip (pixelisp:make-rect 0 0 w h)))
             (when (minusp (pixelisp.internal::%set-blend raw (if alpha 1 0)))
               (pixelisp.internal:native-error 'make-surface))
             ;; Start indexed images with the conventional RGB332 palette.
             ;; Games can replace it without rewriting any stored pixel index.
             (when (= depth 8)
               (set-palette object
                 (loop for index below 256 collect
                   (list (round (* 255 (ldb (byte 3 5) index)) 7)
                         (round (* 255 (ldb (byte 3 2) index)) 7)
                         (* 85 (ldb (byte 2 0) index))))))
             (pixelisp.internal:register-resource object)
             (setf complete t)
             object)
        (unless complete (pixelisp.internal::%free-surface raw)))))))

(defun %make-like (source size)
  "Allocate independent storage with SOURCE's pixel layout and palette."
  (check-surface source)
  (let ((result (make-surface size :depth (get-bitsize source) :masks (get-masks source)
                                   :alpha (alpha-p source))))
    (handler-case
        (progn
          (when (= (get-bitsize source) 8) (set-palette result (get-palette source)))
          result)
      (error (condition) (dispose result) (error condition)))))
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
                           :alpha (not (zerop
                                         (cffi:foreign-slot-value
                                           (pixelisp.internal:%ptr (sdl2:surface-format wrapped))
                                           '(:struct pixelisp.internal::pixel-format-header)
                                           'pixelisp.internal::a)))
                           :owned owned :parent parent
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
  "Read native masks even when a custom layout has no SDL format enum."
  (check-surface surface)
  (let ((format (pixelisp.internal:%ptr (sdl2:surface-format (pixelisp.internal:handle surface)))))
    (values (cffi:foreign-slot-value format '(:struct pixelisp.internal::pixel-format-header) 'pixelisp.internal::bits)
            (loop for channel in '(pixelisp.internal::r pixelisp.internal::g pixelisp.internal::b pixelisp.internal::a)
                  collect (cffi:foreign-slot-value format '(:struct pixelisp.internal::pixel-format-header) channel)))))
(defun get-bitsize (surface)
  "Return the native pixel depth in bits."
  (nth-value 0 (%format-description surface)))
(defun get-bytesize (surface)
  "Return the number of storage bytes per pixel."
  (check-surface surface)
  (cffi:foreign-slot-value (pixelisp.internal:%ptr (sdl2:surface-format (pixelisp.internal:handle surface)))
                           '(:struct pixelisp.internal::pixel-format-header) 'pixelisp.internal::bytes))
(defun get-masks (surface)
  "Return a fresh list of the packed red, green, blue, and alpha bit masks."
  (nth-value 1 (%format-description surface)))

(defun %palette-pointer (surface operation)
  "Get the native palette after checking the surface's type and lifetime."
  (check-surface surface)
  (let* ((format (pixelisp.internal:%ptr (sdl2:surface-format (pixelisp.internal:handle surface))))
         (palette (cffi:foreign-slot-value format '(:struct pixelisp.internal::pixel-format-header)
                                           'pixelisp.internal::palette)))
    (when (cffi:null-pointer-p palette)
      (error 'pixelisp:unsupported-feature :operation operation
             :message "Only indexed 8-bit surfaces have a color palette."))
    palette))

(defun %palette-index (palette index)
  (let ((count (cffi:foreign-slot-value palette '(:struct pixelisp.internal::palette-header)
                                      'pixelisp.internal::count)))
    (unless (and (integerp index) (<= 0 index) (< index count))
      (error 'type-error :datum index :expected-type `(integer 0 ,(1- count))))
    index))

(defun get-palette-at (surface index)
  "Return a fresh Color for palette INDEX."
  (let* ((palette (%palette-pointer surface 'get-palette-at))
         (index (%palette-index palette index))
         (colors (cffi:foreign-slot-value palette '(:struct pixelisp.internal::palette-header)
                                          'pixelisp.internal::colors))
         (color (cffi:mem-aptr colors '(:struct pixelisp.internal::palette-color) index)))
    (apply #'pixelisp:make-color
           (loop for channel in '(pixelisp.internal::r pixelisp.internal::g pixelisp.internal::b pixelisp.internal::a)
                 collect (cffi:foreign-slot-value color '(:struct pixelisp.internal::palette-color) channel)))))

(defun get-palette (surface)
  "Return independent Colors for all entries in an indexed surface's palette."
  (let ((palette (%palette-pointer surface 'get-palette)))
    (loop for index below (cffi:foreign-slot-value palette '(:struct pixelisp.internal::palette-header)
                                                  'pixelisp.internal::count)
          collect (get-palette-at surface index))))

(defun %opaque-palette-color (color)
  (let ((color (px.color:parse color)))
    (unless (= 255 (pixelisp:color-a color))
      (error 'pixelisp:unsupported-feature :operation 'set-palette
             :message "Palette entries must be opaque RGB colors; use a color key for transparency."))
    color))

(defun %write-palette (palette start colors operation)
  (unless (null colors)
    (cffi:with-foreign-object (native '(:struct pixelisp.internal::palette-color) (length colors))
      (loop for color in colors for index from 0
            for entry = (cffi:mem-aptr native '(:struct pixelisp.internal::palette-color) index) do
              (loop for channel in '(pixelisp.internal::r pixelisp.internal::g pixelisp.internal::b pixelisp.internal::a)
                    for value in (px.color:to-list color) do
                      (setf (cffi:foreign-slot-value entry '(:struct pixelisp.internal::palette-color) channel) value)))
      (when (minusp (pixelisp.internal::%set-palette-colors palette native start (length colors)))
        (pixelisp.internal:native-error operation))))
  colors)

(defun set-palette (surface colors)
  "Replace the palette prefix with COLORS, validating the complete input first."
  (let* ((palette (%palette-pointer surface 'set-palette))
         (count (cffi:foreign-slot-value palette '(:struct pixelisp.internal::palette-header) 'pixelisp.internal::count)))
    (unless (and (typep colors 'sequence) (not (stringp colors)) (<= (length colors) count))
      (error "Palette colors must be a sequence with at most ~D entries." count))
    ;; Decode every entry before making a native call; a bad last entry cannot
    ;; partially replace the palette. SDL invalidates cached blit maps for us.
    (%write-palette palette 0 (map 'list #'%opaque-palette-color colors) 'set-palette))
  colors)

(defun set-palette-at (surface index color)
  "Replace one palette color; existing indexed pixels immediately use it."
  (let* ((palette (%palette-pointer surface 'set-palette-at))
         (index (%palette-index palette index))
         (parsed (%opaque-palette-color color)))
    (%write-palette palette index (list parsed) 'set-palette-at))
  color)
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
  (when (< (get-bytesize surface) 4)
    (let ((maximum (1- (ash 1 (* 8 (get-bytesize surface))))))
      (unless (<= 0 pixel maximum)
        (error 'type-error :datum pixel :expected-type `(integer 0 ,maximum)))))
  (cffi:with-foreign-objects ((r :uint8) (g :uint8) (b :uint8) (a :uint8))
    (pixelisp.internal::%get-rgba
     (ldb (byte 32 0) pixel)
     (pixelisp.internal:%ptr (sdl2:surface-format (pixelisp.internal:handle surface))) r g b a)
    (pixelisp:make-color (cffi:mem-ref r :uint8) (cffi:mem-ref g :uint8)
                         (cffi:mem-ref b :uint8) (cffi:mem-ref a :uint8))))

(defun %checked-mapped-pixel (surface value)
  "Validate a native pixel without decoding or choosing another palette index."
  (check-surface surface)
  (let* ((bits (* 8 (get-bytesize surface)))
         (maximum (1- (ash 1 bits)))
         (minimum (if (= bits 32) (- (ash 1 31)) 0)))
    (unless (typep value `(integer ,minimum ,maximum))
      (error 'type-error :datum value :expected-type `(integer ,minimum ,maximum)))
    ;; SDL uses Uint32 pixels. Accept a signed 32-bit representation just as
    ;; PixelArray does, but keep smaller formats strictly within their storage.
    (ldb (byte bits 0) value)))

(defun %color-pixel (surface color)
  "Resolve a drawing color, retaining integers as exact native pixel values."
  (if (integerp color) (%checked-mapped-pixel surface color)
      (map-rgb surface color)))
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
                    (+ (* y (sdl2:surface-pitch (pixelisp.internal:handle surface)))
                       (* x (get-bytesize surface)))))

(defun %little-endian-p ()
  (cffi:with-foreign-object (word :uint16)
    (setf (cffi:mem-ref word :uint16) 1)
    (= 1 (cffi:mem-ref word :uint8))))

(defun %read-packed-pixel (surface x y)
  "Read native pixel storage. The caller holds a lock and validates coordinates."
  (let ((pointer (pixel-pointer surface x y)))
    (case (get-bytesize surface)
      (1 (cffi:mem-ref pointer :uint8))
      (2 (cffi:mem-ref pointer :uint16))
      (4 (cffi:mem-ref pointer :uint32))
      (3 (let ((little (%little-endian-p)))
           ;; A 32-bit load here would overread the last pixel of an unpadded
           ;; row. Assemble exactly three bytes, in native packed-pixel order.
           (loop for index below 3 sum
             (ash (cffi:mem-aref pointer :uint8 index)
                  (* 8 (if little index (- 2 index))))))))))

(defun %write-packed-pixel (surface x y value)
  "Write native storage without the drawing clip. The caller holds a lock."
  (let* ((bytes (get-bytesize surface)) (maximum (1- (ash 1 (* bytes 8))))
         (pointer (pixel-pointer surface x y)))
    (unless (and (integerp value) (<= 0 value maximum))
      (error 'type-error :datum value :expected-type `(integer 0 ,maximum)))
    (case bytes
      (1 (setf (cffi:mem-ref pointer :uint8) value))
      (2 (setf (cffi:mem-ref pointer :uint16) value))
      (4 (setf (cffi:mem-ref pointer :uint32) value))
      (3 (let ((little (%little-endian-p)))
           (dotimes (index 3)
             (setf (cffi:mem-aref pointer :uint8 index)
                   (ldb (byte 8 (* 8 (if little index (- 2 index)))) value))))))
  value))
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
            (%read-packed-pixel surface x y)
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
    (unwind-protect (%read-packed-pixel surface x y)
      (unlock surface))))
(defun set-at-mapped (surface position value)
  "Write a native packed pixel inside the clip; palette indices are ordinary integers."
  (check-surface surface)
  (let ((packed (%checked-mapped-pixel surface value)))
    (multiple-value-bind (x y) (pixelisp.internal:pair position)
      (unless (and (integerp x) (integerp y) (<= 0 x) (< x (width surface)) (<= 0 y) (< y (height surface)))
        (error "Pixel ~S is outside surface ~S." position (size surface)))
      (when (px.rect:collide-point (clip-rect surface) position)
        (lock surface)
        (unwind-protect (%write-packed-pixel surface x y packed) (unlock surface)))))
  value)
(defun set-at (surface position color)
  "Write a color or native packed integer inside the clip; other writes do nothing."
  (check-surface surface)
  ;; Validate even when clipping makes this a no-op, before acquiring a lock.
  (let ((packed (%color-pixel surface color)))
    (multiple-value-bind (x y) (pixelisp.internal:pair position)
      (when (and (integerp x) (integerp y) (px.rect:collide-point (clip-rect surface) position))
        (set-at-mapped surface position packed))))
  color)
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
           (%write-packed-pixel surface x y
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
  (let ((area (px.rect:clip (clip-rect surface) (if rectangle (pixelisp.internal:as-rect rectangle) (get-rect surface))))
        (packed (%color-pixel surface color)))
    (multiple-value-bind (operation include-alpha) (%blend-mode special-flags 'fill)
      ;; Decode/validate before writing any pixels, even for an empty clip.
      (when operation
        (let ((color (if (integerp color) (unmap-rgb surface packed)
                         (multiple-value-call #'pixelisp:make-color (pixelisp.internal:rgba color)))))
          (return-from fill (%fill-blended surface color area operation include-alpha)))))
    (pixelisp.internal::with-native-rect (rect area)
      (when (minusp (pixelisp.internal::%fill-rect
                     (pixelisp.internal::%ptr (pixelisp.internal:handle surface)) rect packed))
        (pixelisp.internal:native-error 'fill))) area))
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
  ;; NIL explicitly disables blending, including per-pixel alpha. Every byte
  ;; value enables it: 255 still means an alpha-enabled source in pygame.
  (pixelisp.internal::%set-blend (pixelisp.internal::%ptr (pixelisp.internal:handle surface))
                               (if alpha 1 0))
  (setf (alpha-value surface) alpha))
(defun %native-colorkey (surface)
  "Return the native transparent pixel/index, or NIL when keying is disabled."
  (check-surface surface)
  (cffi:with-foreign-object (key :uint32)
    (when (zerop (pixelisp.internal::%get-color-key
                  (pixelisp.internal:%ptr (pixelisp.internal:handle surface)) key))
      (cffi:mem-ref key :uint32))))
(defun get-colorkey (surface)
  "Return the key's current color, including any palette changes, or NIL."
  (let ((key (%native-colorkey surface)))
    (when key (unmap-rgb surface key))))
(defun %colorkey-pixel-p (surface pixel key)
  "Match palette indices exactly, or RGB fields independently of pixel alpha."
  (if (= 8 (get-bitsize surface)) (= pixel key)
      (let ((rgb-mask (reduce #'logior (subseq (get-masks surface) 0 3))))
        (= (logand pixel rgb-mask) (logand key rgb-mask)))))
(defun set-colorkey (surface color &key (rle nil rle-p))
  "Set a transparent color and optionally SDL's RLE acceleration hint.
The optional :RLE behavior follows pygame's Surface.set_colorkey flags
argument; RLE sources can be faster to blit and slower to modify. See
https://www.pygame.org/docs/ref/surface.html#pygame.Surface.set_colorkey."
  (check-surface surface)
  (when rle-p (%validate-rle-change surface rle 'set-colorkey))
  (let* ((packed (when color (if (integerp color)
                                 (progn
                                   (unless (<= 0 color (1- (ash 1 (* 8 (get-bytesize surface)))))
                                     (error "The color key does not fit this surface's native pixel."))
                                   color)
                                 (map-rgb surface color))))
         (key (when packed (unmap-rgb surface packed))))
    (when rle-p (set-rle surface rle))
    (sdl2:set-color-key (pixelisp.internal:handle surface) (if key :true :false)
                       (or packed 0))
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
  "Copy native pixels and palette independently, retaining transparency settings."
  (check-surface surface)
  (let ((result (%make-like surface (size surface))))
    (handler-case
        (progn
          (lock surface)
          (unwind-protect
               (progn
                 (lock result)
                 (unwind-protect
                      (dotimes (y (height surface))
                        (dotimes (x (width surface))
                          (%write-packed-pixel result x y (%read-packed-pixel surface x y))))
                   (unlock result)))
            (unlock surface))
          (set-alpha result (get-alpha surface))
          (set-colorkey result (%native-colorkey surface))
          (when (rle-enabled-p surface) (set-rle result t))
          result)
      (error (condition) (dispose result) (error condition)))))

(defun convert (surface &optional format &key masks)
  "Copy colors into an opaque surface. FORMAT is a depth or a template Surface."
  (check-surface surface)
  (let* ((template (when (typep format 'surface) (check-surface format)))
         (requested-depth (cond (template (get-bitsize template)) ((null format) 32)
                      ((integerp format) format)
                      (t (error 'type-error :datum format :expected-type '(or null integer surface)))))
         (masks (or masks (when template (append (subseq (get-masks template) 0 3) '(0)))))
         ;; Removing alpha from RGBA4444 leaves RGB444: SDL reports 12 color
         ;; bits for that layout, although both formats use two storage bytes.
         (depth (if (and template masks
                         (zerop (apply #'pixelisp.internal::%mask-format requested-depth masks)))
                    (integer-length (reduce #'logior (subseq masks 0 3)))
                    requested-depth))
         (result (make-surface (size surface) :depth depth :masks masks)))
    (handler-case
        (progn
          (when (and template (= depth 8)) (set-palette result (get-palette template)))
          (let ((same-layout
                  (and (= (get-bitsize surface) (get-bitsize result))
                       (equal (get-masks surface) (get-masks result))
                       (or (/= depth 8)
                           (equal (mapcar #'px.color:to-list (get-palette surface))
                                  (mapcar #'px.color:to-list (get-palette result)))))))
            (dotimes (y (height surface))
              (dotimes (x (width surface))
                (if same-layout
                    (set-at-mapped result (list x y) (get-at-mapped surface (list x y)))
                    (set-at result (list x y) (get-at surface (list x y))))))
            (set-alpha result (get-alpha surface))
            (set-colorkey result (if same-layout (%native-colorkey surface) (get-colorkey surface))))
          result)
      (error (condition) (dispose result) (error condition)))))
(defun convert-alpha (surface)
  "Copy stored colors to RGBA32, baking the source color key into pixel alpha."
  (check-surface surface)
  (let ((result (make-surface (size surface) :alpha t)) (key (%native-colorkey surface)))
    (handler-case
        (progn
          (dotimes (y (height surface))
            (dotimes (x (width surface))
              (let* ((position (list x y)) (color (get-at surface position)))
                (when (and key (%colorkey-pixel-p surface (get-at-mapped surface position) key))
                  (setf (pixelisp:color-a color) 0))
                (set-at result position color))))
          (set-alpha result (or (get-alpha surface) 255))
          result)
      (error (condition) (dispose result) (error condition)))))
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
    (let* ((raw (apply #'pixelisp.internal::%surface-from
                 (pixel-pointer surface (px.rect:x r) (px.rect:y r)) w h (get-bitsize surface)
                 (sdl2:surface-pitch (pixelisp.internal:handle surface)) (get-masks surface)))
           (child nil) (complete nil))
      (when (cffi:null-pointer-p raw) (pixelisp.internal:native-error 'subsurface))
      (unwind-protect
           (progn
             (setf child (make-instance 'surface :handle (autowrap:wrap-pointer raw 'sdl2-ffi:sdl-surface)
                                    :width w :height h :alpha (alpha-p surface)
                                    :parent surface :offset (list (px.rect:x r) (px.rect:y r))
                                    :clip (pixelisp:make-rect 0 0 w h)))
             (when (= (get-bitsize surface) 8)
               ;; As in pygame, pixel indices alias the parent, while the
               ;; child's palette and other surface state remain independent.
               (set-palette child (get-palette surface)))
             (set-alpha child (get-alpha surface))
             (set-colorkey child (%native-colorkey surface))
             (pixelisp.internal:register-resource child)
             (setf complete t)
             child)
        (unless complete (pixelisp.internal::%free-surface raw))))))
(defun scroll (surface dx dy)
  (let ((snapshot (copy surface)))
    (unwind-protect
         (let ((clip (get-clip surface)))
           (loop for y from (px.rect:top clip) below (px.rect:bottom clip) do
             (loop for x from (px.rect:left clip) below (px.rect:right clip)
                   for sx = (- x dx) for sy = (- y dy)
                   when (px.rect:collide-point clip (list sx sy))
                     do (set-at-mapped surface (list x y) (get-at-mapped snapshot (list sx sy))))))
      (dispose snapshot))) surface)
(defun get-bounding-rect (surface &optional (min-alpha 1))
  "Find the smallest rectangle containing non-keyed pixels above MIN-ALPHA."
  (let ((left (width surface)) (top (height surface)) (right 0) (bottom 0)
        (key (%native-colorkey surface)))
    (dotimes (y (height surface))
      (dotimes (x (width surface))
        (let ((color (get-at surface (list x y))))
          (when (and (>= (pixelisp:color-a color) min-alpha)
                     (not (and key (%colorkey-pixel-p surface (get-at-mapped surface (list x y)) key))))
            (setf left (min left x) top (min top y)
                  right (max right (1+ x)) bottom (max bottom (1+ y)))))))
    (if (zerop right) (pixelisp:make-rect 0 0 0 0) (pixelisp:make-rect left top (- right left) (- bottom top)))))
