;;;; Display selection and mode queries use SDL's public mode descriptions.
;;;; Querying a mode never creates a window or changes the monitor resolution.
(in-package #:pixelisp.display)

(cffi:defcfun ("SDL_GetClosestDisplayMode" %closest-display-mode) :pointer
  (display :int) (requested :pointer) (closest :pointer))
(cffi:defcfun ("SDL_MasksToPixelFormatEnum" %mode-pixel-format) :uint32
  (depth :int) (red :uint32) (green :uint32) (blue :uint32) (alpha :uint32))

(defun %resolved-display-size (size display)
  "Return validated drawing dimensions, replacing zero axes with desktop sizes."
  (%check-display-index display 'set-mode)
  (multiple-value-bind (width height) (pixelisp.internal:pair size)
    (check-type width (integer 0 2147483647))
    (check-type height (integer 0 2147483647))
    (when (or (zerop width) (zerop height))
      (multiple-value-bind (format desktop-width desktop-height refresh)
          (%mode-values display #'%desktop-display-mode 'set-mode)
        (declare (ignore format refresh))
        (when (zerop width) (setf width desktop-width))
        (when (zerop height) (setf height desktop-height))))
    (check-type width (integer 1 2147483647))
    (check-type height (integer 1 2147483647))
    (values width height)))

(defun %requested-mode-format (depth)
  "Map pygame's standard depth hints to SDL RGB masks; NIL means unsupported."
  (let ((masks (case depth
                 (8 '(0 0 0)) (12 '(#xf00 #x0f0 #x00f))
                 (15 '(#x7c00 #x03e0 #x001f)) (16 '(#xf800 #x07e0 #x001f))
                 ((24 32) '(#xff0000 #x00ff00 #x0000ff)))))
    (when masks (apply #'%mode-pixel-format depth (append masks '(0))))))

(defun %mode-depth (format)
  "Read SDL_BITSPERPIXEL from a mode's format enum, as pygame MODE_OK does."
  ;; RGB888 carries 24 significant bits in four bytes of storage. The enum
  ;; reports 24 here; SDL_PixelFormatEnumToMasks can report its 32-bit storage.
  (ldb (byte 8 8) format))

(defun mode-ok (size &key flags (depth 0) (display 0) fullscreen)
  "Return the closest native pixel depth, or 0 when no suitable mode is found.
Fullscreen requests require an exact size. Like pygame's SDL2 implementation,
other window flags are ignored; this is a mode query, not a window-creation test."
  (%check-display-index display 'mode-ok)
  (check-type depth (signed-byte 32))
  (check-type flags list)
  (check-type fullscreen boolean)
  (multiple-value-bind (width height) (pixelisp.internal:pair size)
    (check-type width (integer 0 2147483647))
    (check-type height (integer 0 2147483647))
    (let ((requested-format (if (zerop depth) 0 (%requested-mode-format depth)))
          (fullscreen (or fullscreen (member :fullscreen flags) (member :fullscreen-desktop flags))))
      (unless requested-format (return-from mode-ok 0))
      (cffi:with-foreign-objects ((requested '(:struct %display-mode)) (closest '(:struct %display-mode)))
        (cffi:with-foreign-slots ((format w h refresh-rate driverdata) requested (:struct %display-mode))
          (setf format requested-format
                w width h height refresh-rate 0 driverdata (cffi:null-pointer)))
        (let ((match (%closest-display-mode display requested closest)))
          (when (cffi:null-pointer-p match)
            (return-from mode-ok (if fullscreen 0 (%mode-depth requested-format))))
          (when (and fullscreen
                     (or (/= width (cffi:foreign-slot-value closest '(:struct %display-mode) 'w))
                         (/= height (cffi:foreign-slot-value closest '(:struct %display-mode) 'h))))
            (return-from mode-ok 0))
          (%mode-depth (cffi:foreign-slot-value closest '(:struct %display-mode) 'format)))))))
