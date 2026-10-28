;;;; Deterministic tests for fontconfig inventory and fallback matching.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defparameter *sysfont-test-output*
  (format nil "/fonts/Alpha-Regular.ttf~CAlpha Family,Alpha Alias~CRegular~%~
          /fonts/Alpha-Bold.ttf~CAlpha Family~CBold~%~
          /fonts/Alpha-Italic.ttf~CAlpha Family~CItalic~%~
          /fonts/Alpha-BoldItalic.ttf~CAlpha Family~CBold Italic~%~
          /fonts/Beta.otf~CBeta Sans~CDemi~%~
          /fonts/Ignored.pfb~CUnsupported~CRegular~%~
          malformed row~%"
          #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab
          #\Tab #\Tab))

(defun %with-sysfont-config (output thunk)
  (let* ((symbol 'pixelisp.font::%fontconfig)
         (original (symbol-function symbol)))
    (unwind-protect
         (progn
           (setf (symbol-function symbol)
                 (lambda (program arguments)
                   (declare (ignore arguments))
                   (when (string= program "fc-list") output)))
           (pixelisp.font::%reset-font-inventory)
           (funcall thunk))
      (setf (symbol-function symbol) original)
      (pixelisp.font::%reset-font-inventory))))

(defun %sysfont-bundled-path ()
  (namestring (asdf:system-relative-pathname "pixelisp" "assets/fonts/DejaVuSans.ttf")))

(defun %sysfont-style-output (path &rest styles)
  (with-output-to-string (stream)
    (dolist (style styles)
      (format stream "~A~CPixelisp Test Family~C~A~%" path #\Tab #\Tab style))))

(test sysfont-inventory-normalizes-family-aliases-and-filters-files
  (%with-sysfont-config
   *sysfont-test-output*
   (lambda ()
     (is (equal '("alphaalias" "alphafamily" "betasans") (px.font:get-fonts)))
     (let ((names (px.font:get-fonts)))
       (setf (char (first names) 0) #\X)
       (is (equal '("alphaalias" "alphafamily" "betasans") (px.font:get-fonts))))
     (is (string= "/fonts/Alpha-Regular.ttf" (px.font:match-font "aLpHa Fa-mily")))
     (is (string= "/fonts/Alpha-Regular.ttf"
                  (px.font:match-font '("missing family" "Alpha Alias"))))
     (is (string= "/fonts/Alpha-Regular.ttf"
                  (px.font:match-font #("missing" "Alpha Family"))))
     (is (null (px.font:match-font nil)))
     (is (null (px.font:match-font "an unknown family")))
     (signals px:error (px.font:match-font (format nil "Alpha~CFamily" #\Nul)))
     (let ((path (px.font:match-font "Alpha Family")))
       (setf (char path 0) #\X)
       (is (string= "/fonts/Alpha-Regular.ttf"
                    (px.font:match-font "Alpha Family")))))))

(test sysfont-prefers-requested-installed-styles-and-falls-back-predictably
  (%with-sysfont-config
   *sysfont-test-output*
   (lambda ()
     (is (string= "/fonts/Alpha-Bold.ttf"
                  (px.font:match-font "Alpha Family" :bold t)))
     (is (string= "/fonts/Alpha-Italic.ttf"
                  (px.font:match-font "Alpha Family" :italic t)))
     (is (string= "/fonts/Alpha-BoldItalic.ttf"
                  (px.font:match-font "Alpha Family" :bold t :italic t)))
     ;; A family with only a demi-bold face can satisfy the requested bold
     ;; component when no exact bold-italic variant exists.
     (is (string= "/fonts/Beta.otf" (px.font:match-font "beta sans")))
     (is (string= "/fonts/Beta.otf"
                  (px.font:match-font "beta sans" :bold t :italic t))))))

(test sysfont-system-font-synthesizes-only-missing-style-components
  (let ((path (%sysfont-bundled-path))
        (bold-symbol 'pixelisp.font:set-bold)
        (italic-symbol 'pixelisp.font:set-italic))
    (%with-sysfont-config
     (%sysfont-style-output path "Regular" "Bold")
     (lambda ()
       (multiple-value-bind (matched actual-bold actual-italic)
           (pixelisp.font::%match-system-font "Pixelisp Test Family" :bold t :italic t)
         (is (string= path matched))
         (is-true actual-bold)
         (is (not actual-italic)))
       ;; The matched face is already bold; only the unavailable italic
       ;; component should be synthesized after construction.
       (let* ((real-bold (symbol-function bold-symbol))
              (real-italic (symbol-function italic-symbol))
              (calls nil))
         (unwind-protect
              (progn
                (setf (symbol-function bold-symbol)
                      (lambda (font value)
                        (push :bold calls)
                        (funcall real-bold font value))
                      (symbol-function italic-symbol)
                      (lambda (font value)
                        (push :italic calls)
                        (funcall real-italic font value)))
                (px:with-resource (font (px.font:sys-font "Pixelisp Test Family" 12
                                                          :bold t :italic t))
                  (is (equal '(:italic) calls))))
           (setf (symbol-function bold-symbol) real-bold
                 (symbol-function italic-symbol) real-italic)))))))

(test sysfont-style-configuration-failure-closes-created-font
  (let* ((path (%sysfont-bundled-path))
         (resource-count (length pixelisp.internal:*resources*))
         (symbol 'pixelisp.font:set-bold)
         (original (symbol-function symbol)))
    (%with-sysfont-config
     (%sysfont-style-output path "Regular")
     (lambda ()
       (unwind-protect
            (progn
              (setf (symbol-function symbol)
                    (lambda (&rest arguments)
                      (declare (ignore arguments))
                      (error "Injected style configuration failure.")))
              (signals error (px.font:sys-font "Pixelisp Test Family" 12 :bold t))
              (is (= resource-count (length pixelisp.internal:*resources*))))
         (setf (symbol-function symbol) original))))))

(test freetype-sysfont-synthesizes-missing-styles-and-supports-fallback-names
  (%with-sysfont-config
   (%sysfont-style-output (%sysfont-bundled-path) "Regular")
   (lambda ()
     (px:with-resource (font (px.freetype:sys-font #("missing" "Pixelisp Test Family")
                                                 12 :bold t :italic t :resolution 144))
       (is (= 144 (px.freetype:resolution font)))
       (is (px.freetype:strong font))
       (is (px.freetype:oblique font))
       (is (plusp (length (px.freetype:render-raw font "Styled")))))))
  (%with-sysfont-config
   (%sysfont-style-output (%sysfont-bundled-path) "Bold")
   (lambda ()
     (px:with-resource (font (px.ftfont:sys-font "Pixelisp Test Family" 12 :bold t :italic t))
       (is-false (px.freetype:strong font))
       (is (px.freetype:oblique font))))))

(test sysfont-common-generic-families-alias-installed-fonts-only
  (%with-sysfont-config
   (format nil "/fonts/DejaVuSans.ttf~CDejaVu Sans~CBook~%"
           #\Tab #\Tab)
   (lambda ()
     (is (string= "/fonts/DejaVuSans.ttf" (px.font:match-font "sans-serif")))
     (is (string= "/fonts/DejaVuSans.ttf" (px.font:match-font "Arial")))
     (is (null (px.font:match-font "monospace")))
     (is (equal '("dejavusans") (px.font:get-fonts))))))

(test sysfont-unavailable-fontconfig-does-not-invent-a-match
  (%with-sysfont-config
   nil
   (lambda ()
     (is (null (px.font:get-fonts)))
     (is (null (px.font:match-font "unknown")))
     (is (null (px.font:match-font "sans")))))
  ;; Optional host smoke: a working fontconfig inventory should yield a path
  ;; that corresponds to an actual listed family; minimal hosts may yield NIL.
  (pixelisp.font::%reset-font-inventory)
  (let ((names (px.font:get-fonts)))
    (when names (is (stringp (px.font:match-font (first names))))))
  (pixelisp.font::%reset-font-inventory)
  ;; NIL follows the bundled-font fallback even if fontconfig is unavailable.
  (%with-sysfont-config
   nil
   (lambda ()
     (px:with-resource (font (px.font:sys-font nil 12))
       (px:with-resource (surface (px.font:render font "Fallback" t '(255 255 255)))
         (is (plusp (px.surface:width surface))))))))
