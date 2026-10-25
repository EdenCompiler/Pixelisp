(in-package #:pixelisp.examples.tests)
(in-suite examples)

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
