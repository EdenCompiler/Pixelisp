(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defun %music-wave-bytes (&optional (milliseconds 350))
  "Make a quiet mono PCM WAV long enough to inspect while it streams."
  (let* ((samples (* 2 (floor (* 22050 milliseconds) 1000)))
         (bytes (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0)))
    (labels ((text (value) (map nil (lambda (character) (vector-push-extend (char-code character) bytes)) value))
             (little (value count) (dotimes (index count) (vector-push-extend (ldb (byte 8 (* index 8)) value) bytes))))
      (text "RIFF") (little (+ 36 samples) 4) (text "WAVEfmt ")
      (little 16 4) (little 1 2) (little 1 2) (little 22050 4) (little 44100 4)
      (little 2 2) (little 16 2) (text "data") (little samples 4)
      (dotimes (index samples) (vector-push-extend (if (evenp index) #x34 #x12) bytes)))
    bytes))

(test music-stream-load-bytes-keeps-native-copy
  (let ((bytes (%music-wave-bytes)) (before (length pixelisp.internal:*resources*)))
    (px.mixer:init :frequency 22050 :size -16 :channels 1)
    (unwind-protect
         (progn
           (px.mixer.music:load-bytes bytes :namehint "track.wav")
           (fill bytes 0)
           (px.mixer.music:play)
           (is (px.mixer.music:get-busy))
           (is (= before (length pixelisp.internal:*resources*))))
      (px.mixer.music:unload)
      (px.mixer:quit))))

(test music-stream-load-binary-input-stream-retains-copy-after-close
  (let ((before (length pixelisp.internal:*resources*)))
    (px.mixer:init :frequency 22050 :size -16 :channels 1)
    ;; A file stream supplies octets and can be closed immediately after load.
    (let ((path (merge-pathnames (format nil "pixelisp-music-~A.wav" (gensym)) (uiop:temporary-directory)))
          (bytes (%music-wave-bytes)))
      (unwind-protect
           (progn
             (with-open-file (out path :direction :output :if-exists :supersede :element-type '(unsigned-byte 8))
               (write-sequence #(0 1 2 3) out)
               (write-sequence bytes out))
             (px.mixer:init :frequency 22050 :size -16 :channels 1)
             (with-open-file (input path :direction :input :element-type '(unsigned-byte 8))
               (file-position input 4)
               (px.mixer.music:load input)
               (is (open-stream-p input)))
             (px.mixer.music:play)
             (is (px.mixer.music:get-busy))
             (is (= before (length pixelisp.internal:*resources*))))
        (px.mixer.music:unload) (px.mixer:quit)
        (when (probe-file path) (delete-file path))))))

(test music-stream-queue-transitions-and-repeated-cleanup
  (let ((first (%music-wave-bytes 100)) (second (%music-wave-bytes 600))
        (before (length pixelisp.internal:*resources*)))
    (px.mixer:init :frequency 22050 :size -16 :channels 1)
    (unwind-protect
         (progn
           (px.mixer.music:load first)
           (px.mixer.music:queue second :namehint :wav)
           (let ((old pixelisp.mixer.music::*music*)
                 (queued pixelisp.mixer.music::*queued*))
             (fill second 0)
             (px.mixer.music:play)
             (sleep 0.2)
             (px.mixer.music:update)
             (is (px.mixer.music:get-busy))
             (is (= before (length pixelisp.internal:*resources*)))
             (is (eq queued pixelisp.mixer.music::*music*))
             (is (null (pixelisp.mixer.music::%stream-native old)))
             (is (not (null (pixelisp.mixer.music::%stream-native queued))))
             (px.mixer.music:stop)
             (px.mixer.music:unload)
             (is (null (pixelisp.mixer.music::%stream-native queued)))
             (px.mixer.music:unload)))
      (px.mixer.music:unload)
      (px.mixer:quit)
      (px.mixer:quit))))

(test music-queued-before-play-waits-for-natural-end
  (let ((first (%music-wave-bytes 300)) (second (%music-wave-bytes 500)))
    (px.mixer:init :frequency 22050 :size -16 :channels 1)
    (unwind-protect
         (progn
           (px.mixer.music:load first)
           (let ((current pixelisp.mixer.music::*music*))
             (px.mixer.music:queue second)
             (px.mixer.music:update)
             (is (eq current pixelisp.mixer.music::*music*))
             (is-false (px.mixer.music:get-busy))))
      (px.mixer.music:unload)
      (px.mixer:quit))))

(test music-paused-current-does-not-handoff-and-stop-releases-queue
  (let ((first (%music-wave-bytes 100)) (second (%music-wave-bytes 500)))
    (px.mixer:init :frequency 22050 :size -16 :channels 1)
    (unwind-protect
         (progn
           (px.mixer.music:load first)
           (let ((current pixelisp.mixer.music::*music*))
             (px.mixer.music:queue second)
             (px.mixer.music:play)
             (is (px.mixer.music:get-busy))
             (px.mixer.music:pause)
             (sleep 0.2)
             (px.mixer.music:update)
             (is (eq current pixelisp.mixer.music::*music*))
             (is (not (null pixelisp.mixer.music::*queued*)))
             (px.mixer.music:unpause)
             (sleep 0.2)
             (px.mixer.music:update)
             (is (not (eq current pixelisp.mixer.music::*music*)))
             (is (px.mixer.music:get-busy)))
           (px.mixer.music:queue second)
           (let ((queued pixelisp.mixer.music::*queued*))
             (px.mixer.music:stop)
             (is (null pixelisp.mixer.music::*queued*))
             (is (null (pixelisp.mixer.music::%stream-native queued)))
             (is (null (pixelisp.mixer.music::%stream-rw queued)))
             (is (null (pixelisp.mixer.music::%stream-memory queued)))))
      (px.mixer.music:unload)
      (px.mixer:quit))))

(test music-memory-replacement-and-repeated-shutdown-release-native-storage
  (let ((bytes (%music-wave-bytes 100)))
    (dotimes (cycle 4)
      (declare (ignore cycle))
      (px.mixer:init :frequency 22050 :size -16 :channels 1)
      (unwind-protect
           (progn
             (px.mixer.music:load bytes)
             (px.mixer.music:queue bytes)
             (let ((active pixelisp.mixer.music::*music*)
                   (queued pixelisp.mixer.music::*queued*))
               (px.mixer.music:load bytes)
               (is (null (pixelisp.mixer.music::%stream-native active)))
               (is (null (pixelisp.mixer.music::%stream-rw active)))
               (is (null (pixelisp.mixer.music::%stream-memory active)))
               (is (null (pixelisp.mixer.music::%stream-native queued)))
               (is (null (pixelisp.mixer.music::%stream-rw queued)))
               (is (null (pixelisp.mixer.music::%stream-memory queued))))
             (let ((replacement pixelisp.mixer.music::*music*))
               (px.mixer.music:unload)
               (is (null (pixelisp.mixer.music::%stream-native replacement)))
               (is (null (pixelisp.mixer.music::%stream-rw replacement)))
               (is (null (pixelisp.mixer.music::%stream-memory replacement)))))
        (px.mixer.music:unload)
        (px.mixer:quit)
        (px.mixer:quit)))))

(test music-stream-invalid-input-does-not-disturb-current-or-leak
  (let ((bytes (%music-wave-bytes)))
    (px.mixer:init :frequency 22050 :size -16 :channels 1)
    (unwind-protect
         (progn
           (px.mixer.music:load bytes)
           (px.mixer.music:queue bytes)
           (let ((queued pixelisp.mixer.music::*queued*))
             (let ((before (length pixelisp.internal:*resources*)))
               (signals px:error (px.mixer.music:load "bad" :namehint :unknown))
               (signals px:error
                 (px.mixer.music:load
                  (make-array 4 :element-type '(unsigned-byte 8) :initial-contents '(1 2 3 4))
                  :namehint "wav"))
               (signals type-error (px.mixer.music:queue (make-string-input-stream "no")))
               (signals px:error
                 (px.mixer.music:queue (make-array 0 :element-type '(unsigned-byte 8)) :namehint "wav"))
               (signals type-error (px.mixer.music:load-bytes #(1 2 3)))
               (is (eq queued pixelisp.mixer.music::*queued*))
               (is (= before (length pixelisp.internal:*resources*)))
               (px.mixer.music:play)
               (is (px.mixer.music:get-busy)))))
      (px.mixer.music:unload)
      (px.mixer:quit))))
