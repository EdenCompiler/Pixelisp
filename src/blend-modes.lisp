;;;; Custom SDL renderer blending and renderer capability information.
;;;; The values returned here can be passed directly to draw/texture blend APIs.
(in-package #:pixelisp.sdl2.video)

(cffi:defcfun ("SDL_ComposeCustomBlendMode" %compose-custom-blend-mode) :uint32
  (source-color-factor :int) (destination-color-factor :int) (color-operation :int)
  (source-alpha-factor :int) (destination-alpha-factor :int) (alpha-operation :int))
(cffi:defcfun ("SDL_GetNumRenderDrivers" %get-num-render-drivers) :int)
(cffi:defcfun ("SDL_GetRenderDriverInfo" %get-render-driver-info) :int
  (index :int) (info :pointer))
(cffi:defcfun ("SDL_GetRendererInfo" %get-renderer-info) :int
  (renderer :pointer) (info :pointer))

;; Keep the SDL2 structure layout explicit: the fixed array has 16 entries.
(cffi:defcstruct renderer-info
  (name :pointer) (flags :uint32) (num-texture-formats :uint32)
  (texture-formats (:array :uint32 16))
  (max-texture-width :int) (max-texture-height :int))

(defparameter +blend-factors+
  '((:zero . 1) (:one . 2) (:src-color . 3) (:one-minus-src-color . 4)
    (:src-alpha . 5) (:one-minus-src-alpha . 6) (:dst-color . 7)
    (:one-minus-dst-color . 8) (:dst-alpha . 9) (:one-minus-dst-alpha . 10)))
(defparameter +blend-operations+
  '((:add . 1) (:subtract . 2) (:rev-subtract . 3) (:minimum . 4) (:maximum . 5)))

(defun %blend-enum (value table)
  "Turn a named SDL enum or its integer representation into a checked integer."
  (cond ((integerp value)
         (if (member value (mapcar #'cdr table)) value
             (error 'type-error :datum value :expected-type `(member ,@(mapcar #'cdr table)))))
        ((cdr (assoc value table)) (cdr (assoc value table)))
        (t (error 'type-error :datum value
                  :expected-type `(member ,@(mapcar #'car table))))))

(defun %blend-triple-p (value)
  "Recognize a three-element non-string sequence for a blend mode."
  (and (typep value 'sequence) (not (stringp value)) (= (length value) 3)))

(defun %blend-triple (value)
  "Check one pygame-style mode triple and translate its three SDL values."
  (unless (%blend-triple-p value)
    (error 'type-error :datum value :expected-type '(satisfies %blend-triple-p)))
  (list (%blend-enum (elt value 0) +blend-factors+)
        (%blend-enum (elt value 1) +blend-factors+)
        (%blend-enum (elt value 2) +blend-operations+)))

(defun compose-custom-blend-mode (color-mode alpha-mode)
  "Return an SDL integer blend mode from COLOR-MODE and ALPHA-MODE triples.

Each triple contains (SOURCE-FACTOR DESTINATION-FACTOR OPERATION), as a list
or vector. Factors are :ZERO, :ONE, :SRC-COLOR, :ONE-MINUS-SRC-COLOR,
:SRC-ALPHA, :ONE-MINUS-SRC-ALPHA, :DST-COLOR, :ONE-MINUS-DST-COLOR,
:DST-ALPHA, or :ONE-MINUS-DST-ALPHA. Operations are :ADD, :SUBTRACT,
:REV-SUBTRACT, :MINIMUM, or :MAXIMUM. SDL enum integers are accepted too.
The result can be assigned to DRAW-BLEND-MODE or TEXTURE-BLEND-MODE, when the
active renderer supports that combination."
  (let* ((color (%blend-triple color-mode))
         (alpha (%blend-triple alpha-mode))
         (sc (first color)) (dc (second color)) (co (third color))
         (sa (first alpha)) (da (second alpha)) (ao (third alpha)))
    (pixelisp.internal:check-video-thread)
    (pixelisp.internal:with-native-context
      (%compose-custom-blend-mode sc dc co sa da ao))))

(defun %read-renderer-info (info)
  "Copy SDL_RendererInfo into ordinary Lisp values while INFO is alive."
  (let* ((name-pointer (cffi:foreign-slot-value info '(:struct renderer-info) 'name))
         (name (unless (cffi:null-pointer-p name-pointer)
                 (cffi:foreign-string-to-lisp name-pointer :encoding :utf-8)))
         (count (min 16 (cffi:foreign-slot-value info '(:struct renderer-info) 'num-texture-formats)))
         (formats (cffi:foreign-slot-pointer info '(:struct renderer-info) 'texture-formats)))
    (list :name name
          :flags (cffi:foreign-slot-value info '(:struct renderer-info) 'flags)
          :num-texture-formats count
          :texture-formats (loop for i below count collect (cffi:mem-aref formats :uint32 i))
          :max-texture-width (cffi:foreign-slot-value info '(:struct renderer-info) 'max-texture-width)
          :max-texture-height (cffi:foreign-slot-value info '(:struct renderer-info) 'max-texture-height))))

(defun get-drivers ()
  "Return the available SDL 2D renderer drivers as a list of property lists.

Each plist has :NAME, :FLAGS, :NUM-TEXTURE-FORMATS, :TEXTURE-FORMATS,
:MAX-TEXTURE-WIDTH, and :MAX-TEXTURE-HEIGHT. This query opens no window."
  (pixelisp.internal:check-video-thread)
  (pixelisp.internal:with-native-context
    (let ((count (%get-num-render-drivers)))
      (when (minusp count) (pixelisp.internal:native-error 'get-drivers))
      (loop for index below count collect
        (cffi:with-foreign-object (info '(:struct renderer-info))
          (pixelisp.devices.internal:check-code (%get-render-driver-info index info) 'get-drivers)
          (%read-renderer-info info))))))

(defun get-renderer-info (renderer)
  "Return capability information for an existing RENDERER as a plist."
  ;; Check the Lisp subtype before %pointer: foreign handles are not type-safe.
  (check-type renderer renderer)
  (pixelisp.internal:with-native-context
    (let ((pointer (%pointer renderer)))
      (cffi:with-foreign-object (info '(:struct renderer-info))
        (pixelisp.devices.internal:check-code (%get-renderer-info pointer info) 'get-renderer-info)
        (%read-renderer-info info)))))
