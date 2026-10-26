(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defun %mouse-test-set-wheel-precise (native x y)
  "Fill SDL 2.0.18 wheel fields through the public event structure layout."
  (let ((event-pointer (pixelisp.internal:%ptr native)))
    (setf (cffi:foreign-slot-value event-pointer
                                   '(:struct pixelisp.event::%sdl-mouse-wheel-event)
                                   'pixelisp.event::precise-x) x
          (cffi:foreign-slot-value event-pointer
                                   '(:struct pixelisp.event::%sdl-mouse-wheel-event)
                                   'pixelisp.event::precise-y) y)))

(test native-mouse-motion-and-button-metadata
  (sdl2:with-sdl-event (native :mousemotion)
    (setf (native :motion :which) #xffffffff
          (native :motion :window-id) 41
          (native :motion :x) 12 (native :motion :y) 13
          (native :motion :xrel) 2 (native :motion :yrel) -1
          (native :motion :state) 5)
    (let ((event (px.event::%decode-native native)))
      (is (eq :mouse-motion (px.event:type event)))
      (is (equal '(12 13) (px.event:attribute event :pos)))
      (is (= 5 (px.event:attribute event :buttons)))
      (is (= #xffffffff (px.event:attribute event :which)))
      (is (px.event:attribute event :touch))
      (is (= 41 (px.event:attribute event :window-id)))))
  (sdl2:with-sdl-event (native :mousebuttondown)
    (setf (native :button :which) 7
          (native :button :window-id) 52
          (native :button :button) 1
          (native :button :x) 24 (native :button :y) 25)
    (let ((event (px.event::%decode-native native)))
      (is (eq :mouse-button-down (px.event:type event)))
      (is (= 1 (px.event:attribute event :button)))
      (is (= 7 (px.event:attribute event :which)))
      (is (null (px.event:attribute event :touch)))
      (is (= 52 (px.event:attribute event :window-id))))))

(test native-mouse-wheel-direction-precision-and-old-sdl-fallback
  (sdl2:with-sdl-event (native :mousewheel)
    (setf (native :wheel :which) 9
          (native :wheel :window-id) 63
          (native :wheel :x) -2 (native :wheel :y) 3
          (native :wheel :direction) 1)
    (%mouse-test-set-wheel-precise native -1.25 2.5)
    (let ((event (px.event::%decode-native native)))
      (is (eq :mouse-wheel (px.event:type event)))
      (is (= -2 (px.event:attribute event :x)))
      (is (= 3 (px.event:attribute event :y)))
      (is (= 9 (px.event:attribute event :which)))
      (is (null (px.event:attribute event :touch)))
      (is (= 63 (px.event:attribute event :window-id)))
      (is (px.event:attribute event :flipped))
      (when (px.event::%sdl-version-at-least-p 2 0 18)
        (is (= -1.25 (px.event:attribute event :precise-x)))
        (is (= 2.5 (px.event:attribute event :precise-y)))))
    (let ((fallback (px.event::%native-wheel-precise native nil)))
      (is (= -2 (first fallback)))
      (is (= 3 (second fallback))))))

(test native-wheel-queue-copies-touch-and-normal-wheel-metadata
  (px:with-init ()
    (unwind-protect
         (progn
           (px.event:clear nil :pump nil)
           (sdl2:with-sdl-event (native :mousewheel)
             (setf (native :wheel :which) #xffffffff
                   (native :wheel :window-id) 70
                   (native :wheel :x) 1 (native :wheel :y) -2
                   (native :wheel :direction) 0)
             (%mouse-test-set-wheel-precise native 0.25 -1.5)
             (sdl2:push-event native)
             ;; SDL copies on push; overwrite the source union before polling.
             (setf (native :wheel :which) 12
                   (native :wheel :window-id) 71
                   (native :wheel :x) 99 (native :wheel :y) 99)
             (setf (native :wheel :which) 12
                   (native :wheel :window-id) 71
                   (native :wheel :x) -3 (native :wheel :y) 4
                   (native :wheel :direction) 0)
             (%mouse-test-set-wheel-precise native -2.25 3.5)
             (sdl2:push-event native))
           ;; GET reuses SDL's transient union while decoding the queued events.
           (let ((events (px.event:get :types :mouse-wheel)))
             (is (= 2 (length events)))
             (let ((touch-event (first events)) (mouse-event (second events)))
               (is (= 1 (px.event:attribute touch-event :x)))
               (is (= -2 (px.event:attribute touch-event :y)))
               (is (= #xffffffff (px.event:attribute touch-event :which)))
               (is (px.event:attribute touch-event :touch))
               (is (= 70 (px.event:attribute touch-event :window-id)))
               (is (null (px.event:attribute touch-event :flipped)))
               (is (= -3 (px.event:attribute mouse-event :x)))
               (is (= 4 (px.event:attribute mouse-event :y)))
               (is (= 12 (px.event:attribute mouse-event :which)))
               (is (null (px.event:attribute mouse-event :touch)))
               (is (= 71 (px.event:attribute mouse-event :window-id)))
               (is (null (px.event:attribute mouse-event :flipped)))
               (when (px.event::%sdl-version-at-least-p 2 0 18)
                 (is (= 0.25 (px.event:attribute touch-event :precise-x)))
                 (is (= -1.5 (px.event:attribute touch-event :precise-y)))
                 (is (= -2.25 (px.event:attribute mouse-event :precise-x)))
                 (is (= 3.5 (px.event:attribute mouse-event :precise-y)))))))
      (px.event:clear nil :pump nil))))
