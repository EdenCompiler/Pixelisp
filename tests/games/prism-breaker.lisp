(in-package #:pixelisp.examples.tests)
(in-suite examples)

(test prism-breaker-stick-dead-zone-keeps-resting-input-still
  (is (= 0 (px.examples::%breaker-stick 0.1d0)))
  (is (= 0 (px.examples::%breaker-stick -0.1d0)))
  (is (= 1 (px.examples::%breaker-stick 1d0)))
  (is (= -1 (px.examples::%breaker-stick -1d0))))

(test prism-breaker-virtual-gamepad-moves-and-serves-through-real-device-state
  (px:with-init ()
    (px.controller:init)
    (let ((index (cffi:foreign-funcall "SDL_JoystickAttachVirtual"
                                     :int 1 :int 6 :int 21 :int 1 :int))
          (controller nil) (input nil) (detached nil))
      (is (not (minusp index)))
      (unwind-protect
           (progn
             (px.joystick:with-joystick (original index)
               (px.controller:add-mapping
                (format nil "~A,Pixelisp Breaker Test,leftx:a0,a:b0,dpleft:b13,dpright:b14,"
                        (px.joystick:get-guid original)))
               (setf controller (px.controller:from-joystick original)))
             ;; The original joystick is closed. This independent reference
             ;; drives virtual input while the game polls its mapped controller.
             (setf input (px.controller:as-joystick controller))
             (let ((state (px.examples::%breaker-new-state))
                   (session (px.examples::make-game-session :mouse-pos '(450 300))))
               (setf (getf state :last-mouse-x) 450)
               (cffi:foreign-funcall "SDL_JoystickSetVirtualAxis"
                                    :pointer (pixelisp.internal:handle input)
                                    :int 0 :int16 16384 :int)
               (px.joystick:update)
               (px.examples::%breaker-step state 0.1d0 session controller)
               (is (> (getf state :paddle-x) 398))
               ;; A dpad press must work even with the analog stick at rest.
               (let ((previous-x (getf state :paddle-x)))
                 (cffi:foreign-funcall "SDL_JoystickSetVirtualAxis"
                                      :pointer (pixelisp.internal:handle input)
                                      :int 0 :int16 0 :int)
                 (cffi:foreign-funcall "SDL_JoystickSetVirtualButton"
                                      :pointer (pixelisp.internal:handle input)
                                      :int 13 :uint8 1 :int)
                 (px.joystick:update)
                 (px.examples::%breaker-step state 0.1d0 session controller)
                 (is (< (getf state :paddle-x) previous-x)))
               (px.examples::%breaker-event
                state (px.event:make-event :controller-button-down :which -100 :button 0)
                session controller)
               (is (not (getf state :launched)))
               (px.event:clear nil)
               (cffi:foreign-funcall "SDL_JoystickSetVirtualButton"
                                    :pointer (pixelisp.internal:handle input)
                                    :int 0 :uint8 1 :int)
               (px.joystick:update)
               (let ((event (find (px.controller:instance-id controller)
                                  (px.event:get :types :controller-button-down)
                                  :key (lambda (event) (px.event:attribute event :which)))))
                 (is (not (null event)))
                 (when event (px.examples::%breaker-event state event session controller)))
               (is (getf state :launched))
               (is (= 1 (getf state :launches))))
             ;; Removal is identified by instance ID, even though enumeration
             ;; indices shift. A different available pad may take over.
             (let ((id (px.controller:instance-id controller)))
               (cffi:foreign-funcall "SDL_JoystickDetachVirtual" :int index :int)
               (setf detached t)
               (let ((replacement (px.examples::%breaker-controller-event
                                   controller (px.event:make-event :controller-device-removed :which id))))
                 (is (not (eq replacement controller)))
                 (is (pixelisp.internal:resource-disposed-p controller))
                 (when replacement (px:dispose replacement)))))
        (when input (px:dispose input))
        (when controller (px:dispose controller))
        (unless detached (cffi:foreign-funcall "SDL_JoystickDetachVirtual" :int index :int))))))

(test prism-breaker-shading-broadcasts-scoring-colors-and-releases-the-view
  (px:with-init (:video nil)
    (px:with-resource (brick (px.examples::%breaker-brick-image '(255 88 122)))
      (is (equal '(68 24) (px.surface:size brick)))
      ;; The whole row shares a color, while its lower rows darken. The prism
      ;; keeps the same color cue that tells players which row they cleared.
      (is (equalp (px.surface:get-at brick '(0 10))
                  (px.surface:get-at brick '(67 10))))
      (is (> (px:color-r (px.surface:get-at brick '(32 5)))
             (px:color-r (px.surface:get-at brick '(32 18)))))
      (is (= 255 (px:color-a (px.surface:get-at brick '(32 10)))))
      (is (not (px.surface:locked-p brick)))))
  (is (%clean-run-p)))

(test prism-breaker-brick-impact-scores-and-clears-objective
  (let ((state (px.examples::%breaker-new-state)))
    ;; Put the ball just below an isolated brick and drive it upward through it.
    (setf (getf state :bricks) '((901 100 100 68 24 0))
          (getf state :remaining) 1
          (getf state :launched) t
          (getf state :ball-x) 120d0
          (getf state :ball-y) 125d0
          (getf state :vx) 0d0
          (getf state :vy) -80d0)
    (px.examples::%breaker-advance state 0.05d0)
    (is (= 50 (getf state :score)))
    (is (null (getf state :bricks)))
    (is (= 0 (getf state :remaining)))
    (is (eq :won (getf state :status)))))

(test prism-breaker-ball-loss-and-final-life
  (let ((state (px.examples::%breaker-new-state)))
    (setf (getf state :launched) t
          (getf state :ball-y) 557d0
          (getf state :vy) 300d0)
    (px.examples::%breaker-advance state 0.02d0)
    (is (= 2 (getf state :lives)))
    (is (not (getf state :launched)))
    (is (= 510d0 (getf state :ball-y)))
    (setf (getf state :lives) 1)
    (px.examples::%breaker-miss-ball state)
    (is (eq :lost (getf state :status)))
    (is (= 0 (getf state :lives)))))

(test prism-breaker-finite-win-and-reset
  (let ((state (px.examples::%breaker-new-state)))
    (setf (getf state :bricks) '((77 80 120 68 24 2))
          (getf state :remaining) 1)
    (px.examples::%breaker-hit-brick state 77)
    (is (eq :won (getf state :status)))
    (is (= 150 (getf state :score)))
    (let ((fresh (px.examples::%breaker-reset-state)))
      (is (eq :playing (getf fresh :status)))
      (is (= 3 (getf fresh :lives)))
      (is (= 60 (getf fresh :remaining)))
      (is (zerop (getf fresh :score))))))

(test prism-breaker-paddle-movement-and-launch
  (let ((state (px.examples::%breaker-new-state)))
    (px.examples::%breaker-move-paddle state -10000)
    (is (= 32 (getf state :paddle-x)))
    (px.examples::%breaker-move-paddle state 10000)
    (is (= 764 (getf state :paddle-x)))
    (px.examples::%breaker-launch state)
    (is (getf state :launched))
    (is (= 1 (getf state :launches)))
    (px.examples::%breaker-launch state)
    (is (= 1 (getf state :launches)))))

(test prism-breaker-held-arrows-accumulate-and-release-in-place
  (let ((state (px.examples::%breaker-new-state))
        (left-session (px.examples::make-game-session
                       :held-keys '(:left) :mouse-pos '(450 300)))
        (released-session (px.examples::make-game-session
                           :held-keys nil :mouse-pos '(450 300))))
    (dotimes (frame 3)
      (declare (ignore frame))
      (px.examples::%breaker-step state 0.1d0 left-session))
    (is (= 269.0d0 (getf state :paddle-x)))
    (px.examples::%breaker-step state 0.1d0 released-session)
    (is (= 269.0d0 (getf state :paddle-x)))))
