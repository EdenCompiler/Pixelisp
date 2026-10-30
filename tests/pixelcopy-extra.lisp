;;;; Pixelcopy kinds, broadcasting, and atomic array conversion checks.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defmacro with-pixelcopy-surfaces (bindings &body body)
  (if bindings
      `(pixelisp:with-resource ,(first bindings)
         (with-pixelcopy-surfaces ,(rest bindings) ,@body))
      `(progn ,@body)))

(defun copy-test-array (array)
  (let ((copy (make-array (array-dimensions array)
                         :element-type (array-element-type array))))
    (dotimes (index (array-total-size array) copy)
      (setf (row-major-aref copy index) (row-major-aref array index)))))

(test pixelcopy-surface-to-array-kind-alpha-and-colorkey
  (with-pixelcopy-surfaces
      ((plain (px.surface:make-surface '(2 1) :depth 24))
       (alpha (px.surface:make-surface '(2 1) :depth 32 :alpha t)))
    (px.surface:set-alpha plain 70)
    (px.surface:set-at plain '(0 0) '(1 2 3))
    (px.surface:set-at plain '(1 0) '(4 5 6))
    (let ((alpha-array (make-array '(2 1) :element-type '(unsigned-byte 8) :initial-element 0))
          (key-array (make-array '(2 1) :element-type '(unsigned-byte 8) :initial-element 99)))
      ;; Blanket alpha without a pixel alpha mask still reads as 255 from the
      ;; native pixel format; key-only surfaces use OPAQUE below that branch.
      (px.pixelcopy:surface-to-array alpha-array plain :kind #\a :opaque 37)
      (is (equalp #2A((255) (255)) alpha-array))
      (px.surface:set-alpha plain 0)
      (px.pixelcopy:surface-to-array alpha-array plain :kind #\a :opaque 37)
      (is (equalp #2A((255) (255)) alpha-array))
      (px.surface:set-alpha plain 255)
      (px.pixelcopy:surface-to-array alpha-array plain :kind #\a :opaque 37)
      (is (equalp #2A((255) (255)) alpha-array))
      (px.surface:set-alpha plain nil)
      (px.pixelcopy:surface-to-array alpha-array plain :kind #\a :opaque 37)
      (is (equalp #2A((37) (37)) alpha-array))
      ;; pygame.pixelcopy compares complete mapped integers, including alpha.
      (px.surface:set-at alpha '(0 0) '(10 20 30 77))
      (px.surface:set-at alpha '(1 0) '(10 20 30 255))
      (px.surface:set-colorkey alpha '(10 20 30 255))
      (px.pixelcopy:surface-to-array key-array alpha :kind "c" :opaque 31 :clear 4)
      (is (equalp #2A((31) (4)) key-array))
      ;; A copies actual per-pixel alpha bytes, ignoring key matches.
      (px.pixelcopy:surface-to-array alpha-array alpha :kind "A" :opaque 9)
      (is (equalp #2A((77) (255)) alpha-array))
      ;; An explicitly disabled SDL blend mode uses OPAQUE even when the
      ;; format has an alpha mask; enabling it again exposes per-pixel alpha.
      (px.surface:set-alpha alpha nil)
      (px.pixelcopy:surface-to-array alpha-array alpha :kind "A" :opaque 9)
      (is (equalp #2A((9) (9)) alpha-array))
      (px.surface:set-alpha alpha 255)
      ;; No key means C uses OPAQUE for every pixel.
      (px.surface:set-colorkey alpha nil)
      (px.pixelcopy:surface-to-array key-array alpha :kind :colorkey :opaque 23 :clear 3)
      (is (equalp #2A((23) (23)) key-array)))))

(test pixelcopy-surface-to-array-preserves-index-keys-and-validates-before-copy
  (with-pixelcopy-surfaces ((surface (px.surface:make-surface '(2 1) :depth 8)))
    (px.surface:set-palette-at surface 1 '(12 34 56))
    (px.surface:set-palette-at surface 2 '(12 34 56))
    (px.surface:set-at-mapped surface '(0 0) 1)
    (px.surface:set-at-mapped surface '(1 0) 2)
    (px.surface:set-colorkey surface 1)
    (let ((target (make-array '(2 1) :element-type '(unsigned-byte 8) :initial-element 99)))
      (px.pixelcopy:surface-to-array target surface :kind #\C :opaque 250 :clear 7)
      (is (equalp #2A((7) (250)) target))
      ;; Indexed surfaces still expose decoded color channel copies.
      (px.pixelcopy:surface-to-array target surface :kind :red)
      (is (equalp #2A((12) (12)) target))
      (px.pixelcopy:surface-to-array target surface :kind :colorkey)
      (let ((before (copy-test-array target)))
        (signals error (px.pixelcopy:surface-to-array target surface :kind "bad"))
        (signals type-error (px.pixelcopy:surface-to-array target surface :opaque 256))
        (is (equalp before target))))
    (let ((wrong-shape (make-array '(1 2) :initial-element 8)))
      (signals error (px.pixelcopy:surface-to-array wrong-shape surface)))))

(test pixelcopy-array-to-surface-singleton-broadcasts
  (with-pixelcopy-surfaces ((surface (px.surface:make-surface '(3 2) :depth 32 :alpha t)))
    (let ((column (make-array '(1 2) :element-type '(unsigned-byte 32)
                                     :initial-contents '((#x11223344 #x55667788)))))
      (px.pixelcopy:array-to-surface surface column)
      (is (loop for x below 3 always (= #x11223344 (px.surface:get-at-mapped surface (list x 0)))))
      (is (loop for x below 3 always (= #x55667788 (px.surface:get-at-mapped surface (list x 1))))))
    (let ((row (make-array '(3 1 3) :element-type '(unsigned-byte 8)))
          (invalid (make-array '(2 1) :initial-element 9)))
      (dotimes (x 3)
        (setf (aref row x 0 0) (* x 40)
              (aref row x 0 1) 80
              (aref row x 0 2) 120))
      (px.surfarray:blit-array surface row)
      (loop for x below 3 do
        (is (equalp (px.surface:get-at surface (list x 0))
                    (px.surface:get-at surface (list x 1)))))
      (let ((before (px.surfarray:array2d surface)))
        (signals error (px.pixelcopy:array-to-surface surface invalid))
        (is (equalp before (px.surfarray:array2d surface)))))))

(test pixelcopy-map-array-keeps-two-argument-api-and-broadcasts-destination-form
  (with-pixelcopy-surfaces ((format (px.surface:make-surface '(1 1) :depth 32)))
    (let* ((source (make-array '(1 2 3) :element-type '(unsigned-byte 8)
                                       :initial-contents '(((10 20 30) (40 50 60)))))
           (destination (make-array '(3 2) :element-type '(unsigned-byte 32)
                                           :initial-element 0)))
      (let ((legacy (px.pixelcopy:map-array format source)))
        (is (equal '(1 2) (array-dimensions legacy)))
        (is (= (px.surface:map-rgb format '(10 20 30)) (aref legacy 0 0))))
      (px.pixelcopy:map-array destination source format)
      (dotimes (x 3)
        (is (= (px.surface:map-rgb format '(10 20 30)) (aref destination x 0)))
        (is (= (px.surface:map-rgb format '(40 50 60)) (aref destination x 1))))
      (let ((before (copy-test-array destination)))
        (signals error (px.pixelcopy:map-array destination (make-array '(2 2 3) :initial-element 0) format))
        (is (equalp before destination))))))

(test pixelcopy-map-array-snapshots-overlapping-displaced-arrays
  (with-pixelcopy-surfaces ((format (px.surface:make-surface '(1 1) :depth 32)))
    (let* ((storage (make-array 12 :element-type '(unsigned-byte 32)
                                   :initial-contents '(10 20 30 40 50 60 70 80 90 100 110 120)))
           (source (make-array '(1 2 3) :element-type '(unsigned-byte 32)
                                        :displaced-to storage :displaced-index-offset 0))
           (destination (make-array '(3 2) :element-type '(unsigned-byte 32)
                                           :displaced-to storage :displaced-index-offset 0))
           (expected-0 (px.surface:map-rgb format '(10 20 30)))
           (expected-1 (px.surface:map-rgb format '(40 50 60))))
      ;; Source and destination share storage, so all colors must be mapped
      ;; before the first destination element is overwritten.
      (px.pixelcopy:map-array destination source format)
      (dotimes (x 3)
        (is (= expected-0 (aref destination x 0)))
        (is (= expected-1 (aref destination x 1)))))))

(test pixelcopy-conversions-check-surface-kind-before-native-work
  (signals type-error (px.pixelcopy:surface-to-array #2A((0)) :not-a-surface))
  (signals type-error (px.pixelcopy:array-to-surface :not-a-surface #2A((0))))
  (signals type-error (px.pixelcopy:map-array #2A((0)) #3A(((0 0 0))) :not-a-surface))
  (let ((surface (px.surface:make-surface '(1 1) :depth 32)))
    (unwind-protect
         (progn
           (px:dispose surface)
           (signals pixelisp:disposed-resource
             (px.pixelcopy:array-to-surface surface #2A((0)))))
      (when (not (pixelisp.internal:resource-disposed-p surface))
        (px:dispose surface)))))
