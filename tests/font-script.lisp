(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defun %font-script-harfbuzz-unavailable-p (condition)
  "Recognize only explicit native errors saying HarfBuzz support is absent."
  (let ((message (string-downcase (px:message condition))))
    (and (search "harfbuzz" message)
         (some (lambda (phrase) (search phrase message))
               '("not built" "wasn't built" "without" "not available" "unavailable"
                 "lack" "not supported" "disabled")))))

(test font-script-is-per-font-and-validates-tags
  (let ((font (px.font:make-font nil 24)))
    (unwind-protect
         (progn
           ;; Validation is independent of SDL_ttf/HarfBuzz availability and
           ;; happens before the native font can be changed.
           (dolist (invalid '("Lat" "Latin" "L4tn" "Lātn" "Latn "))
             (signals px:error (px.font:set-script font invalid)))
           (let ((function (px.font::%font-script-function))
                 (unusable-backend nil))
             (if (null function)
                 (signals px:unsupported-feature (px.font:set-script font "Latn"))
                 (handler-case
                     (progn
                       (is (string= "Latn" (px.font:set-script font "Latn")))
                       (is (string= "Arab" (px.font:set-script font "Arab"))))
                   ;; SDL_ttf exports this API even in builds without HarfBuzz;
                   ;; in that case its documented native -1 becomes px:error.
                   (px:error (condition)
                     (if (%font-script-harfbuzz-unavailable-p condition)
                         (setf unusable-backend t)
                         (error condition)))))
           ;; Script selection leaves UTF-8 rendering and standard metrics
           ;; usable, regardless of whether shaping support is installed.
           (multiple-value-bind (width height) (px.font:size font "hélλo")
             (is (plusp width))
             (is (plusp height)))
           (let ((rendered (px.font:render font "hélλo" t '(230 200 170))))
             (unwind-protect
                  (progn
                    (is (plusp (px.surface:width rendered)))
                    (is (plusp (px.surface:height rendered))))
               (px:dispose rendered)))
             ;; Render and check its dimensions before marking this test skipped
             ;; when the function exists but the library lacks HarfBuzz.
             (when unusable-backend
               (skip "SDL_ttf lacks usable HarfBuzz shaping support."))))
      (px:dispose font))))

(test font-script-validates-before-native-call-and-checks-font-liveness
  (let ((font (px.font:make-font nil 16)))
    (signals type-error (px.font:set-script font nil))
    (px:dispose font)
    (signals px:disposed-resource (px.font:set-script font "Latn"))
    ;; Malformed tags are rejected before a native mutation, even for closed fonts.
    (signals px:error (px.font:set-script font "La1n"))))

(test font-script-reports-a-missing-native-symbol
  (let* ((font (px.font:make-font nil 16))
         (original (symbol-function 'px.font::%font-script-function)))
    (unwind-protect
         (progn
           ;; Exercise the old-SDL_ttf path deterministically on any host.
           (setf (symbol-function 'px.font::%font-script-function)
                 (lambda () nil))
           (signals px:unsupported-feature (px.font:set-script font "Latn")))
      (setf (symbol-function 'px.font::%font-script-function) original)
      (px:dispose font))))
