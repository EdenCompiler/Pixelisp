(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test float-mixer-copied-arrays-and-live-views
  (px.mixer:init :frequency 22050 :size 32 :channels 1 :buffer 256)
  (let* ((input (make-array 4 :element-type 'single-float
                            :initial-contents '(0.0 0.25 -0.5 1.0)))
         (sound (px.sndarray:make-sound input))
         (view (px.sndarray:samples sound)))
    (unwind-protect
         (progn
           (is (= 32 (second (multiple-value-list (px.mixer:get-init)))))
           (is (eq 'single-float (px.mixer:sound-element-type sound)))
           (is (equalp input (px.sndarray:array sound)))
           (setf (px.buffer:view-ref view 1) -0.75)
           (is (= -0.75 (aref (px.sndarray:array sound) 1)))
           (setf (aref (px.sndarray:array sound) 0) 0.5)
           (is (= 0.0 (px.buffer:view-ref view 0)))
           (is (= 16 (length (px.mixer:get-raw sound))))
           (let ((raw (px.mixer:get-raw sound)))
             (is (equalp (if (member :little-endian *features*)
                             #(0 0 0 0 0 0 64 191)
                             #(0 0 0 0 191 64 0 0))
                         (subseq raw 0 8))))
           (is (typep (px.mixer:play sound) 'px.mixer:channel)))
      (px.buffer:close view) (px:dispose sound) (px.mixer:quit))))

(test float-mixer-stereo-and-format-rejection
  (px.mixer:init :frequency 22050 :size 32 :channels 2 :buffer 256)
  (let ((sound nil))
    (unwind-protect
         (progn
           (signals type-error
             (px.sndarray:make-sound
              (make-array '(2 2) :element-type '(signed-byte 16) :initial-element 0)))
           (signals type-error
             (px.sndarray:make-sound
              (make-array '(2 2) :element-type 'double-float :initial-element 0.0d0)))
           (setf sound
                 (px.sndarray:make-sound
                  (make-array '(2 2) :element-type 'single-float
                              :initial-contents '((1.5 -1.5) (0.5 -1.0)))))
           (is (equal '(2 2) (array-dimensions (px.sndarray:array sound))))
           (is (= 1.5 (px.mixer:sound-sample-ref sound 0 0)))
           (is (= -1.5 (px.mixer:sound-sample-ref sound 0 1)))
           (let ((view (px.sndarray:samples sound)))
             (unwind-protect
                  (progn
                    (signals type-error (setf (px.buffer:view-ref view 0 0) 1))
                    (is (= 1.5 (px.buffer:view-ref view 0 0)))
                    (setf (px.buffer:view-ref view 0 0) 1.25)
                    (is (= 1.25 (px.mixer:sound-sample-ref sound 0 0))))
               (px.buffer:close view))))
      (when sound (px:dispose sound)) (px.mixer:quit))))

(test float-mixer-keeps-raw-octets-distinct-and-decodes-wav
  (px.mixer:init :frequency 22050 :size 32 :channels 1)
  (let ((raw nil) (decoded nil))
    (unwind-protect
         (progn
           (setf raw (px.mixer:make-sound nil :buffer
                                         (make-array 8 :element-type '(unsigned-byte 8) :initial-element 0)))
           (is (= 2 (px.mixer:sound-frame-count raw)))
           (is (= 8 (length (px.mixer:get-raw raw))))
           ;; Existing WAV helper builds signed PCM16 values +0.1426 and -0.0089;
           ;; SDL_mixer converts decoded data to the current float mixer format.
           (setf decoded (px.mixer:load-sound-bytes (%sound-wave-bytes)))
           (is (= 32 (px.mixer:sample-format decoded)))
           (is (= 2 (px.mixer:sound-frame-count decoded)))
           (is (< (abs (- 0.1426 (px.mixer:sound-sample-ref decoded 0))) 0.002))
           (is (< (abs (- -0.00891 (px.mixer:sound-sample-ref decoded 1))) 0.002)))
      (when decoded (px:dispose decoded)) (when raw (px:dispose raw)) (px.mixer:quit))))

(test float-sound-views-and-reinitialization-lifetime
  (px.mixer:init :frequency 22050 :size 32 :channels 1)
  (let* ((sound (px.sndarray:make-sound
                 (make-array 2 :element-type 'single-float :initial-element 0.0)))
         (view (px.sndarray:samples sound)))
    (unwind-protect
         (progn
           (px:dispose sound)
           (signals px:disposed-resource (px.buffer:view-ref view 0))
           (px.mixer:quit)
           (px.mixer:quit)
           (px.mixer:init :frequency 22050 :size 32 :channels 1)
           (is (= 32 (second (multiple-value-list (px.mixer:get-init))))))
      (px.buffer:close view) (px:dispose sound) (px.mixer:quit))))
