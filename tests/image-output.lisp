(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test encoded-image-roundtrips-preserve-pixels-and-outlive-the-source
  (dolist (kind '(:png :bmp :tga))
    (let ((bytes nil))
      (px.surface:with-surface (source '(3 2) :alpha t)
        (loop for color in '((240 20 40 0) (30 210 50 64) (60 70 220 128)
                            (90 100 110 192) (120 130 140 254) (150 160 170 255))
              for index from 0
              do (px.surface:set-at source (list (mod index 3) (floor index 3)) color))
        (px.surface:set-alpha source 7)
        (px.surface:set-clip source '(1 0 1 1))
        (setf bytes (px.image:save-bytes source :namehint kind))
        (is (typep bytes '(vector (unsigned-byte 8))))
        (is (= 7 (px.surface:get-alpha source))))
      ;; The encoded vector owns its contents after the source is disposed.
      (px:with-resource (decoded (px.image:load-bytes bytes :namehint kind))
        (is (equal '(3 2) (px.surface:size decoded)))
        (loop for expected in '((240 20 40 0) (30 210 50 64) (60 70 220 128)
                               (90 100 110 192) (120 130 140 254) (150 160 170 255))
              for index from 0
              for actual = (px.color:to-list
                            (px.surface:get-at decoded (list (mod index 3) (floor index 3))))
              do (is (equal expected actual)))))))

(test image-memory-encoder-grows-and-supports-jpeg
  (px.surface:with-surface (surface '(128 96))
    ;; BMP is deliberately larger than the adapter's first allocation and seeks
    ;; back to update its header after writing rows.
    (px.surface:fill surface '(130 80 35))
    (let ((bytes (px.image:save-bytes surface :namehint :bmp)))
      (is (> (length bytes) 4096))
      (is (equalp #(66 77) (subseq bytes 0 2)))
      (px:with-resource (image (px.image:load-bytes bytes))
        (is (equal '(130 80 35 255) (px.color:to-list (px.surface:get-at image '(127 95)))))))
    (let ((bytes (px.image:save-bytes surface :namehint "asset.jpeg" :quality 95)))
      (is (equalp #(255 216) (subseq bytes 0 2)))
      (px:with-resource (image (px.image:load-bytes bytes))
        (is (equal '(128 96) (px.surface:size image)))
        (destructuring-bind (r g b a) (px.color:to-list (px.surface:get-at image '(64 48)))
          (is (<= (abs (- r 130)) 3))
          (is (<= (abs (- g 80)) 3))
          (is (<= (abs (- b 35)) 3))
          (is (= a 255)))))))

(test image-save-binary-stream-preserves-position-and-ownership
  (dolist (kind '(nil :png :jpeg :bmp))
    (let ((path (merge-pathnames (format nil "pixelisp-stream-~A.bin" (gensym))
                                 (uiop:temporary-directory))))
      (unwind-protect
           (px.surface:with-surface (surface '(4 3))
             (px.surface:fill surface '(20 80 140))
             (with-open-file (stream path :direction :io :if-exists :supersede
                                         :element-type '(unsigned-byte 8))
               (write-sequence #(1 2 3 4) stream)
               (is (eq stream (px.image:save surface stream :namehint kind)))
               (is (open-stream-p stream))
               (finish-output stream)
               (file-position stream 4)
               (px:with-resource (image (px.image:load stream :namehint (or kind :tga)))
                 (is (equal '(4 3) (px.surface:size image))))))
        (when (probe-file path) (delete-file path))))))

(test image-save-tga-paths-defaults-and-opaque-header
  (px.surface:with-surface (surface '(2 1))
    (px.surface:fill surface '(10 20 30))
    (let ((bytes (px.image:save-bytes surface)))
      (is (= 24 (aref bytes 16)))
      (is (= #x20 (aref bytes 17)))
      (is (equalp #(30 20 10 30 20 10) (subseq bytes 18)))
      (is (equalp bytes (px.image:save-bytes surface :namehint "unknown.extension"))))
    (let ((path (merge-pathnames (format nil "pixelisp-tga-~A.tga" (gensym))
                                 (uiop:temporary-directory))))
      (unwind-protect
           (progn
             (is (equal path (px.image:save surface path)))
             (px:with-resource (image (px.image:load path))
               (is (equal '(10 20 30 255) (px.color:to-list (px.surface:get-at image '(1 0)))))))
        (when (probe-file path) (delete-file path))))))

(test image-output-rejects-invalid-streams-and-quality-before-writing
  (px.surface:with-surface (surface '(1 1))
    (signals type-error (px.image:save surface (make-string-output-stream)))
    (let ((path (merge-pathnames (format nil "pixelisp-invalid-~A.bin" (gensym))
                                 (uiop:temporary-directory))))
      (unwind-protect
           (with-open-file (stream path :direction :io :if-exists :supersede
                                       :element-type '(unsigned-byte 8))
             (write-sequence #(7 8 9) stream)
             (signals type-error (px.image:save surface stream :namehint :jpeg :quality 101))
             (signals type-error (px.image:save surface stream :namehint 42))
             (is (= 3 (file-position stream)))
             (is (open-stream-p stream)))
        (when (probe-file path) (delete-file path))))))

(test encoded-image-output-validates-owner-and-subtype
  (let ((surface (px.surface:make-surface '(1 1) :alpha t)))
    (px:dispose surface)
    (dolist (kind '(:png :bmp :tga))
      (signals px:disposed-resource (px.image:save-bytes surface :namehint kind))))
  (signals type-error (px.image:save-bytes '(not a surface) :namehint :png)))
