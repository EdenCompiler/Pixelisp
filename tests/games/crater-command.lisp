(in-package #:pixelisp.examples.tests)
(in-suite examples)

(test crater-command-shell-has-readable-ballistics
  (px:with-init ()
    (let* ((state (px.examples::%crater-command-new-state))
           (terrain (px.surface:make-surface '(900 620) :alpha t))
           (ground (px.mask:make-mask '(900 620)))
           (crater (px.mask:make-mask '(3 3) :fill t)))
      (unwind-protect
           (progn
             (is (px.examples::%crater-command-fire state))
             (let* ((shell (px.examples::%crater-command-state-projectile state))
                    (start-x (getf shell :x))
                    (start-y (getf shell :y)))
               (px.examples::%crater-command-advance state 0.5 ground crater terrain nil)
               (is (> (getf shell :x) start-x))
               (is (< (getf shell :y) start-y))
               (is (= 11 (px.examples::%crater-command-state-ammo state)))
               (is (px.examples::%crater-command-state-projectile state))))
        (px:dispose terrain)))))

(test crater-command-impact-clears-alpha-and-collision
  (px:with-init ()
    (let ((terrain (px.surface:make-surface '(20 20) :alpha t))
          (ground (px.mask:make-mask '(20 20) :fill t))
          (crater (px.mask:make-mask '(5 5) :fill t)))
      (unwind-protect
           (progn
             (px.surface:fill terrain '(90 130 80 255))
             (is (plusp (px.examples::%crater-command-carve terrain ground crater 10 10)))
             (is (= 0 (px.mask:get-at ground '(10 10))))
             (is (= 0 (px:color-a (px.surface:get-at terrain '(10 10)))))
             (is (= 1 (px.mask:get-at ground '(0 0)))))
        (px:dispose terrain)))))

(test crater-command-targets-score-and-resolve-the-objective
  (let ((state (px.examples::%crater-command-new-state)))
    (is (px.examples::%crater-command-hit-target state 0))
    (is (= 100 (px.examples::%crater-command-state-score state)))
    (is (= 2 (getf (px.examples::%crater-command-snapshot state) :remaining)))
    (px.examples::%crater-command-hit-target state 1)
    (px.examples::%crater-command-hit-target state 2)
    (is (eq :won (px.examples::%crater-command-state-status state)))
    (is (= 300 (getf (px.examples::%crater-command-snapshot state) :score)))))

(test crater-command-aim-is-time-based-and-reactors-have-clear-shots
  (let ((short-steps (px.examples::%crater-command-new-state))
        (one-step (px.examples::%crater-command-new-state)))
    (px.examples::%crater-command-aim short-steps 0.1 t nil nil nil)
    (px.examples::%crater-command-aim short-steps 0.1 t nil nil nil)
    (px.examples::%crater-command-aim one-step 0.2 t nil nil nil)
    (is (< (abs (- (px.examples::%crater-command-state-angle short-steps)
                   (px.examples::%crater-command-state-angle one-step))) 0.0001))
    (is (< (abs (- (px.examples::%crater-command-state-power short-steps)
                   (px.examples::%crater-command-state-power one-step))) 0.0001)))
  (dolist (solution '((58 351 (635 404))
                      (45 360 (735 414))
                      (45 392 (835 406))))
    (is (px.examples::%crater-command-shot-reaches-p
         (first solution) (second solution) (third solution)))))

(test crater-command-ammo-loss-and-reset-state
  (px:with-init ()
    (let ((state (px.examples::%crater-command-new-state))
          (terrain (px.surface:make-surface '(900 620) :alpha t))
          (ground (px.mask:make-mask '(900 620)))
          (crater (px.mask:make-mask '(3 3) :fill t)))
      (unwind-protect
           (progn
             (dotimes (shot 12)
               (declare (ignore shot))
               (setf (px.examples::%crater-command-state-projectile state) nil)
               (is (px.examples::%crater-command-fire state))
               ;; An out-of-bounds miss resolves this shell immediately.
               (setf (getf (px.examples::%crater-command-state-projectile state) :x) 884)
               (px.examples::%crater-command-advance state 0.01 ground crater terrain nil))
             (is (eq :lost (px.examples::%crater-command-state-status state)))
             (let ((reset (px.examples::%crater-command-new-state)))
               (is (eq :playing (px.examples::%crater-command-state-status reset)))
               (is (= 12 (px.examples::%crater-command-state-ammo reset)))
               (is (= 3 (px.examples::%crater-command-target-count reset)))))
        (px:dispose terrain)))))

(test crater-command-real-shots-can-win-the-battlefield
  (px:with-init ()
    (let* ((session (px.examples::make-game-session))
           (game (px.examples::make-crater-command session))
           (state (px.examples::mini-game-state game)))
      ;; These are normal angle/power choices, run through the same callbacks as
      ;; keyboard input. Collision uses the real terrain and its changing mask.
      (dolist (shot '((58 351) (45 360) (45 392)))
        (setf (px.examples::%crater-command-state-angle state) (first shot)
              (px.examples::%crater-command-state-power state) (second shot))
        (funcall (px.examples::mini-game-on-event game) state
                 (px.event:make-event :key-down :key :space) session)
        (loop repeat 300 while (px.examples::%crater-command-state-projectile state)
              do (funcall (px.examples::mini-game-on-step game) state 0.02d0 session))
        (is (null (px.examples::%crater-command-state-projectile state))))
      (is (eq :won (px.examples::%crater-command-state-status state)))
      (is (= 0 (px.examples::%crater-command-target-count state)))
      (is (= 9 (px.examples::%crater-command-state-ammo state)))
      (is (>= (px.examples::%crater-command-state-score state) 300)))))
