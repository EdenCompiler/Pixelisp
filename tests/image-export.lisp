(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test image-export-premultiplies-with-pygame-floor-rounding
  (px.surface:with-surface (surface '(3 1) :alpha t)
    (px.surface:set-at surface '(0 0) '(200 51 129 128))
    (px.surface:set-at surface '(1 0) '(200 51 129 254))
    (px.surface:set-at surface '(2 0) '(200 51 129 0))
    (is (equalp #(100 25 64 128 199 50 128 254 0 0 0 0)
                (px.image:to-bytes surface :rgba_premult)))
    (is (equalp #(128 100 25 64 254 199 50 128 0 0 0 0)
                (px.image:to-string surface "argb-premult")))
    ;; Export is a read-only snapshot and ignores blanket alpha, color key and clip.
    (px.surface:set-alpha surface 17)
    (px.surface:set-colorkey surface '(200 51 129))
    (px.surface:set-clip surface '(1 0 1 1))
    (is (equalp #(100 25 64 128 199 50 128 254 0 0 0 0)
                (px.image:to-bytes surface :rgba-premult)))
    (is (= 17 (px.surface:get-alpha surface)))
    (let ((clip (px.surface:get-clip surface)))
      (is (equal '(1 0 1 1)
                 (list (px.rect:x clip) (px.rect:y clip)
                       (px.rect:width clip) (px.rect:height clip)))))
    (is (equal '(200 51 129 128) (px.color:to-list (px.surface:get-at surface '(0 0)))))))

(test image-export-premultiplied-flipped-rows-and-cropped-surfaces
  (px.surface:with-surface (parent '(3 3) :alpha t)
    (dotimes (y 3)
      (dotimes (x 3)
        (px.surface:set-at parent (list x y) (list (+ 10 (* 20 y) x) 40 60 128))))
    (px:with-resource (crop (px.surface:subsurface parent '(1 0 2 2)))
      (is (equalp #(5 20 30 128 6 20 30 128
                    15 20 30 128 16 20 30 128)
                  (px.image:to-bytes crop :rgba-premult)))
      (is (equalp #(15 20 30 128 16 20 30 128
                    5 20 30 128 6 20 30 128)
                  (px.image:to-bytes crop :rgba-premult t))))))

(test image-export-premultiplied-requires-real-alpha-mask
  (px.surface:with-surface (opaque '(1 1))
    (signals px:unsupported-feature (px.image:to-bytes opaque :rgba-premult)))
  ;; Imported RGBX surfaces carry an alpha compatibility flag in the wrapper,
  ;; but have no alpha mask in the native SDL pixel format.
  (cffi:with-foreign-object (pixels :uint8 4)
    (dotimes (i 4) (setf (cffi:mem-aref pixels :uint8 i) 255))
    (px:with-resource (surface (px.image:from-buffer pixels '(1 1) :rgbx :byte-count 4))
      (is (zerop (fourth (px.surface:get-masks surface))))
      (signals px:unsupported-feature (px.image:to-string surface :argb-premult)))))

(test image-import-still-rejects-premultiplied-format-names
  (let ((bytes (make-array 4 :element-type '(unsigned-byte 8) :initial-element 0)))
    (signals px:unsupported-feature (px.image:from-bytes bytes '(1 1) :rgba-premult))
    (signals px:unsupported-feature (px.image:from-string bytes '(1 1) "ARGB_PREMULT"))))

(test image-export-rejects-disposed-surface
  (let ((surface (px.surface:make-surface '(1 1) :alpha t)))
    (px:dispose surface)
    (signals px:disposed-resource (px.image:to-bytes surface :rgba-premult))))
