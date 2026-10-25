(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defun %sound-wave-bytes ()
  "Build a two-sample, mono PCM WAV without relying on a checked-in fixture."
  (let ((bytes (make-array 0 :element-type '(unsigned-byte 8)
                           :adjustable t :fill-pointer 0)))
    (labels ((ascii (text) (map nil (lambda (character) (vector-push-extend (char-code character) bytes)) text))
             (u16 (value) (dotimes (shift 2) (vector-push-extend (ldb (byte 8 (* shift 8)) value) bytes)))
             (u32 (value) (dotimes (shift 4) (vector-push-extend (ldb (byte 8 (* shift 8)) value) bytes))))
      (ascii "RIFF") (u32 40) (ascii "WAVE")
      (ascii "fmt ") (u32 16) (u16 1) (u16 1) (u32 22050)
      (u32 44100) (u16 2) (u16 16)
      (ascii "data") (u32 4) (u16 #x1234) (u16 #xfedc))
    bytes))

(test sound-loads-encoded-octets-and-copies-decoded-data
  (let ((bytes (%sound-wave-bytes)) (sound nil))
    (px.mixer:init :frequency 22050 :size -16 :channels 1)
    (unwind-protect
         (progn
           (setf sound (px.mixer:make-sound nil :file bytes))
           (is (= #x1234 (px.mixer:sound-sample-ref sound 0)))
           (is (= -292 (px.mixer:sound-sample-ref sound 1)))
           ;; Decoder output remains valid even after the caller's vector changes.
           (fill bytes 0)
           (is (= 2 (px.mixer:sound-frame-count sound)))
           (is (= 4 (length (px.mixer:get-raw sound))))
           (is (= 22050 (first (multiple-value-list (px.mixer:get-init))))))
      (when sound (px:dispose sound))
      (px.mixer:quit))))

(test sound-loads-encoded-binary-stream-without-closing-it
  (let* ((path (merge-pathnames (format nil "pixelisp-sound-~A.wav" (gensym))
                                (uiop:temporary-directory)))
         (bytes (%sound-wave-bytes)) (sound nil))
    (with-open-file (output path :direction :output :element-type '(unsigned-byte 8)
                                  :if-exists :supersede)
      ;; The stream test seeks past this prefix before handing the stream over.
      (write-sequence #(0 0 0 0) output)
      (write-sequence bytes output))
    (px.mixer:init :frequency 22050 :size -16 :channels 1)
    (unwind-protect
         (with-open-file (stream path :direction :input :element-type '(unsigned-byte 8))
           (file-position stream 4)
           (setf sound (px.mixer:make-sound nil :file stream))
           (is (open-stream-p stream))
           (is (= 2 (px.mixer:sound-frame-count sound)))
           (is (= #x1234 (px.mixer:sound-sample-ref sound 0))))
      (when sound (px:dispose sound))
      (px.mixer:quit)
      (when (probe-file path) (delete-file path)))))

(test sound-file-keyword-accepts-path-and-raw-buffer-stays-distinct
  (let* ((path (merge-pathnames (format nil "pixelisp-sound-~A.wav" (gensym))
                                (uiop:temporary-directory)))
         (bytes (%sound-wave-bytes)) (decoded nil) (raw nil)
         (raw-buffer (make-array 4 :element-type '(unsigned-byte 8)
                                 :initial-contents '(1 0 2 0))))
    (with-open-file (output path :direction :output :element-type '(unsigned-byte 8)
                                  :if-exists :supersede)
      (write-sequence bytes output))
    (px.mixer:init :frequency 22050 :size -16 :channels 1)
    (unwind-protect
         (progn
           (setf decoded (px.mixer:make-sound nil :file path)
                 raw (px.mixer:make-sound nil :buffer raw-buffer))
           (is (= 2 (px.mixer:sound-frame-count decoded)))
           (is (= 2 (px.mixer:sound-frame-count raw)))
           (is (equalp raw-buffer (px.mixer:get-raw raw))))
      (when decoded (px:dispose decoded))
      (when raw (px:dispose raw))
      (px.mixer:quit)
      (when (probe-file path) (delete-file path)))))

(test sound-invalid-encoded-data-releases-resources
  (px.mixer:init :frequency 22050 :size -16 :channels 1)
  (let ((resource-count (length pixelisp.internal:*resources*)))
    (unwind-protect
         (progn
           (signals px:error
             (px.mixer:load-sound-bytes (make-array 0 :element-type '(unsigned-byte 8))))
           (signals px:error
             (px.mixer:load-sound-bytes
              (make-array 4 :element-type '(unsigned-byte 8) :initial-contents '(1 2 3 4))))
           (is (= resource-count (length pixelisp.internal:*resources*))))
      (px.mixer:quit))))

(test sound-disposed-memory-no-longer-accessible
  (px.mixer:init :frequency 22050 :size -16 :channels 1)
  (let ((sound (px.mixer:load-sound-bytes (%sound-wave-bytes))))
    (unwind-protect
         (progn
           (px:dispose sound)
           (signals px:disposed-resource (px.mixer:get-raw sound)))
      (px.mixer:quit))))

(test sound-source-conflicts-do-not-consume-stream
  (let ((stream (make-string-input-stream "still here")))
    (signals px:error
      (px.mixer:make-sound nil :file stream
                           :buffer (make-array 2 :element-type '(unsigned-byte 8)
                                              :initial-contents '(0 0))))
    (is (= 0 (file-position stream)))))

(test sound-rejects-output-stream-before-decoding
  (let ((path (merge-pathnames (format nil "pixelisp-output-~A.wav" (gensym))
                               (uiop:temporary-directory))))
    (unwind-protect
         (with-open-file (stream path :direction :output :element-type '(unsigned-byte 8))
           (signals type-error (px.mixer:make-sound nil :file stream))
           (is (open-stream-p stream)))
      (when (probe-file path) (delete-file path)))))

(test sound-rejects-invalid-encoded-source-before-opening-mixer
  (let ((initialized (px.mixer:get-init)))
    (unless initialized
      (signals type-error (px.mixer:make-sound nil :file (make-string-input-stream "not bytes")))
      (is-false (px.mixer:get-init)))))
