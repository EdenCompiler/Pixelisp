;;;; Prism Breaker — a compact brick breaker built for the shared mini-game runner.
(in-package #:pixelisp.examples)

(defconstant +breaker-left+ 32)
(defconstant +breaker-right+ 868)
(defconstant +breaker-top+ 112)
(defconstant +breaker-bottom+ 558)
(defconstant +breaker-ball-size+ 14)
(defconstant +breaker-paddle-width+ 104)

(defun %breaker-new-state ()
  "Create a fresh, native-independent round of Prism Breaker."
  (let ((bricks nil))
    ;; Six rows form a finite objective. The staggered palette is also a visual
    ;; hint: deeper rows are worth more points as the player clears them.
    (loop for row below 6
          for y from 144 by 34
          do (loop for column below 10
                   for x from 56 by 78
                   do (push (list (+ (* row 10) column) x y 68 24 row) bricks)))
    (list :status :playing :score 0 :lives 3 :combo 0 :remaining (length bricks)
          :bricks (nreverse bricks) :paddle-x 398
          :last-mouse-x nil
          :ball-x 443 :ball-y 510 :vx 0d0 :vy 0d0 :launched nil
          :launches 0)))

(defun %breaker-reset-state ()
  "Reset gameplay state without allocating or depending on SDL assets."
  (%breaker-new-state))

(defun %breaker-ball-rect (state)
  (px:make-rect (round (getf state :ball-x)) (round (getf state :ball-y))
                +breaker-ball-size+ +breaker-ball-size+))

(defun %breaker-paddle-rect (state)
  (px:make-rect (round (getf state :paddle-x)) 526 +breaker-paddle-width+ 16))

(defun %breaker-move-paddle (state dx)
  "Move the paddle by DX and keep it inside the side walls."
  (setf (getf state :paddle-x)
        (max +breaker-left+ (min (- +breaker-right+ +breaker-paddle-width+)
                                 (+ (getf state :paddle-x) dx))))
  state)

(defun %breaker-launch (state)
  "Launch a resting ball. Repeated launch requests while flying are ignored."
  (when (and (eq (getf state :status) :playing) (not (getf state :launched)))
    (setf (getf state :launched) t
          (getf state :vx) 145d0
          (getf state :vy) -310d0)
    (incf (getf state :launches)))
  state)

(defun %breaker-hit-brick (state brick-id)
  "Remove one brick and apply its row value plus a rising combo bonus."
  (let ((brick (find brick-id (getf state :bricks) :key #'first)))
    (when brick
      (setf (getf state :bricks) (delete brick (getf state :bricks) :test #'eq)
            (getf state :combo) (1+ (getf state :combo)))
      (incf (getf state :score) (* 50 (1+ (sixth brick)) (getf state :combo)))
      (decf (getf state :remaining))
      (when (zerop (getf state :remaining))
        (setf (getf state :status) :won))))
  state)

(defun %breaker-miss-ball (state)
  "Consume one life; either reset the ball for another serve or finish lost."
  (when (eq (getf state :status) :playing)
    (decf (getf state :lives))
    (setf (getf state :combo) 0)
    (if (zerop (getf state :lives))
        (setf (getf state :status) :lost
              (getf state :launched) nil)
        (setf (getf state :launched) nil
              (getf state :ball-x) (+ (getf state :paddle-x) 45)
              (getf state :ball-y) 510
              (getf state :vx) 0d0
              (getf state :vy) 0d0)))
  state)

(defun %breaker-reflect (state normal)
  "Reflect the ball velocity vector across NORMAL using the shared vector API."
  (let ((reflected (px.math:reflect (px:make-vector2 (getf state :vx) (getf state :vy)) normal)))
    (setf (getf state :vx) (px.math:x reflected)
          (getf state :vy) (px.math:y reflected)))
  state)

(defun %breaker-paddle-bounce (state)
  ;; Contact offset controls the outgoing angle, while reflection preserves a
  ;; meaningful vector-physics response for the paddle's upward normal.
  (let* ((ball-center (+ (getf state :ball-x) (/ +breaker-ball-size+ 2)))
         (paddle-center (+ (getf state :paddle-x) (/ +breaker-paddle-width+ 2)))
         (offset (max -1d0 (min 1d0 (/ (- ball-center paddle-center) 48d0))))
         (speed (max 335d0 (min 470d0 (px.math:length
                                      (px:make-vector2 (getf state :vx) (getf state :vy)))))))
    (%breaker-reflect state (px:make-vector2 0 -1))
    (setf (getf state :vx) (* speed offset 0.78d0)
          (getf state :vy) (- (sqrt (max 1d0 (- (* speed speed)
                                                (* (getf state :vx) (getf state :vx)))))))
    state))

(defun %breaker-advance (state seconds)
  "Advance ball physics in short slices so thin bricks cannot be skipped."
  (when (and (eq (getf state :status) :playing) (getf state :launched))
    (let ((steps (max 1 (ceiling (* seconds 120)))))
      (dotimes (step steps)
        (declare (ignore step))
        (let* ((dt (/ seconds steps))
               (old-x (getf state :ball-x)))
          (incf (getf state :ball-x) (* (getf state :vx) dt))
          (incf (getf state :ball-y) (* (getf state :vy) dt))
          ;; Side and ceiling bounces use vector reflection, then reposition
          ;; the ball just inside the boundary to prevent repeated collisions.
          (when (< (getf state :ball-x) +breaker-left+)
            (setf (getf state :ball-x) +breaker-left+)
            (%breaker-reflect state (px:make-vector2 1 0)))
          (when (> (+ (getf state :ball-x) +breaker-ball-size+) +breaker-right+)
            (setf (getf state :ball-x) (- +breaker-right+ +breaker-ball-size+))
            (%breaker-reflect state (px:make-vector2 -1 0)))
          (when (< (getf state :ball-y) +breaker-top+)
            (setf (getf state :ball-y) +breaker-top+)
            (%breaker-reflect state (px:make-vector2 0 1)))
          (let ((ball (%breaker-ball-rect state))
                (paddle (%breaker-paddle-rect state)))
            (when (and (> (getf state :vy) 0)
                       (px.rect:collide-rect ball paddle))
              (setf (getf state :ball-y) (- 526 +breaker-ball-size+))
              (%breaker-paddle-bounce state))
            ;; Test one brick per slice. Position history chooses the collision
            ;; normal, preserving the reflected component on corner approach.
            (let ((brick (find-if (lambda (candidate)
                                    (px.rect:collide-rect ball
                                      (px:make-rect (second candidate) (third candidate)
                                                    (fourth candidate) (fifth candidate))))
                                  (getf state :bricks))))
              (when brick
                (let ((brick-rect (px:make-rect (second brick) (third brick)
                                                (fourth brick) (fifth brick))))
                  (if (or (< (+ old-x +breaker-ball-size+) (px.rect:x brick-rect))
                          (> old-x (+ (px.rect:x brick-rect) (px.rect:width brick-rect))))
                      (%breaker-reflect state (px:make-vector2 (if (< (getf state :vx) 0) 1 -1) 0))
                      (%breaker-reflect state (px:make-vector2 0 (if (< (getf state :vy) 0) 1 -1))))
                  (%breaker-hit-brick state (first brick))))))
          (when (and (eq (getf state :status) :playing)
                     (> (getf state :ball-y) +breaker-bottom+))
            (%breaker-miss-ball state))))))
  state)

(defun %breaker-event (state event session)
  (declare (ignore session))
  (when (and (eq (px.event:type event) :key-down)
             (eq (px.event:attribute event :key) :space))
    (%breaker-launch state))
  state)

(defun %breaker-step (state seconds session)
  (let* ((mouse (session-mouse-pos session))
         (left (%held-p session :left)) (right (%held-p session :right)))
    ;; Snap only when the pointer actually changes. This lets arrow movement
    ;; accumulate while the pointer is still, then resume direct mouse control
    ;; on the next motion without a stale pointer yanking the paddle back.
    (when (and (consp mouse) (numberp (first mouse))
               (or (null (getf state :last-mouse-x))
                   (/= (first mouse) (getf state :last-mouse-x))))
      (setf (getf state :paddle-x)
            (max +breaker-left+ (min (- +breaker-right+ +breaker-paddle-width+)
                                     (- (first mouse) (/ +breaker-paddle-width+ 2))))))
    (when (and (consp mouse) (numberp (first mouse)))
      (setf (getf state :last-mouse-x) (first mouse)))
    (%breaker-move-paddle state (* 430d0 seconds (- (if right 1 0) (if left 1 0))))
    (unless (getf state :launched)
      (setf (getf state :ball-x) (+ (getf state :paddle-x) 45)))
    (%breaker-advance state seconds)))

(defun %breaker-snapshot (state)
  (list :status (getf state :status) :score (getf state :score)
        :lives (getf state :lives) :remaining (getf state :remaining)
        :launched (not (null (getf state :launched)))
        :launches (getf state :launches) :combo (getf state :combo)))

(defun %breaker-brick-image (color)
  "Shade a prism in its scoring row's color, then cache it for native blits."
  (let ((image (px.surface:make-surface '(68 24) :alpha t))
        ;; Pixel arrays use X/Y order. One column of colors will broadcast
        ;; across every column of the brick, keeping the gradient code small.
        (rows (make-array '(1 24)))
        (complete nil))
    (unwind-protect
         (progn
           (dotimes (y 24)
             (setf (aref rows 0 y)
                   (cond ((< y 3) '(255 255 255 120))
                         ((>= y 20) '(30 39 64 100))
                         (t (append (mapcar (lambda (channel)
                                              (round (* channel (- 1 (/ y 92)))))
                                            color)
                                    '(255))))))
           ;; ASSIGN validates and maps all colors before touching the image.
           ;; Closing the view releases its surface lock before gameplay draws.
           (px.pixelarray:with-pixel-array (pixels image)
             (px.pixelarray:assign pixels rows))
           (setf complete t)
           image)
      (unless complete (px:dispose image)))))

(defun make-prism-breaker (session)
  "Build the Prism Breaker callback bundle and cache all reusable art once."
  (let* ((screen (session-screen session))
         (background (px.surface:make-surface '(900 620)))
         (brick-images (loop for color in '((255 88 122) (255 151 83) (255 211 91)
                                           (104 225 186) (83 196 255) (177 139 255))
                             collect (%breaker-brick-image color)))
         (paddle (px.surface:make-surface '(104 16) :alpha t))
         (ball (px.surface:make-surface '(16 16) :alpha t)))
    (px.surface:fill background '(10 17 33))
    (px.draw:rect background '(17 29 51) '(32 112 836 446))
    (px.draw:rect background '(43 60 91) '(32 112 836 446) :width 2)
    ;; Soft side rails and a thin lower danger line clarify the play field.
    (px.draw:rect background '(52 79 114) '(34 114 3 442))
    (px.draw:rect background '(52 79 114) '(863 114 3 442))
    (px.draw:rect background '(255 91 117) '(32 556 836 2))
    (px.surface:fill paddle '(64 224 244))
    (px.draw:rect paddle '(210 255 255) '(8 2 88 3))
    (px.draw:rect paddle '(29 121 172) '(0 12 104 4))
    (px.draw:circle ball '(247 252 255) '(8 8) 7)
    (px.draw:circle ball '(131 231 255) '(6 6) 3)
    (make-mini-game :id :prism-breaker :title "PRISM BREAKER"
          :instructions "Mouse / ← → move · Space launch"
          :state (%breaker-new-state)
          :on-event (lambda (state event current-session)
                      (let ((before (getf state :launched)))
                        (%breaker-event state event current-session)
                        (when (and (not before) (getf state :launched))
                          (%play-tone current-session 540 :duration 0.08 :volume 0.20)))
                      state)
          :on-step (lambda (state seconds current-session)
                     (let ((previous-score (getf state :score))
                           (previous-lives (getf state :lives)))
                       (%breaker-step state seconds current-session)
                       (when (> (getf state :score) previous-score)
                         (%play-tone current-session (+ 620 (* 28 (getf state :combo)))
                                     :duration 0.07 :volume 0.18))
                       (when (< (getf state :lives) previous-lives)
                         (%play-tone current-session 180 :duration 0.18 :volume 0.25)))
                     state)
          :on-draw (lambda (state current-session)
                     (px.surface:blit screen background '(0 0))
                     (%hud current-session "PRISM BREAKER" (getf state :score)
                           :subtitle (format nil "~D prisms left · combo ×~D"
                                             (getf state :remaining) (max 1 (getf state :combo)))
                           :lives (getf state :lives))
                     (dolist (brick (getf state :bricks))
                       (px.surface:blit screen (nth (sixth brick) brick-images)
                                        (list (second brick) (third brick))))
                     (px.surface:blit screen paddle (list (round (getf state :paddle-x)) 526))
                     (px.surface:blit screen ball
                                      (list (round (getf state :ball-x)) (round (getf state :ball-y))))
                     state)
          :on-reset (lambda (current-session)
                      (declare (ignore current-session)) (%breaker-reset-state))
          :snapshot #'%breaker-snapshot)))
