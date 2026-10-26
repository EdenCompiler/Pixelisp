;;;; Transforms copy packed pixels while keeping their source Surface format.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defun %set-transform-pixels (surface values)
  (px.surface:lock surface)
  (unwind-protect
       (loop for value in values for index from 0
             do (px.surface::%write-packed-pixel surface (mod index (px.surface:width surface))
                                                     (floor index (px.surface:width surface)) value))
    (px.surface:unlock surface)))

(defun %transform-pixels (surface)
  (px.surface:lock surface)
  (unwind-protect
       (loop for y below (px.surface:height surface)
             append (loop for x below (px.surface:width surface)
                          collect (px.surface::%read-packed-pixel surface x y)))
    (px.surface:unlock surface)))

(test nearest-transforms-preserve-packed-formats
  (dolist (depth '(8 16 24 32))
    (px:with-resource (source (px.surface:make-surface '(2 2) :depth depth))
      ;; Direct packed writes let this exercise indexed values independently of
      ;; their displayed colors, including distinct palette indices.
      (%set-transform-pixels source '(1 2 3 4))
      (let* ((original (%transform-pixels source))
             (flipped (px.transform:flip source t nil))
             (scaled (px.transform:scale source '(4 2)))
             (doubled (px.transform:scale2x source))
             (chopped (px.transform:chop source '(0 0 1 1)))
             (results (list flipped scaled doubled chopped)))
        (unwind-protect
             (progn
               (dolist (result results)
                 (is (= depth (px.surface:get-bitsize result)))
                 (is (equal (px.surface:get-masks source) (px.surface:get-masks result)))
                 (is (null (px.surface:get-parent result))))
               (is (equal '(2 1 4 3) (%transform-pixels flipped)))
               (is (equal '(1 1 2 2 3 3 4 4) (%transform-pixels scaled)))
               (is (equal '(1 1 2 2 1 1 2 2 3 3 4 4 3 3 4 4)
                          (%transform-pixels doubled)))
               (is (equal '(4) (%transform-pixels chopped)))
               (is (equal original '(1 2 3 4))))
          (mapc #'px:dispose results))))))

(test nearest-transform-writes-ignore-destination-clip
  (px:with-resource (source (px.surface:make-surface '(2 1) :depth 24))
    (px:with-resource (destination (px.surface:make-surface '(2 1) :depth 24))
      (%set-transform-pixels source '(#x010203 #x040506))
      (px.surface:set-clip destination '(0 0 1 1))
      (px.transform:scale source '(2 1) destination)
      (is (equal '(#x010203 #x040506) (%transform-pixels destination))))))

(test filtered-transforms-reject-low-depth-surfaces
  (dolist (depth '(8 16))
    (px:with-resource (source (px.surface:make-surface '(2 2) :depth depth))
      (signals error (px.transform:smoothscale source '(3 3))))))

(test rotozoom-converts-low-depth-stored-colors-to-32-bit
  (dolist (depth '(8 16 24))
    (px:with-resource (source (px.surface:make-surface '(2 1) :depth depth))
      (when (= depth 8)
        (px.surface:set-palette-at source 1 '(80 120 160))
        (px.surface:set-palette-at source 2 '(100 140 180))
        (%set-transform-pixels source '(1 2)))
      (unless (= depth 8)
        (px.surface:set-at source '(0 0) '(80 120 160))
        (px.surface:set-at source '(1 0) '(100 140 180)))
      (px.surface:set-alpha source 91)
      (px.surface:set-colorkey source (px.surface:get-at source '(0 0)))
      (let ((expected (px.color:to-list (px.surface:get-at source '(1 0))))
            (result (px.transform:rotozoom source 0 1.0)))
        (unwind-protect
             (progn
               (is (= 32 (px.surface:get-bitsize result)))
               (is (px.surface:alpha-p result))
               ;; The key pixel becomes transparent. Blanket alpha remains a
               ;; Surface attribute and does not darken converted pixel data.
               (is (zerop (px:color-a (px.surface:get-at result '(0 0)))))
               (is (equal expected (px.color:to-list (px.surface:get-at result '(1 0))))))
          (px:dispose result))))))

(test rotozoom-releases-temporary-conversion-on-error
  (px:with-resource (source (px.surface:make-surface '(1 1) :depth 8))
    (let ((before (length pixelisp.internal:*resources*)))
      (signals error (px.transform:rotozoom source 'not-an-angle 1.0))
      (is (= before (length pixelisp.internal:*resources*))))))

(test indexed-palette-and-blanket-attributes-survive-transform
  (px:with-resource (source (px.surface:make-surface '(2 1) :depth 8))
    (px.surface:set-palette-at source 1 '(20 30 40))
    (px.surface:set-palette-at source 2 '(20 30 40))
    (%set-transform-pixels source '(1 2))
    (px.surface:set-alpha source 117)
    ;; Index 2 duplicates index 1 in RGB, so retaining the packed key matters.
    (px.surface:set-colorkey source 2)
    (let ((result (px.transform:scale source '(4 1))))
      (unwind-protect
           (progn
             (is (equal '(1 1 2 2) (%transform-pixels result)))
             (is (= 117 (px.surface:get-alpha result)))
             (is (equal (px.color:to-list (px.surface:get-colorkey source))
                        (px.color:to-list (px.surface:get-colorkey result))))
             (is (= 2 (px.surface::%native-colorkey result)))
             (is (equal (px.color:to-list (px.surface:get-palette-at source 1))
                        (px.color:to-list (px.surface:get-palette-at result 2)))))
        (px:dispose result)))))

(test transform-destination-must-match-format
  (px:with-resource (source (px.surface:make-surface '(1 1) :depth 16))
    (px:with-resource (wrong (px.surface:make-surface '(2 2) :depth 32))
      (signals error (px.transform:scale source '(2 2) wrong))
      (signals error (px.transform:scale2x source wrong)))))
