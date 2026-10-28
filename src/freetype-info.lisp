;;;; Read-only face information lives apart from the glyph layout code.
;;;; Every native value is copied before returning; callers never borrow a
;;;; FreeType structure or need to know its fixed-point representation.
(in-package #:pixelisp.freetype)

(export '(fixed-width-p fixed-sizes scalable-p height ascender descender
          get-sized-glyph-height get-sizes))

(defun %info-face (font)
  "Validate FONT without resizing it or replacing its current glyph slot."
  (check-type font font)
  (pixelisp.internal:ensure-live font)
  (pixelisp.internal:handle font))

(defun fixed-width-p (font)
  "Whether the face declares all characters to have the same advance."
  (not (null (member :fixed-width
                     (freetype2-types:ft-face-face-flags (%info-face font))))))

(defun scalable-p (font)
  "Whether FONT contains scalable outlines, rather than only bitmap strikes."
  (not (null (member :scalable
                     (freetype2-types:ft-face-face-flags (%info-face font))))))

(defun fixed-sizes (font)
  "Return the number of embedded bitmap sizes, including those in outline fonts."
  (freetype2-types:ft-face-num-fixed-sizes (%info-face font)))

(defun height (font)
  "Return the unscaled distance between baselines, in font units."
  (freetype2-types:ft-face-height (%info-face font)))

(defun ascender (font)
  "Return the unscaled ascent above the baseline, in font units."
  (freetype2-types:ft-face-ascender (%info-face font)))

(defun descender (font)
  "Return the unscaled descent, normally negative, in font units."
  (freetype2-types:ft-face-descender (%info-face font)))

(defun get-sized-glyph-height (font &optional size)
  "Return the ascent-to-descent span in pixels, including one baseline row.

Like pygame, this uses face metrics; it does not measure a particular string
or include synthetic styles. SIZE temporarily selects the point size at FONT's DPI
and leaves the font's default SIZE property unchanged."
  (let* ((face (%face font size))
         (metrics (freetype2-types:ft-size-metrics
                   (freetype2-types:ft-face-size face))))
    ;; FreeType stores these coordinates in signed 26.6 fractional pixels.
    (1+ (- (ceiling (freetype2-types:ft-size-metrics-ascender metrics) 64)
           (floor (freetype2-types:ft-size-metrics-descender metrics) 64)))))

(defun get-sizes (font)
  "Return bitmap strike records (point-size height width x-ppem y-ppem).

The first three values are integers; ppem values are fractional pixels.
An outline-only face returns NIL. Each call returns fresh Lisp lists."
  (let* ((face (%info-face font))
         (count (freetype2-types:ft-face-num-fixed-sizes face))
         ;; Read the binding's native array directly. Its convenience accessor
         ;; exposes borrowed wrappers; keeping that array private also makes
         ;; the ownership of the returned records unambiguous.
         (sizes (cffi:mem-ref
                 (cffi:foreign-slot-pointer
                   (freetype2-types:w* face)
                   '(:struct freetype2-types::foreign-ft-facerec)
                   'freetype2-types::available-sizes)
                 :pointer)))
    (loop for index below count
          for record = (cffi:mem-aptr sizes
                         '(:struct freetype2-types::foreign-ft-bitmap-size) index)
          collect
          (flet ((field (name)
                   (cffi:foreign-slot-value record
                     '(:struct freetype2-types::foreign-ft-bitmap-size) name)))
            (list (floor (+ (field 'freetype2-types::size) 32) 64)
                  (field 'freetype2-types::height)
                  (field 'freetype2-types::width)
                  (/ (field 'freetype2-types::x-ppem) 64.0d0)
                  (/ (field 'freetype2-types::y-ppem) 64.0d0))))))
