;;;; Encoded image output, separate from raw RGB/RGBA pixel byte conversion.
;;;; Native codecs write into a growable C-owned SDL stream. Lisp only copies
;;;; the result: no callback enters Lisp and no temporary file is needed.
(in-package #:pixelisp.image)

(cffi:defcfun ("px_image_encode" %encode-memory) :int
  (surface :pointer) (format :int) (codec :pointer) (quality :int)
  (output :pointer) (length :pointer))
(cffi:defcfun ("px_image_bytes_free" %encoded-bytes-free) :void (bytes :pointer))

(defun %output-kind (hint)
  "Choose a codec from a filename/extension; pygame defaults to TGA."
  (unless (or (null hint) (stringp hint) (symbolp hint) (pathnamep hint))
    (error 'type-error :datum hint :expected-type '(or null string symbol pathname)))
  (let* ((text (cond ((null hint) "") ((pathnamep hint) (namestring hint))
                     (t (string hint))))
         (extension (string-downcase (or (pathname-type text) text))))
    (cond ((string= extension "png") :png)
          ((member extension '("jpg" "jpeg") :test #'string=) :jpeg)
          ((string= extension "bmp") :bmp)
          (t :tga))))

(defun %tga-bytes (surface)
  "Write top-to-bottom 24/32-bit true-color TGA in portable Lisp."
  (px.surface::check-surface surface)
  (let* ((width (px.surface:width surface)) (height (px.surface:height surface))
         (alpha (not (zerop (fourth (px.surface:get-masks surface)))))
         (channels (if alpha 4 3)))
    (unless (and (<= width 65535) (<= height 65535))
      (error 'pixelisp:unsupported-feature :operation 'save
             :message "TGA dimensions cannot exceed 65535 pixels on either axis"))
    (let ((bytes (make-array (+ 18 (* width height channels))
                             :element-type '(unsigned-byte 8) :initial-element 0)))
      ;; TGA uses a little-endian header followed by BGR or BGRA pixels.
      (setf (aref bytes 2) 2                   ; uncompressed true-color image
            (aref bytes 12) (ldb (byte 8 0) width)
            (aref bytes 13) (ldb (byte 8 8) width)
            (aref bytes 14) (ldb (byte 8 0) height)
            (aref bytes 15) (ldb (byte 8 8) height)
            (aref bytes 16) (* 8 channels)
            (aref bytes 17) (logior #x20 (if alpha 8 0))) ; top-left origin
      (replace bytes (to-bytes surface (if alpha :bgra :bgr)) :start1 18)
      bytes)))

(defun %output-codec (kind)
  "Resolve optional SDL_image encoders only when requested."
  (if (eq kind :bmp) (cffi:null-pointer)
      (let* ((name (ecase kind (:png "IMG_SavePNG_RW") (:jpeg "IMG_SaveJPG_RW")))
             (function (ignore-errors (cffi:foreign-symbol-pointer name))))
        (when (or (null function) (cffi:null-pointer-p function))
          (error 'pixelisp:unsupported-feature :operation 'save-bytes
                 :message (format nil "The loaded SDL_image does not provide ~A" name)))
        function)))

(defun %native-image-bytes (surface kind quality)
  "Encode once, copy into an octet vector, and release temporary native bytes."
  (let ((surface-pointer (pixelisp.internal:%ptr (pixelisp.internal:surface-handle surface)))
        (codec (%output-codec kind)))
    (pixelisp.native:ensure-loaded)
    (cffi:with-foreign-objects ((output :pointer) (length :size))
      (setf (cffi:mem-ref output :pointer) (cffi:null-pointer)
            (cffi:mem-ref length :size) 0)
      (unwind-protect
           (progn
             (when (minusp (%encode-memory surface-pointer
                                           (ecase kind (:bmp 0) (:png 1) (:jpeg 2))
                                           codec (if (eq kind :jpeg) quality 0) output length))
               (error 'pixelisp:error :operation 'save-bytes
                      :message (pixelisp.native:last-error)))
             (let* ((size (cffi:mem-ref length :size))
                    (pointer (cffi:mem-ref output :pointer))
                    (bytes (make-array size :element-type '(unsigned-byte 8))))
               (dotimes (index size bytes)
                 (setf (aref bytes index) (cffi:mem-aref pointer :uint8 index)))))
        (let ((pointer (cffi:mem-ref output :pointer)))
          (unless (cffi:null-pointer-p pointer) (%encoded-bytes-free pointer)))))))

(defun save-bytes (surface &key namehint (quality 90))
  "Return encoded file octets; NAMEHINT selects PNG/JPEG/BMP or defaults to TGA.
Unlike TO-BYTES, this returns a complete image file rather than raw pixels."
  (let ((kind (%output-kind namehint)))
    (when (eq kind :jpeg) (check-type quality (integer 0 100)))
    (if (eq kind :tga) (%tga-bytes surface)
        (%native-image-bytes surface kind quality))))

(defun save (surface destination &key namehint (quality 90))
  "Save to a pathname or caller-owned binary output stream.
NAMEHINT selects a stream's encoding; filenames use their own extensions."
  (etypecase destination
    (stream
     (unless (and (output-stream-p destination)
                  (subtypep (stream-element-type destination) '(unsigned-byte 8)))
       (error 'simple-type-error :datum destination :expected-type 'stream
              :format-control "Expected a binary output stream; received ~S"
              :format-arguments (list destination)))
     ;; Finish encoding before writing: argument/codec errors leave it untouched.
     (write-sequence (save-bytes surface :namehint namehint :quality quality) destination))
    ((or string pathname)
     (let ((kind (%output-kind destination)))
       (if (eq kind :tga)
           (let ((bytes (%tga-bytes surface)))
             (with-open-file (stream destination :direction :output :if-exists :supersede
                                                :element-type '(unsigned-byte 8))
               (write-sequence bytes stream)))
           (%save-file surface destination quality)))))
  destination)
