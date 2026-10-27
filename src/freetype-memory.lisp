;;;; Direct FreeType sources and their ownership boundary.
;;;; Keep encoded bytes alive until the native face is closed: unlike a decoded
;;;; image, a font can read its source again whenever a new glyph is requested.
(in-package #:pixelisp.freetype)

(defun %checked-native-long (index)
  "Validate the FT_Long argument before crossing the native boundary."
  (let ((maximum (1- (ash 1 (1- (* 8 (cffi:foreign-type-size :long)))))))
    (unless (typep index `(integer 0 ,maximum))
      (error 'type-error :datum index :expected-type `(integer 0 ,maximum)))
    index))

(defun %release-face (face)
  "Close the face and its binding-owned pointer cell exactly once."
  ;; cl-freetype2 installs a finalizer on its wrapper. Pixelisp owns explicit
  ;; disposal, so cancel it both on success and on failed construction.
  (trivial-garbage:cancel-finalization face)
  (let ((storage (freetype2-types:fw-ptr face)))
    (unless (cffi:null-pointer-p storage)
      (freetype2-ffi:ft-done-face (freetype2-types:w* face))
      (freetype2-types:libc-free storage)
      (setf (freetype2-types:fw-ptr face) (cffi:null-pointer)))))

(defun %release-font-memory (memory)
  "Release encoded source storage, after its borrowing face has been closed."
  (when memory (cffi:foreign-free memory)))

(defun %new-memory-face (memory length index)
  "Create the binding's typed face wrapper with explicit native ownership."
  ;; The binding stores FT_Face in a separately allocated pointer cell. Use its
  ;; allocator so %RELEASE-FACE can release path and memory faces identically.
  ;; No finalizer is installed here: the constructor below owns every failure.
  (let ((storage (freetype2-types:libc-calloc (cffi:foreign-type-size :pointer) 1))
        (complete nil))
    (when (cffi:null-pointer-p storage)
      (error 'pixelisp:error :operation 'make-font :message "Unable to allocate a font face handle"))
    (unwind-protect
         (progn
           (freetype2-types:ft-error
             (freetype2-ffi:ft-new-memory-face freetype2:*library* memory length index storage))
           (let ((face (freetype2-types:%make-ft-face :ptr storage)))
             (setf complete t)
             face))
      (unless complete
        (unless (cffi:null-pointer-p (cffi:mem-ref storage :pointer))
          (freetype2-ffi:ft-done-face (cffi:mem-ref storage :pointer)))
        (freetype2-types:libc-free storage)))))

(defun %make-font-from-source (source size index kerning antialiased)
  "Transfer a successfully configured face and its optional bytes to a font."
  (%checked-native-long index)
  (%size-axes size)
  (let* ((path (cond ((null source) (namestring (get-default-font)))
                     ((or (pathnamep source) (stringp source)) (namestring (pathname source)))
                     ((or (streamp source) (typep source '(vector (unsigned-byte 8)))) nil)
                     (t (error 'type-error :datum source
                               :expected-type '(or null pathname string stream
                                                   (vector (unsigned-byte 8)))))))
         ;; Reuse the binary-input rules from SDL_ttf: read from the caller's
         ;; current stream position, leave it open, and never retain the stream.
         (octets (unless path (pixelisp.font::%font-source-octets source)))
         (length (when octets (length octets)))
         (memory nil) (face nil) (complete nil))
    (when (and length (zerop length))
      (error 'pixelisp:error :operation 'make-font :message "Font data is empty"))
    (when length (%checked-native-long length))
    (init)
    (unwind-protect
         (progn
           (when octets
             ;; FT_New_Memory_Face borrows this address; the private native copy
             ;; isolates glyph loading from later mutation of a Lisp vector.
             (setf memory (cffi:foreign-alloc :uint8 :count length))
             (when (cffi:null-pointer-p memory)
               (error 'pixelisp:error :operation 'make-font :message "Unable to allocate encoded font storage"))
             (dotimes (i length)
               (setf (cffi:mem-aref memory :uint8 i) (aref octets i))))
           (setf face
                 (handler-case
                     (if path (freetype2:new-face path index)
                         (%new-memory-face memory length index))
                   (error (condition)
                     (error 'pixelisp:error :operation 'make-font
                            :message (format nil "Unable to open font face ~D: ~A" index condition)))))
           ;; Take ownership before sizing. A failed bitmap-size request must
           ;; close the face before its encoded storage is freed, too.
           (trivial-garbage:cancel-finalization face)
           ;; FreeType packs variation-instance bits into its native index.
           ;; This API selects collection faces only; do not let a huge index
           ;; silently alias face zero when the native library ignores bits.
           (unless (< index (freetype2-types:ft-face-num-faces face))
             (error 'pixelisp:error :operation 'make-font
                    :message "Font index is outside the source collection"))
           (%set-face-size face size)
           (let ((font (pixelisp.internal:register-resource
                        (make-instance 'font :handle face :path (when path (copy-seq path))
                                       :memory memory :font-index index :size size
                                       :kerning kerning :antialiased antialiased))))
             (setf complete t)
             font))
      (unless complete
        (unwind-protect (when face (%release-face face))
          (%release-font-memory memory))))))

(defun load-font-bytes (octets &optional (size 16) &key (font-index 0) (kerning t) (antialiased t))
  "Open encoded font octets, retaining an independent copy until disposal."
  (check-type octets (vector (unsigned-byte 8)))
  (make-font octets size :font-index font-index :kerning kerning :antialiased antialiased))

(defun path (font)
  "Return a fresh source namestring, or NIL for an in-memory font."
  (check-type font font)
  (pixelisp.internal:ensure-live font)
  (when (%path font) (copy-seq (%path font))))

(defun font-index (font)
  "Return the collection face index requested when FONT was opened."
  (check-type font font)
  (pixelisp.internal:ensure-live font)
  (%font-index font))

(defun num-faces (font)
  "Return the number of faces in FONT's source file or memory collection."
  (freetype2-types:ft-face-num-faces (%info-face font)))
