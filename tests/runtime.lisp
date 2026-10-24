(in-package #:pixelisp.tests)
(in-suite pixelisp)
(cffi:defcfun ("SDL_strdup" %test-sdl-duplicate) :pointer (text :string))

(test input-state-requires-an-initialized-video-subsystem
  ;; An audio-only runtime leaves *INITIALIZED* true but has no video owner.
  ;; State access must signal a Lisp condition before dereferencing SDL state.
  (let ((pixelisp.internal:*initialized* t)
        (pixelisp.internal:*video-thread* nil))
    (signals px:initialization-error (px.key:get-pressed))
    (signals px:initialization-error (px.mouse:get-pos))
    (signals px:initialization-error (px.mouse:get-pressed))))

(test joystick-and-controller-event-payloads-are-copied
  (sdl2:with-sdl-event (native :controllerbuttondown)
    (setf (native :cbutton :which) 12
          (native :cbutton :button) 3
          (native :cbutton :state) 1)
    (let ((event (px.event::%decode-native native)))
      (is (= 12 (px.event:attribute event :which)))
      (is (= 3 (px.event:attribute event :button)))
      (is (= 1 (px.event:attribute event :state)))))
  (sdl2:with-sdl-event (native :joyhatmotion)
    (setf (native :jhat :which) 17
          (native :jhat :hat) 2
          (native :jhat :value) 3)
    (let ((event (px.event::%decode-native native)))
      (is (eq :joy-hat-motion (px.event:type event)))
      (is (= 17 (px.event:attribute event :which)))
      (is (= 2 (px.event:attribute event :hat)))
      (is (= 3 (px.event:attribute event :value)))))
  (sdl2:with-sdl-event (native :joyballmotion)
    (setf (native :jball :which) 23
          (native :jball :ball) 1
          (native :jball :xrel) -4
          (native :jball :yrel) 6)
    (let ((event (px.event::%decode-native native)))
      (is (eq :joy-ball-motion (px.event:type event)))
      (is (= 23 (px.event:attribute event :which)))
      (is (= 1 (px.event:attribute event :ball)))
      (is (equal '(-4 6) (px.event:attribute event :rel)))))
  (sdl2:with-sdl-event (native :controllertouchpadmotion)
    (setf (native :ctouchpad :which) 31
          (native :ctouchpad :touchpad) 2
          (native :ctouchpad :finger) 0
          (native :ctouchpad :x) 0.25
          (native :ctouchpad :y) 0.75
          (native :ctouchpad :pressure) 0.5)
    (let ((event (px.event::%decode-native native)))
      (is (= 31 (px.event:attribute event :which)))
      (is (= 2 (px.event:attribute event :touchpad)))
      (is (= 0 (px.event:attribute event :finger)))
      (is (= 0.25 (px.event:attribute event :x)))
      (is (= 0.75 (px.event:attribute event :y)))
      (is (= 0.5 (px.event:attribute event :pressure)))))
  (sdl2:with-sdl-event (native :controllersensorupdate)
    (setf (native :csensor :which) 7
          (native :csensor :sensor) 2
          (native :csensor :data 0) 0.125
          (native :csensor :data 1) -0.25
          (native :csensor :data 2) 1.5)
    (let ((event (px.event::%decode-native native)))
      (is (= 7 (px.event:attribute event :which)))
      (is (= 2 (px.event:attribute event :sensor)))
      (is (equal '(0.125 -0.25 1.5) (px.event:attribute event :data)))))
  (sdl2:with-sdl-event (native :multigesture)
    (setf (native :mgesture :touch-id) 54
          (native :mgesture :d-theta) 0.5
          (native :mgesture :d-dist) 0.25
          (native :mgesture :x) 0.75
          (native :mgesture :y) 0.125
          (native :mgesture :num-fingers) 2)
    (let ((event (px.event::%decode-native native)))
      (is (= 54 (px.event:attribute event :touch-id)))
      (is (= 0.5 (px.event:attribute event :dtheta)))
      (is (= 2 (px.event:attribute event :fingers))))))

(test axis-event-normalization-matches-polled-axis
  ;; SDL's signed 16-bit axis has one extra negative value. Both ends should
  ;; normalize exactly to the same inclusive range used by device polling.
  (dolist (type '(:joyaxismotion :controlleraxismotion))
    (dolist (sample '((32767 1.0) (-32768 -1.0)))
      (sdl2:with-sdl-event (native type)
        (if (eq type :joyaxismotion)
            (setf (native :jaxis :value) (first sample))
            (setf (native :caxis :value) (first sample)))
        (let* ((event (px.event::%decode-native native))
               (value (px.event:attribute event :value)))
          (is (= (second sample) value)))))))

(test drop-event-copies-and-releases-sdl-owned-path
  (sdl2:with-sdl-event (native :dropfile)
    (setf (native :drop :file) (%test-sdl-duplicate "/tmp/dragged file.png")
          (native :drop :window-id) 42)
    (let ((event (px.event::%decode-native native)))
      (is (eq :dropfile (px.event:type event)))
      (is (string= "/tmp/dragged file.png" (px.event:attribute event :file)))
      (is (= 42 (px.event:attribute event :window-id)))))
  (sdl2:with-sdl-event (native :droptext)
    (setf (native :drop :file) (%test-sdl-duplicate "plain text payload"))
    (let ((event (px.event::%decode-native native)))
      (is (string= "plain text payload" (px.event:attribute event :text)))
      (is (null (px.event:attribute event :file))))))
