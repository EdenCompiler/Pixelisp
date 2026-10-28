;;;; Check physical byte order rather than only decoded colors. These fixtures
;;;; cover F-contiguous surface pixels, C-contiguous audio, packed 24-bit values,
;;;; partial elements and dependent view lifetimes without borrowing pointers.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defun %native-test-octets (values bytes)
  (let ((little (member :little-endian *features*)))
    (coerce (loop for value in values append
              (loop for byte below bytes collect
                (ldb (byte 8 (* 8 (if little byte (- bytes byte 1)))) value)))
            '(vector (unsigned-byte 8)))))

(test buffer-proxy-packed-surface-copy-and-byte-writes
  (px.surface:with-surface (surface '(3 2))
    (px.pixelarray:with-pixel-array (pixels surface)
      (loop for y below 2 do
        (loop for x below 3 do (setf (px.pixelarray:ref pixels x y) (+ 1 x (* y 3))))))
    (px.buffer:with-view (view (px.surface:get-view surface #\2))
      (is (eq surface (px.buffer:parent view)))
      (is (= 24 (px.buffer:byte-length view)))
      (is (px.buffer:contiguous-p view))
      (let ((copy (px.buffer:raw view)))
        (is (typep copy '(vector (unsigned-byte 8))))
        (is (equalp (%native-test-octets '(1 2 3 4 5 6) 4) copy))
        (setf (aref copy 0) 99)
        (is (= 1 (px.surface:get-at-mapped surface '(0 0)))))
      (is (eq view (px.buffer:write view (%native-test-octets '(80) 4) :offset 4)))
      (is (= 80 (px.surface:get-at-mapped surface '(1 0))))
      (is (= 4 (px.surface:get-at-mapped surface '(0 1)))))
    (is-false (px.surface:locked-p surface)))

(test buffer-proxy-c-and-f-order-and-partial-integer-elements
  (dolist (strides '((6 2) (2 4)))
    (let ((array (make-array '(2 3) :element-type '(signed-byte 16)
                                  :initial-contents '((1 -2 3) (4 5 6)))))
      (px.buffer:with-view
          (view (px.buffer:make-view :owner array :dimensions '(2 3) :strides strides
                  :element-type '(signed-byte 16)
                  :reader (lambda (x y) (aref array x y))
                  :writer (lambda (value x y) (setf (aref array x y) value))))
        (let* ((original (px.buffer:raw view))
               (expected (if (equal strides '(6 2)) '(1 -2 3 4 5 6) '(1 4 -2 5 3 6))))
          (is (equalp (%native-test-octets expected 2) original))
          (px.buffer:write-bytes view '(123 45 67) :offset 1)
          (setf (subseq original 1 4) #(123 45 67))
          (is (equalp original (px.buffer:raw view))))))))

(test buffer-proxy-native24-and-row-padding
  (px.surface:with-surface (surface '(4 1) :depth 24)
    (px.buffer:with-view (view (px.surface:get-view surface #\1))
      (is (= 12 (px.buffer:byte-length view)))
      (px.buffer:write view (%native-test-octets '(#x123456 #x789abc #xdef012 #x345678) 3))
      (is (= #x789abc (px.surface:get-at-mapped surface '(1 0))))
      (is (equalp (%native-test-octets '(#x123456 #x789abc #xdef012 #x345678) 3)
                  (px.buffer:raw view)))))
  (px.surface:with-surface (surface '(3 2) :depth 24)
    (px.buffer:with-view (view (px.surface:get-view surface #\2))
      (is (= 18 (px.buffer:byte-length view)))
      (is-false (px.buffer:contiguous-p view))
      (signals px:unsupported-feature (px.buffer:raw view))
      (signals px:unsupported-feature (px.buffer:write view '(1))))
    (px.buffer:with-view (bytes (px.surface:get-buffer surface))
      ;; A raw byte buffer explicitly includes padding as accessible elements.
      (is (= (* 2 (px.surface:get-pitch surface)) (px.buffer:byte-length bytes)))
      (is (px.buffer:contiguous-p bytes)))))

(test buffer-proxy-strided-views-lifetimes-and-read-only-access
  (px.surface:with-surface (surface '(4 1) :depth 8)
    (px.buffer:with-view (view (px.surface:get-buffer surface))
      (px.buffer:write view '(1 2 3 4))
      (px.buffer:with-view (strided (px.buffer:slice view '(0) '(2) '(2)))
        (is (eq view (px.buffer:parent strided)))
        (is (= 2 (px.buffer:byte-length strided)))
        (is-false (px.buffer:contiguous-p strided))
        (signals px:unsupported-feature (px.buffer:raw strided))
        (signals px:resource-in-use (px.buffer:close view)))
      (px.buffer:with-view (backwards (px.buffer:slice view '(3) '(4) '(-1)))
        (is-false (px.buffer:contiguous-p backwards))
        (signals px:unsupported-feature (px.buffer:write backwards '(1))))
      (px.buffer:with-view (source (px.buffer:slice view '(0) '(3)))
        (px.buffer:write view source :offset 1))
      (is (equalp #(1 1 2 3) (px.buffer:raw view))))
    (let ((closed (px.surface:get-buffer surface)))
      (px.buffer:close closed)
      (signals px:disposed-resource (px.buffer:raw closed))
      (signals px:disposed-resource (px.buffer:byte-length closed))
      (signals px:disposed-resource (px.buffer:parent closed))
      (signals px:disposed-resource (px.buffer:write closed '(1)))))
  (px.buffer:with-view (readonly (px.buffer:make-view :owner :test :dimensions '(2) :strides '(1)
                                  :reader (lambda (i) (1+ i))))
    (is (equalp #(1 2) (px.buffer:raw readonly)))
    (signals px:unsupported-feature (px.buffer:write readonly '(3)))))

(test buffer-proxy-validates-entire-patch-before-mutation
  (let ((data (make-array 4 :element-type '(unsigned-byte 8) :initial-element 9)))
    (px.buffer:with-view (view (px.buffer:make-view :owner data :dimensions '(4)
                                :reader (lambda (i) (aref data i))
                                :writer (lambda (value i) (setf (aref data i) value))))
      (signals type-error (px.buffer:write view '(1 2 300)))
      (signals type-error (px.buffer:write view '(1) :offset -1))
      (signals error (px.buffer:write view '(1 2) :offset 3))
      (signals error (px.buffer:write view '(1) :offset 5))
      (is (equalp #(9 9 9 9) data))
      (is (eq view (px.buffer:write view #() :offset 4))))))

(test buffer-proxy-float-audio-byte-encoding-and-partial-writes
  (px.mixer:init :frequency 22050 :size 32 :channels 2)
  (unwind-protect
       (px:with-resource (sound (px.sndarray:make-sound
                                (make-array '(2 2) :element-type 'single-float
                                                    :initial-contents '((0.25 -0.5) (1.0 -0.0)))))
         (px.buffer:with-view (view (px.sndarray:samples sound))
           (is (= 16 (px.buffer:byte-length view)))
           (is (equalp (px.mixer:get-raw sound) (px.buffer:raw view)))
           (px.buffer:write view (%native-test-octets '(#x3f000000) 4) :offset 0)
           (is (= 0.5 (px.mixer:sound-sample-ref sound 0 0)))
           (is (equalp (px.mixer:get-raw sound) (px.buffer:raw view)))
           (px.buffer:write view '(0 0) :offset 7)
           (is (equalp (px.mixer:get-raw sound) (px.buffer:raw view))))))
    (px.mixer:quit)))
