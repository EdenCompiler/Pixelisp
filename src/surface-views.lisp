;;;; Pygame-style scoped views over native surface storage.
;;;; The returned views retain and lock their surface until explicitly closed.
(in-package #:pixelisp.surface)

(defun %view-pixel-address (surface x y)
  "Address a pixel using the native byte depth and row pitch."
  (let ((handle (pixelisp.internal:surface-handle surface)))
    (cffi:inc-pointer (sdl2:surface-pixels handle)
                      (+ (* y (sdl2:surface-pitch handle))
                         (* x (get-bytesize surface))))))

(defun %view-byte-order ()
  "Return the host byte order used by SDL's packed native pixels."
  (cffi:with-foreign-object (word :uint32)
    (setf (cffi:mem-ref word :uint32) #x01020304)
    (if (= (cffi:mem-ref word :uint8) 4) :little :big)))

(defun %view-read-pixel (surface x y)
  "Read one packed native pixel, including the three-byte 24-bit case."
  (let* ((address (%view-pixel-address surface x y))
         (bytes (get-bytesize surface))
         (order (%view-byte-order)))
    (loop for index below bytes
          sum (ash (cffi:mem-ref (cffi:inc-pointer address index) :uint8)
                   (* 8 (if (eq order :little) index (- bytes index 1)))))))

(defun %view-write-pixel (surface x y value)
  "Write one packed native pixel without applying the drawing clip."
  (let* ((bytes (get-bytesize surface))
         (maximum (1- (ash 1 (* bytes 8))))
         (address (%view-pixel-address surface x y))
         (order (%view-byte-order)))
    (unless (and (integerp value) (<= 0 value maximum))
      (error 'type-error :datum value :expected-type `(integer 0 ,maximum)))
    (dotimes (index bytes value)
      (setf (cffi:mem-ref (cffi:inc-pointer address index) :uint8)
            (ldb (byte 8 (* 8 (if (eq order :little) index (- bytes index 1)))) value)))))

(defun %view-channel-offset (surface channel)
  "Return CHANNEL's byte position within a native pixel, or NIL if absent."
  (when (member (get-bitsize surface) '(24 32))
    (let* ((mask (nth (position channel '(:red :green :blue :alpha)) (get-masks surface)))
           (shift (%mask-shift mask)))
      (when (and (= 8 (logcount mask)) (zerop (mod shift 8)))
        (if (eq (%view-byte-order) :little) (/ shift 8)
            (- (get-bytesize surface) 1 (/ shift 8)))))))

(defun %view-kind (kind)
  "Normalize pygame's one-character string or character view selector."
  (let ((character (cond ((characterp kind) kind)
                         ((and (stringp kind) (= (length kind) 1)) (char kind 0))
                         (t (error "Surface view kind must be one character: ~S." kind)))))
    (let ((normalized (char-downcase character)))
      (unless (find normalized "0123rgba")
        (error "Unsupported surface view kind ~S; expected 0, 1, 2, 3, r, g, b, or a." kind))
      normalized)))

(defun %make-surface-view (surface kind)
  "Build one locked view, attaching its unlock action during construction."
  (let* ((width (width surface))
         (height (height surface))
         (bytes (get-bytesize surface))
         (pitch (get-pitch surface))
         (contiguous-p (= pitch (* width bytes)))
         (count (* width height)))
    (labels ((make-locked-view (&rest arguments)
               (apply (if (char= kind #\2)
                          #'px.buffer::%make-packed-view
                          #'px.buffer:make-view)
                      :owner surface :releaser (lambda () (unlock surface)) arguments))
             (pixel-type () (list 'unsigned-byte (* 8 bytes)))
             (pixel (x y) (%view-read-pixel surface x y))
             (set-pixel (value x y) (%view-write-pixel surface x y value))
             (linear-pixel (index)
               (pixel (mod index width) (floor index width)))
             (set-linear-pixel (value index)
               (set-pixel value (mod index width) (floor index width)))
             (byte-at (offset) (cffi:mem-ref (cffi:inc-pointer
                                              (sdl2:surface-pixels
                                               (pixelisp.internal:surface-handle surface))
                                              offset) :uint8)))
      (case kind
        ;; Raw bytes have no shape and are available only for contiguous rows.
        (#\0
         (unless contiguous-p
           (error 'pixelisp:unsupported-feature :operation 'get-view
                  :message "Kind 0 requires a contiguous surface pixel layout."))
         (make-locked-view :dimensions (list (* count bytes)) :strides '(1)
           :element-type '(unsigned-byte 8)
           :reader (lambda (index) (byte-at index))
           :writer (lambda (value index)
                     (check-type value (unsigned-byte 8))
                     (setf (cffi:mem-ref (cffi:inc-pointer
                                          (sdl2:surface-pixels
                                           (pixelisp.internal:surface-handle surface)) index)
                                         :uint8) value))))
        ;; One continuous sequence of native packed pixels.
        (#\1
         (unless contiguous-p
           (error 'pixelisp:unsupported-feature :operation 'get-view
                  :message "Kind 1 requires a contiguous surface pixel layout."))
         (make-locked-view :dimensions (list count) :strides (list bytes)
           :element-type (pixel-type)
           :reader #'linear-pixel :writer #'set-linear-pixel))
        ;; Two-dimensional packed pixels keep native row pitch and pixel stride.
        (#\2
         (make-locked-view :dimensions (list width height)
           :strides (list bytes pitch) :element-type (pixel-type)
           :reader #'pixel :writer #'set-pixel))
        (#\3
         (unless (member (get-bitsize surface) '(24 32))
           (error 'pixelisp:unsupported-feature :operation 'get-view
                  :message "Kind 3 supports only 24-bit and 32-bit surfaces."))
         (let* ((offsets (mapcar (lambda (channel) (%view-channel-offset surface channel))
                                 '(:red :green :blue)))
                (step (and (every #'integerp offsets)
                           (- (second offsets) (first offsets)))))
           (unless (and step (member step '(-1 1))
                        (= step (- (third offsets) (second offsets))))
             (error 'pixelisp:unsupported-feature :operation 'get-view
                    :message "Kind 3 requires adjacent RGB or BGR bytes in each pixel."))
           (make-locked-view :dimensions (list width height 3)
             :strides (list bytes pitch step) :byte-offset (first offsets)
             :element-type '(unsigned-byte 8)
             :reader (lambda (x y component)
                       (cffi:mem-ref (cffi:inc-pointer (%view-pixel-address surface x y)
                                                       (nth component offsets)) :uint8))
             :writer (lambda (value x y component)
                       (check-type value (unsigned-byte 8))
                       (setf (cffi:mem-ref (cffi:inc-pointer (%view-pixel-address surface x y)
                                                            (nth component offsets)) :uint8)
                             value)))))
        (otherwise
         (let* ((channel (ecase kind (#\r :red) (#\g :green) (#\b :blue) (#\a :alpha)))
                (offset (%view-channel-offset surface channel)))
           (when (and (eq channel :alpha)
                      (not (and (alpha-p surface) (= (get-bitsize surface) 32))))
             (setf offset nil))
           (unless offset
             (error 'pixelisp:unsupported-feature :operation 'get-view
                    :message (format nil "This surface format has no ~A byte plane."
                                     (string-upcase (symbol-name channel)))))
           (make-locked-view :dimensions (list width height)
             :strides (list bytes pitch) :byte-offset offset
             :element-type '(unsigned-byte 8)
             :reader (lambda (x y)
                       (cffi:mem-ref (cffi:inc-pointer (%view-pixel-address surface x y) offset)
                                     :uint8))
             :writer (lambda (value x y)
                       (check-type value (unsigned-byte 8))
                       (setf (cffi:mem-ref (cffi:inc-pointer (%view-pixel-address surface x y) offset)
                                           :uint8) value)))))))))

(defun %surface-buffer-length (surface)
  "Return the raw view extent without crossing the root allocation boundary."
  (let* ((root (get-abs-parent surface))
         (root-pitch (get-pitch root))
         (root-bytes (* root-pitch (height root)))
         (offset (get-abs-offset surface))
         (byte-offset (+ (* (second offset) root-pitch)
                         (* (first offset) (get-bytesize root))))
         (available (max 0 (- root-bytes byte-offset))))
    ;; A cropped child keeps its parent's pitch. Clamp its nominal pitch*height
    ;; block to the bytes that remain in the top-level pixel allocation.
    (min (* (height surface) (get-pitch surface)) available)))

(defun get-buffer (surface)
  "Return a locked byte view covering native pixels and row padding.
For a cropped subsurface, truncate any final padding that would cross the
top-level owner allocation. Close the view with PX.BUFFER:CLOSE."
  (check-surface surface)
  (lock surface)
  (handler-case
      (let* ((length (%surface-buffer-length surface))
             (pixels (sdl2:surface-pixels (pixelisp.internal:surface-handle surface)))
             (view (px.buffer:make-view
                    :owner surface :dimensions (list length) :strides '(1)
                    :element-type '(unsigned-byte 8)
                    :reader (lambda (index) (cffi:mem-ref (cffi:inc-pointer pixels index) :uint8))
                    :writer (lambda (value index)
                              (check-type value (unsigned-byte 8))
                              (setf (cffi:mem-ref (cffi:inc-pointer pixels index) :uint8) value))
                    :releaser (lambda () (unlock surface)))))
        view)
    (error (condition) (unlock surface) (error condition))))

(defun get-view (surface &optional (kind #\2))
  "Return an owner-backed native pixel view selected by pygame's KIND codes.

Kind 0 is contiguous raw bytes, 1 is a contiguous sequence of pixels, 2 is
two-dimensional packed pixels, 3 is RGB channels, and r/g/b/a select a single
channel. Views lock their surface until closed with PX.BUFFER:CLOSE."
  (check-surface surface)
  (let ((kind (%view-kind kind)))
    (lock surface)
    (handler-case
        (%make-surface-view surface kind)
      (error (condition) (unlock surface) (error condition)))))
