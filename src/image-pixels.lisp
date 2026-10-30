;;;; Raw image transfer is separate from encoded image-file loading.
;;;; P bytes are palette indices, never palette RGB values. Shared imports own
;;;; SDL's metadata while the caller continues to own the backing allocation.
(in-package #:pixelisp.image)

(cffi:defcfun ("SDL_CreateRGBSurfaceFrom" %surface-from-masks) :pointer
  (pixels :pointer) (width :int) (height :int) (depth :int) (pitch :int)
  (red :uint32) (green :uint32) (blue :uint32) (alpha :uint32))

(defun %format (format &optional (operation 'from-string))
  (unless (or (stringp format) (symbolp format))
    (error 'type-error :datum format :expected-type '(or string symbol)))
  (let ((name (substitute #\_ #\- (string-upcase (string format)))))
    (unless (member name (if (eq operation 'to-string)
                             '("P" "RGB" "RGBA" "RGBX" "ARGB" "BGRA" "BGR"
                               "RGBA_PREMULT" "ARGB_PREMULT")
                             '("P" "RGB" "RGBA" "RGBX" "ARGB" "BGRA" "BGR"))
                    :test #'string=)
      (error 'pixelisp:unsupported-feature :operation operation
             :message (if (eq operation 'to-string)
                          "Use P, RGB, RGBA, RGBX, ARGB, BGRA, BGR, RGBA_PREMULT or ARGB_PREMULT output bytes."
                          "Use P, RGB, RGBA, RGBX, ARGB, BGRA or BGR pixel bytes.")))
    name))

(defun %pixel-dimensions (size bytes-per-pixel &optional (operation 'from-string))
  "Validate SDL's signed integer dimensions and tightly packed row pitch."
  (multiple-value-bind (width height) (pixelisp.internal:pair size)
    (check-type width (integer 1 #x7fffffff))
    (check-type height (integer 1 #x7fffffff))
    (let ((pitch (* width bytes-per-pixel)))
      (when (> pitch #x7fffffff)
        (error 'pixelisp:error :operation operation
               :message "The packed image row exceeds SDL's integer pitch range."))
      (values width height pitch))))

(defun %white-indexed-palette (surface)
  ;; P assets contain no palette. Pygame creates all-white palette entries;
  ;; callers install their saved palette separately after copying or sharing.
  (px.surface:set-palette surface (make-list 256 :initial-element '(255 255 255)))
  surface)

(defun from-string (bytes size format &optional flipped)
  "Copy tightly packed pixels into an owned surface; FLIPPED reverses rows.
P creates an indexed 8-bit surface with a white palette; other formats use the
standard 32-bit drawing format. The input vector is never retained."
  (unless (typep bytes '(vector (unsigned-byte 8)))
    (error 'type-error :datum bytes :expected-type '(vector (unsigned-byte 8))))
  (let* ((fmt (%format format)) (channels (length fmt)) (indexed (string= fmt "P")))
    (multiple-value-bind (width height pitch) (%pixel-dimensions size channels)
      ;; Reject malformed input before allocating any native resource.
      (unless (= (length bytes) (* pitch height))
        (error 'pixelisp:error :operation 'from-string
               :message "Pixel byte count does not match dimensions."))
      (let ((surface (px.surface:make-surface size :depth (if indexed 8 32)
                                                  :alpha (not (null (find #\A fmt)))))
            (complete nil))
        (unwind-protect
             (progn
               (when indexed (%white-indexed-palette surface))
               (px.surface:lock surface)
               (unwind-protect
                    (dotimes (y height)
                      (dotimes (x width)
                        (let ((offset (* channels (+ x (* width (if flipped (- height 1 y) y))))))
                          (if indexed
                              (px.surface::%write-packed-pixel surface x y (aref bytes offset))
                              (let ((color (loop for channel across "RGBA" collect
                                             (let ((index (position channel fmt)))
                                               (if index (aref bytes (+ offset index)) 255)))))
                                (pixelisp.internal:write-surface-pixel surface (list x y) color))))))
                 (px.surface:unlock surface))
               (setf complete t)
               surface)
          (unless complete (px:dispose surface)))))))

(defun to-string (surface format &optional flipped)
  "Copy tightly packed pixels to an octet vector, omitting row padding.
P returns exact 8-bit indices. Premultiplied exports use per-pixel alpha only."
  (px.surface::check-surface surface)
  (let* ((fmt (%format format 'to-string)) (indexed (string= fmt "P"))
         (premultiplied (member fmt '("RGBA_PREMULT" "ARGB_PREMULT") :test #'string=))
         (order (if premultiplied (subseq fmt 0 4) fmt))
         (channels (length order))
         (width (px.surface:width surface)) (height (px.surface:height surface)))
    (when (and indexed (/= 8 (px.surface:get-bitsize surface)))
      (error 'pixelisp:unsupported-feature :operation 'to-string
             :message "P output requires an indexed 8-bit surface."))
    (when (and premultiplied (zerop (fourth (px.surface:get-masks surface))))
      (error 'pixelisp:unsupported-feature :operation 'to-string
             :message "Premultiplied output requires a per-pixel alpha mask."))
    (let ((bytes (make-array (* width height channels) :element-type '(unsigned-byte 8))))
      (px.surface:lock surface)
      (unwind-protect
           (dotimes (y height bytes)
             (let ((source-y (if flipped (- height 1 y) y)))
               (dotimes (x width)
                 (let ((offset (* channels (+ x (* width y)))))
                   (if indexed
                       (setf (aref bytes offset) (px.surface::%read-packed-pixel surface x source-y))
                       (multiple-value-bind (r g b a)
                           (pixelisp.internal:rgba (px.surface:get-at surface (list x source-y)))
                         (when premultiplied
                           (setf r (floor (* r a) 255) g (floor (* g a) 255) b (floor (* b a) 255)))
                         (loop for channel across order for k from 0 do
                           (setf (aref bytes (+ offset k))
                                 (case channel (#\R r) (#\G g) (#\B b) (#\A a) (#\X 255))))))))))
        (px.surface:unlock surface)))))

(setf (fdefinition 'from-bytes) #'from-string (fdefinition 'to-bytes) #'to-string)

(defun %byte-channel-masks (format)
  "Describe byte order with masks instead of endian-specific SDL enum values."
  (let ((bytes (length format)) (little (eq :little (px.surface::%view-byte-order))))
    (loop for channel across "RGBA" collect
      (let ((position (position channel format)))
        (if position (ash #xff (* 8 (if little position (- bytes position 1)))) 0)))))

(defun from-buffer (pointer size format &key owner byte-count)
  "Share tightly packed foreign pixels; retain OWNER, but do not own its memory.
P, RGB/BGR and 32-bit channel orders are supported. The allocation must stay
valid and writable until disposal. A moving Lisp vector is not foreign storage."
  (unless (and (cffi:pointerp pointer) (not (cffi:null-pointer-p pointer)))
    (error 'type-error :datum pointer :expected-type 'cffi:foreign-pointer))
  (when byte-count (check-type byte-count (integer 0 *)))
  (when (typep owner 'pixelisp.internal:resource) (pixelisp.internal:ensure-live owner))
  (let* ((fmt (%format format 'from-buffer)) (bytes (length fmt)) (depth (* 8 bytes)))
    (multiple-value-bind (width height pitch) (%pixel-dimensions size bytes 'from-buffer)
      (when (and byte-count (< byte-count (* height pitch)))
        (error 'pixelisp:error :operation 'from-buffer :message "Foreign buffer is too short."))
      (destructuring-bind (red green blue alpha) (%byte-channel-masks fmt)
        (pixelisp.internal:with-native-context
          (let ((native (%surface-from-masks pointer width height depth pitch red green blue alpha)))
            (when (cffi:null-pointer-p native)
              (error 'pixelisp:error :operation 'from-buffer
                     :message (or (%sdl-error) "SDL rejected the pixel buffer.")))
            ;; WRAP-SURFACE consumes the SDL wrapper even if registration fails.
            ;; SDL_PREALLOC keeps the caller's pixel allocation outside disposal.
            (let ((surface (pixelisp.internal:wrap-surface native :owned t :parent owner
                                                                 :preserve-format t))
                  (complete nil))
              (unwind-protect
                   (progn
                     (when (string= fmt "P") (%white-indexed-palette surface))
                     (setf complete t)
                     surface)
                (unless complete (px:dispose surface))))))))))
