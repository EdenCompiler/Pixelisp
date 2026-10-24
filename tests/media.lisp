(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test image-octets-and-row-order
  ;; Distinct colors and alpha values make channel and row swaps observable.
  (let* ((bytes (make-array 16 :element-type '(unsigned-byte 8)
                           :initial-contents '(255 0 0 255 0 255 0 128 0 0 255 64 20 30 40 0)))
         (surface (px.image:from-bytes bytes '(2 2) :rgba)))
    (unwind-protect
         (progn
           (is (equalp bytes (px.image:to-bytes surface :rgba)))
           (is (equalp #(0 0 255 64 20 30 40 0 255 0 0 255 0 255 0 128)
                       (px.image:to-bytes surface :rgba t))))
      (px:dispose surface))))

(test image-native-sharing
  (cffi:with-foreign-object (pixels :uint8 8)
    (dotimes (i 8) (setf (cffi:mem-aref pixels :uint8 i) 255))
    (let ((surface (px.image:from-buffer pixels '(2 1) :rgba :byte-count 8)))
      (unwind-protect
           (progn
             (setf (cffi:mem-aref pixels :uint8 0) 17)
             (is (= 17 (px:color-r (px.surface:get-at surface '(0 0)))))
             (px.surface:set-at surface '(1 0) '(12 23 34 45))
             (is (= 23 (cffi:mem-aref pixels :uint8 5))))
        (px:dispose surface)))))

(test image-png-roundtrip
  (let ((path (merge-pathnames (format nil "pixelisp-image-~A.png" (gensym)) (uiop:temporary-directory)))
        (surface (px.surface:make-surface '(3 2) :alpha t)))
    (unwind-protect
         (progn
           (px.surface:fill surface '(12 34 56 123))
           (px.image:save surface path)
           (let ((loaded (px.image:load path)))
             (unwind-protect
                  (progn (is (equal '(3 2) (px.surface:size loaded)))
                         (is (equal '(12 34 56 123) (px.color:to-list (px.surface:get-at loaded '(1 1))))))
               (px:dispose loaded))))
      (px:dispose surface) (when (probe-file path) (delete-file path)))))

(test font-unicode-and-lifetime
  (let ((font (px.font:make-font nil 20)))
    (unwind-protect
         (progn
           (multiple-value-bind (width height) (px.font:size font "hélλo")
             (is (plusp width)) (is (plusp height)))
           (is (= 5 (length (px.font:metrics font "hélλo"))))
           (px.font:set-bold font t) (is (px.font:get-bold font))
           (let ((rendered (px.font:render font "hélλo" t '(230 200 170))))
             (unwind-protect (is (plusp (px.surface:width rendered))) (px:dispose rendered))))
      (px:dispose font))
    (signals px:disposed-resource (px.font:size font "closed"))
    ;; Repeated disposal must never call TTF_CloseFont twice.
    (px:dispose font)))

(test font-quit-is-idempotent
  (let ((font (px.font:make-font nil 14)))
    (px.font:quit)
    (px.font:quit)
    (is-false (px.font:get-init))
    (signals px:disposed-resource (px.font:size font "closed"))))

(test freetype-direct-rendering-and-kerning
  (let ((font (px.freetype:make-font nil 24)))
    (unwind-protect
         (progn
           (is (numberp (px.freetype:get-kerning font #\A #\V)))
           (is (= 2 (length (px.freetype:get-metrics font "AV"))))
           (multiple-value-bind (bytes dimensions) (px.freetype:render-raw font "AV")
             (is (= (length bytes) (apply #'* dimensions)))
             (is (some #'plusp bytes)))
           (let ((with-kerning (px.freetype:get-rect font "AV")))
             (setf (px.freetype:kerning font) nil)
             (is (<= (px.rect:width with-kerning) (px.rect:width (px.freetype:get-rect font "AV"))))))
      (px:dispose font))
    (signals px:disposed-resource (px.freetype:get-metrics font "x"))))

(test sound-copies-live-views-and-playback
  (px.mixer:init :frequency 22050 :size -16 :channels 2 :buffer 256)
  (let* ((data (make-array '(2205 2) :element-type '(signed-byte 16) :initial-element 0))
         (sound (px.sndarray:make-sound data))
         (view (px.sndarray:samples sound)))
    (unwind-protect
         (progn
           (is (equal '(2205 2) (px.buffer:dimensions view)))
           (setf (px.buffer:view-ref view 0 1) -1234)
           (is (= -1234 (aref (px.sndarray:array sound) 0 1)))
           (is (= 0 (aref data 0 1)))
           (let ((copy (px.sndarray:array sound)))
             (setf (aref copy 0 1) 200)
             (is (= -1234 (px.buffer:view-ref view 0 1))))
           (is (< (abs (- 0.1 (px.mixer:get-length sound))) 0.001))
           (px.mixer:set-volume sound 0.5)
           (is (= 0.5 (px.mixer:get-volume sound)))
           (let ((channel (px.mixer:play sound)))
             (is (typep channel 'px.mixer:channel))
             (is (eq sound (px.mixer:get-sound channel)))
             (px.mixer:stop channel)
             (is (not (px.mixer:get-busy channel)))))
      (px.buffer:close view) (px:dispose sound) (px.mixer:quit))))

(test sound-view-invalidated-by-owner-disposal
  (px.mixer:init :frequency 22050 :size -16 :channels 1)
  (let* ((sound (px.sndarray:make-sound (make-array 16 :element-type '(signed-byte 16) :initial-element 0)))
         (view (px.sndarray:samples sound)))
    (unwind-protect
         (progn (px:dispose sound)
                (signals px:disposed-resource (px.buffer:view-ref view 0)))
      (px.buffer:close view) (px:dispose sound) (px.mixer:quit))))

(test mixer-quit-is-idempotent
  (px.mixer:init :frequency 22050 :size -16 :channels 1)
  (px.mixer:quit)
  ;; Explicit shutdown followed by a global shutdown hook is a normal lifecycle.
  (is (null (px.mixer:get-init)))
  (is (null (px.mixer:quit)))
  (is (null (px.mixer:get-init))))

(test mixer-api-is-safe-before-init-and-after-quit
  (px.mixer:quit)
  (is (= 0 (px.mixer:get-num-channels)))
  (is-false (px.mixer:get-busy))
  (is (null (px.mixer:update)))
  (is (null (px.mixer:stop)))
  (is (null (px.mixer:pause)))
  (is (null (px.mixer:unpause)))
  (is (null (px.mixer:fadeout 10)))
  (is-false (px.mixer.music:get-busy))
  (is (= -1 (px.mixer.music:get-pos)))
  (is (null (px.mixer.music:stop)))
  (is (null (px.mixer.music:pause)))
  (is (null (px.mixer.music:unpause)))
  (is (null (px.mixer.music:rewind)))
  (is (null (px.mixer.music:fadeout 10)))
  (is (null (px.mixer.music:unload)))
  (signals px:initialization-error (px.mixer:set-num-channels 2))
  (px.mixer:init :frequency 22050 :size -16 :channels 1)
  (let ((channel (px.mixer:make-channel 0)))
    (px.mixer:quit)
    (is-false (px.mixer:get-busy channel))
    (is (= 0 (px.mixer:get-volume channel)))
    (is (null (px.mixer:stop channel)))
    (is (null (px.mixer:pause channel)))
    (is (null (px.mixer:unpause channel)))
    (is (null (px.mixer:fadeout 10 channel)))
    (signals px:initialization-error (px.mixer:set-volume channel 0.5))))

(test sound-construction-failure-does-not-register-partial-resource
  (px.mixer:init :frequency 22050 :size -16 :channels 1)
  (let ((before (length pixelisp.internal:*resources*)))
    (signals type-error
      (px.sndarray:make-sound (vector 40000)))
    (is (= before (length pixelisp.internal:*resources*)))
    (signals px:error
      (px.mixer:make-sound nil :array (vector 1) :buffer #(1)))
    (signals px:error (px.mixer:make-sound #P"/definitely/missing/pixelisp.wav"))
    (is (= before (length pixelisp.internal:*resources*))))
  (px.mixer:quit))

(defun %write-test-wave (path samples frequency channels)
  "Write a minimal PCM WAV fixture without adding an external asset dependency."
  (with-open-file (stream path :direction :output :if-exists :supersede :element-type '(unsigned-byte 8))
    (labels ((text (value) (map nil (lambda (character) (write-byte (char-code character) stream)) value))
             (integer-le (value bytes) (dotimes (index bytes) (write-byte (ldb (byte 8 (* index 8)) value) stream))))
      (text "RIFF") (integer-le (+ 36 (length samples)) 4) (text "WAVEfmt ")
      (integer-le 16 4) (integer-le 1 2) (integer-le channels 2)
      (integer-le frequency 4) (integer-le (* frequency channels 2) 4)
      (integer-le (* channels 2) 2) (integer-le 16 2)
      (text "data") (integer-le (length samples) 4) (write-sequence samples stream))))

(test music-load-play-pause-seek-and-unload
  (px.mixer:init :frequency 22050 :size -16 :channels 1)
  (let ((path (merge-pathnames (format nil "pixelisp-audio-~A.wav" (gensym)) (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (%write-test-wave path (make-array 44100 :element-type '(unsigned-byte 8) :initial-element 0) 22050 1)
           (px.mixer.music:load path) (px.mixer.music:play)
           (is (px.mixer.music:get-busy))
           (is (>= (px.mixer.music:get-pos) 0))
           (px.mixer.music:pause) (is (not (px.mixer.music:get-busy)))
           (px.mixer.music:unpause) (is (px.mixer.music:get-busy))
           (px.mixer.music:set-volume 0.5) (is (= 0.5 (px.mixer.music:get-volume)))
           (px.mixer.music:stop) (is (= -1 (px.mixer.music:get-pos)))
           (px.mixer.music:unload))
      (px.mixer.music:unload) (px.mixer:quit)
      (when (probe-file path) (delete-file path)))))
