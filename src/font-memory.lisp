;;;; Fonts backed by encoded octets or caller-owned binary streams.
;;;; Loaded after MEDIA so its font class and native SDL_ttf bindings exist.
(in-package #:pixelisp.font)

(cffi:defcfun ("TTF_OpenFontRW" %open-font-rw) :pointer
  (source :pointer) (freesrc :int) (point-size :int))
(cffi:defcfun ("TTF_CloseFont" %close-raw-font) :void (font :pointer))

(defun %font-source-octets (source)
  "Return encoded font octets, copying a binary stream from its current position."
  (cond
    ((typep source '(vector (unsigned-byte 8))) source)
    ((streamp source)
     (unless (and (input-stream-p source)
                  (subtypep (stream-element-type source) '(unsigned-byte 8)))
       (error 'simple-type-error :datum source :expected-type 'stream
              :format-control "Expected a binary input stream containing font octets; received ~S"
              :format-arguments (list source)))
     (let ((octets (make-array 0 :element-type '(unsigned-byte 8)
                               :adjustable t :fill-pointer 0)))
       (loop for octet = (read-byte source nil nil)
             while octet do (vector-push-extend octet octets))
       octets))
    (t (error 'type-error :datum source
              :expected-type '(or (vector (unsigned-byte 8)) stream)))))

(defun %make-font-from-source (source point-size)
  "Create an SDL_ttf font while retaining its RWops and immutable native copy."
  ;; Read and validate all Lisp-side input before initializing SDL_ttf or
  ;; allocating memory, so errors cannot strand partially-created resources.
  (check-type point-size (integer 1 #x7fffffff))
  (let* ((octets (%font-source-octets source))
         (length (length octets)))
    (when (zerop length)
      (error 'pixelisp:error :operation 'make-font :message "Font data is empty"))
    (when (> length #x7fffffff)
      (error 'pixelisp:error :operation 'make-font
             :message "Font data exceeds SDL's supported size"))
    (init)
    (let ((memory nil) (rwops nil) (native nil) (font-wrapper nil) (complete nil))
      (unwind-protect
           (progn
             ;; SDL_RWFromConstMem does not copy. Keep this private copy alive
             ;; because SDL_ttf can read it later when glyphs are requested.
             (setf memory (cffi:foreign-alloc :uint8 :count length))
             (dotimes (index length)
               (setf (cffi:mem-aref memory :uint8 index) (aref octets index)))
             (setf rwops (pixelisp.image::%rw-from-const-mem memory length))
             (when (cffi:null-pointer-p rwops)
               (error 'pixelisp:error :operation 'make-font
                      :message (or (pixelisp.image::%sdl-error)
                                   "Unable to create font byte stream")))
             ;; freesrc=0: this resource closes the RWops after TTF_CloseFont.
             (setf native (%open-font-rw rwops 0 point-size))
             (when (cffi:null-pointer-p native)
               (error 'pixelisp:error :operation 'make-font
                      :message (or (pixelisp.image::%sdl-error)
                                   "Unsupported or malformed font data")))
             ;; The binding API expects its typed autowrap wrapper. The raw
             ;; CFFI pointer returned above has no binding finalizer to cancel.
             (setf font-wrapper (autowrap:wrap-pointer native 'sdl2-ffi:ttf-font))
             (let ((resource
                     (pixelisp.internal:register-resource
                      (make-instance 'font :handle font-wrapper :path nil
                                     :point-size point-size
                                     :rwops rwops :memory memory))))
               (setf complete t)
               resource))
        (unless complete
          ;; The font never took ownership of either the RWops or allocation.
          (cond (font-wrapper (sdl2-ttf:close-font font-wrapper))
                ((and native (not (cffi:null-pointer-p native)))
                 (%close-raw-font native)))
          (when (and rwops (not (cffi:null-pointer-p rwops)))
            (pixelisp.image::%rw-close rwops))
          (when memory (cffi:foreign-free memory)))))))

(defun load-font-bytes (octets point-size)
  "Open a font from encoded octets, retaining a native copy until it is closed."
  (unless (typep octets '(vector (unsigned-byte 8)))
    (error 'type-error :datum octets :expected-type '(vector (unsigned-byte 8))))
  (%make-font-from-source octets point-size))
