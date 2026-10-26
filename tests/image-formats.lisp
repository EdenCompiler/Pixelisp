;;;; Optional decoded-format preservation for image loads.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test indexed-bmp-load-can-preserve-native-format-and-palette
  (let ((bytes nil))
    (px.surface:with-surface (source '(3 1) :depth 8)
      (px.surface:set-palette-at source 3 '(230 20 40))
      (px.surface:set-palette-at source 9 '(15 190 70))
      (px.buffer:with-view (pixels (px.surface:get-view source #\2))
        (setf (px.buffer:view-ref pixels 0 0) 3
              (px.buffer:view-ref pixels 1 0) 9
              (px.buffer:view-ref pixels 2 0) 3))
      (setf bytes (px.image:save-bytes source :namehint :bmp)))
    ;; Default loading retains the existing normalized 32-bit behavior.
    (px:with-resource (normalized (px.image:load-bytes bytes :namehint :bmp))
      (is (= 32 (px.surface:get-bitsize normalized))))
    ;; The optional path retains both indexed storage and the decoded palette.
    (px:with-resource (preserved (px.image:load-bytes bytes :namehint :bmp
                                                       :preserve-format t))
      (is (= 8 (px.surface:get-bitsize preserved)))
      (is (equal '(230 20 40 255)
                 (px.color:to-list (px.surface:get-palette-at preserved 3))))
      (is (equal '(15 190 70 255)
                 (px.color:to-list (px.surface:get-palette-at preserved 9))))
      (px.buffer:with-view (pixels (px.surface:get-view preserved #\2))
        (is (equal '(3 9 3)
                   (loop for x below 3 collect (px.buffer:view-ref pixels x 0))))))))

(test image-preserve-format-option-is-validated-before-decoding
  (px.surface:with-surface (source '(1 1))
    (let ((bytes (px.image:save-bytes source :namehint :bmp))
          (before (length pixelisp.internal:*resources*)))
      (signals type-error (px.image:load-bytes bytes :preserve-format :yes))
      (is (= before (length pixelisp.internal:*resources*))))))

(test image-load-preserve-format-applies-to-path-vector-and-stream
  (let* ((path (merge-pathnames (format nil "pixelisp-indexed-~A.bmp" (gensym))
                                (uiop:temporary-directory)))
         (source (px.surface:make-surface '(2 1) :depth 8)))
    (unwind-protect
         (progn
           (px.surface:set-palette-at source 5 '(100 80 60))
           (px.buffer:with-view (pixels (px.surface:get-view source #\2))
             (setf (px.buffer:view-ref pixels 0 0) 5
                   (px.buffer:view-ref pixels 1 0) 5))
           (px.image:save source path :namehint :bmp)
           (let ((bytes (with-open-file (stream path :direction :input
                                                      :element-type '(unsigned-byte 8))
                          (let ((result (make-array (file-length stream)
                                                    :element-type '(unsigned-byte 8))))
                            (read-sequence result stream)
                            result))))
             (px:with-resource (from-vector (px.image:load bytes :preserve-format t))
               (is (= 8 (px.surface:get-bitsize from-vector))))
             (with-open-file (stream path :direction :input :element-type '(unsigned-byte 8))
               (let ((position (file-position stream)))
                 (signals type-error (px.image:load stream :preserve-format :yes))
                 (is (= position (file-position stream))))
               (px:with-resource (from-stream (px.image:load stream :preserve-format t))
                 (is (open-stream-p stream))
                 (is (= 8 (px.surface:get-bitsize from-stream))))))
           (px:with-resource (from-path (px.image:load path :preserve-format t))
             (is (= 8 (px.surface:get-bitsize from-path))))
           (signals type-error (px.image:load path :preserve-format :yes)))
      (px:dispose source)
      (when (probe-file path) (delete-file path)))))
