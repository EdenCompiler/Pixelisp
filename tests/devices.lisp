(in-package #:pixelisp.tests)
(in-suite pixelisp)

;; SDL virtual devices exercise the production joystick path without requiring
;; a gamepad or replacing native behavior with a mock implementation.
(cffi:defcfun ("SDL_JoystickAttachVirtual" %attach-virtual) :int
  (type :int) (axes :int) (buttons :int) (hats :int))
(cffi:defcfun ("SDL_JoystickDetachVirtual" %detach-virtual) :int (index :int))
(cffi:defcfun ("SDL_JoystickSetVirtualAxis" %virtual-axis) :int
  (joystick :pointer) (axis :int) (value :int16))
(cffi:defcfun ("SDL_JoystickSetVirtualButton" %virtual-button) :int
  (joystick :pointer) (button :int) (value :uint8))
(cffi:defcfun ("SDL_JoystickSetVirtualHat" %virtual-hat) :int
  (joystick :pointer) (hat :int) (value :uint8))

(test virtual-joystick-native-state-and-lifetime
  (px.joystick:init)
  (let ((index (%attach-virtual 1 6 21 1)) (joystick nil))
    (is (not (minusp index)))
    (unwind-protect
         (progn
           (setf joystick (px.joystick:open-joystick index))
           (is (= 6 (px.joystick:get-numaxes joystick)))
           (is (= 21 (px.joystick:get-numbuttons joystick)))
           (is (= 1 (px.joystick:get-numhats joystick)))
           (is (px.joystick:attached-p joystick))
           (%virtual-axis (pixelisp.internal:handle joystick) 0 -16384)
           (%virtual-button (pixelisp.internal:handle joystick) 2 1)
           (%virtual-hat (pixelisp.internal:handle joystick) 0 3)
           (px.joystick:update)
           (is (= -0.5 (px.joystick:get-axis joystick 0)))
           (is (px.joystick:get-button joystick 2))
           (is (equal '(1 1) (px.joystick:get-hat joystick 0)))
           (signals type-error (px.joystick:get-axis joystick 6))
           (px.joystick:close joystick)
           (signals px:disposed-resource (px.joystick:name joystick))
           (px.joystick:close joystick))
      (when joystick (px:dispose joystick))
      (%detach-virtual index))))

(test worker-results-failures-and-ordered-map
  (is (equal '(7 9) (multiple-value-list (px.threads:join (px.threads:spawn (lambda () (values 7 9)))))))
  (signals simple-error (px.threads:join (px.threads:spawn (lambda () (error "Worker failure")))))
  (is (equal '(1 4 9 16) (px.threads:parallel-map (lambda (x) (* x x)) '(1 2 3 4) :workers 2)))
  (signals simple-error
    (px.threads:parallel-map (lambda (x) (if (= x 2) (error "Bad input") x)) '(1 2 3) :workers 2)))

(test cursor-bitmap-compilation
  (multiple-value-bind (data mask size)
      (px.cursors:compile-cursor '("X.      " " .X     "))
    (is (equal '(8 2) size))
    (is (equalp #(128 32) data))
    (is (equalp #(192 96) mask)))
  (signals px:error (px.cursors:compile-cursor '("????????"))))

(test sdl2-video-ownership-and-texture-upload
  (let* ((window (px.sdl2.video:make-window :size '(32 24) :hidden t))
         (renderer (px.sdl2.video:make-renderer window))
         (surface (px.surface:make-surface '(3 2) :alpha t))
         (texture nil))
    (unwind-protect
         (progn
           (px.surface:fill surface '(210 120 30 200))
           (setf texture (px.sdl2.video:texture-from-surface renderer surface))
           (is (equal '(3 2) (px.sdl2.video:texture-size texture)))
           (setf (px.sdl2.video:texture-alpha texture) 123)
           (is (= 123 (px.sdl2.video:texture-alpha texture)))
           (px.sdl2.video:clear renderer '(12 23 34))
           (px.sdl2.video:draw-texture renderer texture :destination '(2 3 12 8))
           (px.sdl2.video:present renderer)
           (px.sdl2.video:close window)
           (signals px:disposed-resource (px.sdl2.video:texture-size texture)))
      (px:dispose surface) (px:dispose window))))

(test raw-queued-audio-is-copied
  ;; The dummy device is deterministic while paused: queue size cannot change.
  (let ((device (px.sdl2.audio:open-device :frequency 22050 :channels 1 :format :u8)))
    (unwind-protect
         (progn
           (px.sdl2.audio:queue device (make-array 256 :element-type '(unsigned-byte 8) :initial-element 128))
           (is (= 256 (px.sdl2.audio:queued-size device)))
           (px.sdl2.audio:clear-queue device)
           (is (zerop (px.sdl2.audio:queued-size device)))
           (px.sdl2.audio:close device)
           (signals px:disposed-resource (px.sdl2.audio:queued-size device)))
      (px:dispose device))))

(test mixer-postmix-captures-generated-audio
  ;; This exercises the native ring using SDL_mixer's generated output. It
  ;; opens no recording device and does not depend on a microphone.
  (px.mixer:init :frequency 22050 :size -16 :channels 1 :buffer 256)
  (let ((sound (px.sndarray:make-sound
                (make-array 2205 :element-type '(signed-byte 16) :initial-element 12000)))
        (captured #()))
    (unwind-protect
         (progn
           (px.sdl2.mixer:start-capture :capacity 32768)
           (px.mixer:play sound)
           ;; The dummy backend runs its audio callback on another thread.
           (loop repeat 100 while (zerop (length captured)) do
             (px.time:delay 2)
             (setf captured (px.sdl2.mixer:read-capture 32768)))
           (is (plusp (length captured)))
           (is (some #'plusp captured)))
      (px.sdl2.mixer:stop-capture)
      (px:dispose sound)
      (px.mixer:quit))))

(test camera-colorspace-and-closed-state
  (let ((source (px.surface:make-surface '(1 1))) (converted nil)
        (camera (px.camera:make-camera "/dev/pixelisp-nonexistent-camera" :size '(8 8))))
    (unwind-protect
         (progn
           (px.surface:set-at source '(0 0) '(255 0 0))
           (setf converted (px.camera:colorspace source :hsv))
           (is (equal '(0 255 255 255) (px.color:to-list (px.surface:get-at converted '(0 0)))))
           (signals px:initialization-error (px.camera:query-image camera))
           (when (px.camera:available-p)
             (signals px:error (px.camera:start camera)))
           (px:dispose camera)
           (signals px:disposed-resource (px.camera:start camera)))
      (px:dispose source) (when converted (px:dispose converted)) (px:dispose camera))))

(test midi-numeric-helpers-and-event-conversion
  (is (= 440d0 (px.midi:note-to-frequency 69)))
  (is (= 69 (px.midi:frequency-to-note 440)))
  (is (string= "C4" (px.midi:note-to-name 60)))
  (let ((event (first (px.midi:midis-to-events '(((144 60 100 0) 123)) 7))))
    (is (eq :midi-in (px.event:type event)))
    (is (= 123 (px.event:attribute event :timestamp)))
    (is (= 7 (px.event:attribute event :device-id)))))

;; Hardware checks are opt-in. They never wait indefinitely, and the MIDI
;; check opens input only (it never sends a note or SysEx message).
(test opt-in-camera-hardware-smoke
  (cond
    ((not (sb-ext:posix-getenv "PIXELISP_TEST_CAMERA"))
     (skip "Set PIXELISP_TEST_CAMERA=1 to enable the bounded camera hardware check."))
    ((not (px.camera:available-p))
     (skip "The libv4l2 camera adapter is unavailable."))
    (t
     (let ((path (first (px.camera:list-cameras))))
       (if path
           (px.camera:with-camera (camera path :size '(160 120))
             (is (equal 2 (length (px.camera:get-size camera))))
             (px.camera:get-raw camera :timeout 250))
           (skip "No V4L2 capture camera was found."))))))

(test opt-in-midi-input-hardware-smoke
  (cond
    ((not (sb-ext:posix-getenv "PIXELISP_TEST_MIDI"))
     (skip "Set PIXELISP_TEST_MIDI=1 to enable the nonblocking MIDI input check."))
    ((not (px.midi:available-p))
     (skip "PortMidi is unavailable."))
    (t
     (px.midi:init)
     (let ((id (px.midi:get-default-input-id)))
       (if id
           (px.midi:with-input (stream id)
             ;; Poll is non-blocking; reading is bounded to a small batch.
             (when (px.midi:poll stream) (px.midi:read stream 16)))
           (skip "No default MIDI input device was found."))))))

;; Run under Xvfb with PIXELISP_TEST_CLIPBOARD=1 to verify SDL's real X11 clipboard
;; round-trip. Save and restore the clipboard text so the check is contained.
(test opt-in-x11-clipboard-roundtrip
  (cond
    ((not (sb-ext:posix-getenv "PIXELISP_TEST_CLIPBOARD"))
     (skip "Set PIXELISP_TEST_CLIPBOARD=1 under Xvfb to enable the clipboard check."))
    ((not (sb-ext:posix-getenv "DISPLAY"))
     (skip "The clipboard integration check requires an X11 DISPLAY."))
    (t
     (let ((old (handler-case (px.scrap:get-text) (error () nil))))
       (unwind-protect
            (progn
              (px.scrap:set-mode :clipboard)
              (px.scrap:put-text "pixelisp X11 clipboard integration")
              (is (string= "pixelisp X11 clipboard integration" (px.scrap:get-text))))
         (ignore-errors (px.scrap:put-text (or old ""))))))))
