(in-package #:pixelisp.examples)

;;;; Crater Command: shape each shot with angle and power, then use the holes
;;;; from earlier impacts to open a clear lane through the hostile landscape.

(defparameter +crater-command-terrain-profile+
  '((24 425) (130 415) (245 430) (350 390) (410 350) (455 354)
    (510 405) (590 415) (675 406) (760 422) (876 411)))

(defstruct (%crater-command-state (:constructor %crater-command-state
                                         (&key (angle 48.0) (power 440.0) (ammo 12)
                                               (score 0) (target-hp (list 1 1 1))
                                               projectile (status :playing))))
  (angle 48.0 :type real)
  (power 440.0 :type real)
  (ammo 12 :type integer)
  (score 0 :type integer)
  (target-hp '(1 1 1))
  projectile
  (status :playing))

(defun %crater-command-new-state ()
  (%crater-command-state))

(defun %crater-command-target-count (state)
  (count-if #'plusp (%crater-command-state-target-hp state)))

(defun %crater-command-snapshot (state)
  (list :status (%crater-command-state-status state)
        :score (%crater-command-state-score state)
        :ammo (%crater-command-state-ammo state)
        :remaining (%crater-command-target-count state)
        :angle (round (%crater-command-state-angle state))
        :power (round (%crater-command-state-power state))))

(defun %crater-command-aim (state seconds left right up down)
  "Apply aim controls in units per second, so movement is frame-rate neutral."
  (let ((seconds (max 0.0 seconds)))
    (incf (%crater-command-state-angle state)
          (* seconds 36.0 (- (if right 1 0) (if left 1 0))))
    (incf (%crater-command-state-power state)
          (* seconds 150.0 (- (if up 1 0) (if down 1 0))))
    (setf (%crater-command-state-angle state)
          (max 20.0 (min 78.0 (%crater-command-state-angle state)))
          (%crater-command-state-power state)
          (max 350.0 (min 560.0 (%crater-command-state-power state)))))
  state)

(defun %crater-command-ground-height (x)
  "Interpolate the visible ground profile for trajectory planning and tests."
  (loop for (left-x left-y) in +crater-command-terrain-profile+
        for (right-x right-y) in (cdr +crater-command-terrain-profile+)
        when (<= left-x x right-x)
          return (+ left-y (* (/ (- x left-x) (- right-x left-x))
                              (- right-y left-y)))))

(defun %crater-command-launch-origin (angle)
  (let ((radians (* pi (/ angle 180.0))))
    (values (+ 110.0 (* 52.0 (cos radians)))
            (- 420.0 (* 52.0 (sin radians))))))

(defun %crater-command-shot-reaches-p (angle power target)
  "Pure trajectory check used to keep the puzzle's reactor lanes solvable."
  (let* ((radians (* pi (/ angle 180.0)))
         (vx (* power (cos radians)))
         (vy (* (- power) (sin radians))))
    (multiple-value-bind (origin-x origin-y) (%crater-command-launch-origin angle)
      (let* ((target-x (first target))
             (target-y (second target))
             (flight-time (/ (- target-x origin-x) vx))
             (impact-y (+ origin-y (* vy flight-time)
                           (* 0.5 230.0 flight-time flight-time))))
        (and (<= (abs (- impact-y target-y)) 9.0)
             (loop for x from (ceiling origin-x) below target-x by 3
                   for time = (/ (- x origin-x) vx)
                   for y = (+ origin-y (* vy time) (* 115.0 time time))
                   for ground = (%crater-command-ground-height x)
                   always (or (null ground) (< y (- ground 2.0)))))))))

(defun %crater-command-fire (state)
  (when (and (eq :playing (%crater-command-state-status state))
             (null (%crater-command-state-projectile state))
             (plusp (%crater-command-state-ammo state)))
    (let* ((angle (* pi (/ (%crater-command-state-angle state) 180.0)))
           (power (%crater-command-state-power state)))
      (decf (%crater-command-state-ammo state))
      (multiple-value-bind (origin-x origin-y)
          (%crater-command-launch-origin (%crater-command-state-angle state))
        (setf (%crater-command-state-projectile state)
            (list :x origin-x :y origin-y
                  :vx (* power (cos angle))
                  :vy (* (- power) (sin angle)))))
      t)))

(defun %crater-command-hit-target (state index)
  "Damage one target and resolve victory."
  (let ((hp (%crater-command-state-target-hp state)))
    (when (and (<= 0 index) (< index (length hp)) (plusp (nth index hp)))
      (decf (nth index hp))
      (incf (%crater-command-state-score state) 100)
      (when (zerop (%crater-command-target-count state))
        (setf (%crater-command-state-status state) :won))
      t)))

(defun %crater-command-carve (terrain mask crater-mask x y)
  "Erase a cached crater from collision and alpha data; return cleared pixels."
  (let* ((radius-x (px.mask:width crater-mask))
         (radius-y (px.mask:height crater-mask))
         (left (- (round x) (floor radius-x 2)))
         (top (- (round y) (floor radius-y 2)))
         (cleared 0))
    (px.mask:erase mask crater-mask (list left top))
    ;; The shared alpha view locks the surface. Close it before the next blit.
    (px.buffer:with-view (alpha (px.surface:get-view terrain #\a))
      (dotimes (cy radius-y)
        (dotimes (cx radius-x)
          (when (= 1 (px.mask:get-at crater-mask (list cx cy)))
            (let ((tx (+ left cx)) (ty (+ top cy)))
              (when (and (<= 0 tx) (< tx (px.surface:width terrain))
                         (<= 0 ty) (< ty (px.surface:height terrain)))
                (when (plusp (px.buffer:view-ref alpha tx ty)) (incf cleared))
                (setf (px.buffer:view-ref alpha tx ty) 0))))))
    cleared)))

(defun %crater-command-ground-p (mask x y)
  (let ((ix (round x)) (iy (round y)))
    (and (<= 0 ix) (< ix (px.mask:width mask))
         (<= 0 iy) (< iy (px.mask:height mask))
         (= 1 (px.mask:get-at mask (list ix iy))))))

(defun %crater-command-step-shell (state dt terrain-mask crater-mask terrain targets)
  "Integrate one short slice, then resolve a reactor, terrain, or boundary hit."
  (let* ((shell (%crater-command-state-projectile state))
         (x (+ (getf shell :x) (* (getf shell :vx) dt)))
         (y (+ (getf shell :y) (* (getf shell :vy) dt)))
         (target-index
           (loop for target in targets for index from 0
                 when (and (plusp (nth index (%crater-command-state-target-hp state)))
                           (< (+ (expt (- x (first target)) 2)
                                 (expt (- y (second target)) 2)) 121.0))
                   return index)))
    (incf (getf shell :vy) (* 230.0 dt))
    (setf (getf shell :x) x (getf shell :y) y)
    (cond
      (target-index
       (%crater-command-hit-target state target-index)
       (%crater-command-carve terrain terrain-mask crater-mask x y)
       (incf (%crater-command-state-score state) 15)
       (setf (%crater-command-state-projectile state) nil))
      ((%crater-command-ground-p terrain-mask x y)
       (%crater-command-carve terrain terrain-mask crater-mask x y)
       (incf (%crater-command-state-score state) 5)
       (setf (%crater-command-state-projectile state) nil))
      ((or (< x 24) (> x 876) (< y 98) (> y 558))
       (setf (%crater-command-state-projectile state) nil)))))

(defun %crater-command-advance (state seconds terrain-mask crater-mask terrain targets)
  "Use short slices so a fast shell cannot jump through a narrow reactor."
  (when (%crater-command-state-projectile state)
    (let* ((slices (max 1 (ceiling (* seconds 120)))) (dt (/ seconds slices)))
      (loop repeat slices while (%crater-command-state-projectile state)
            do (%crater-command-step-shell state dt terrain-mask crater-mask terrain targets))))
  ;; The final shell must finish its flight before an empty magazine is a loss.
  (when (and (eq :playing (%crater-command-state-status state))
             (zerop (%crater-command-state-ammo state))
             (null (%crater-command-state-projectile state)))
    (setf (%crater-command-state-status state) :lost))
  state)

(defun %crater-command-terrain ()
  "Create the fixed, gently rolling battlefield; crater edits happen in play."
  (let ((surface (px.surface:make-surface '(900 620) :alpha t)))
    (px.surface:fill surface '(0 0 0 0))
    ;; A broad ridge forces players to alter their launch angle, while the
    ;; low ground between the ridge and reactors gives craters useful value.
    (px.draw:polygon surface '(62 115 83 255)
                     (append +crater-command-terrain-profile+
                             '((876 558) (24 558))))
    (loop for first in +crater-command-terrain-profile+
          for second in (cdr +crater-command-terrain-profile+)
          do (px.draw:line surface '(116 184 127) first second :width 2))
    surface))

(defun make-crater-command (session)
  "Return a finite artillery puzzle with mutable terrain and three reactors."
  (let* ((terrain (%crater-command-terrain))
         (terrain-source (px.surface:copy terrain))
         (terrain-mask (px.mask:from-surface terrain))
         (crater-image (%circle-image 27 '(0 0 0 255)))
         (crater-mask (px.mask:from-surface crater-image))
         (cannon-tube (px.surface:make-surface '(60 18) :alpha t))
         (cannon-frames (make-array 59))
         (cannon-base (px.surface:make-surface '(40 40) :alpha t))
         (targets '((635 404) (735 414) (835 406)))
         (target-art (px.surface:make-surface '(34 42) :alpha t))
         (shell-art (%circle-image 5 '(255 226 145)))
         (state (%crater-command-new-state))
         (shot-tone 640) (impact-tone 180) (hit-tone 920))
    (declare (ignore session))
    (px.surface:fill cannon-tube '(0 0 0 0))
    (px.draw:line cannon-tube '(75 104 118) '(3 9) '(58 9) :width 12)
    (px.draw:line cannon-tube '(160 189 197) '(17 5) '(55 5) :width 2)
    ;; Rotate the barrel once per integer aim angle and reuse those frames.
    (loop for angle from 20 to 78
          do (setf (aref cannon-frames (- angle 20))
                   (px.transform:rotate cannon-tube angle)))
    (px.surface:fill cannon-base '(0 0 0 0))
    (px.draw:circle cannon-base '(56 69 81) '(20 20) 18)
    (px.draw:circle cannon-base '(188 199 201) '(17 17) 7)
    (px.surface:fill target-art '(0 0 0 0))
    (px.draw:polygon target-art '(65 240 170)
                     '((17 0) (31 10) (29 30) (17 41) (4 30) (2 10)))
    (px.draw:circle target-art '(232 255 192) '(17 18) 6)
    (make-mini-game
     :id :crater-command :title "CRATER COMMAND"
     :instructions "←/→ aim · ↑/↓ power · SPACE fire"
     :state state
     :on-event (lambda (current event game-session)
                 (when (and (eq :key-down (px.event:type event))
                            (eq :space (px.event:attribute event :key)))
                   (when (%crater-command-fire current)
                     (%play-tone game-session shot-tone :duration 0.09 :volume 0.17)))
                 current)
     :on-step (lambda (current seconds game-session)
                (when (eq :playing (%crater-command-state-status current))
                  (%crater-command-aim current seconds
                                       (%held-p game-session :left)
                                       (%held-p game-session :right)
                                       (%held-p game-session :up)
                                       (%held-p game-session :down))
                  (let* ((had-projectile (%crater-command-state-projectile current))
                         (score-before (%crater-command-state-score current)))
                    (%crater-command-advance current seconds terrain-mask crater-mask terrain targets)
                    (when (and had-projectile (null (%crater-command-state-projectile current)))
                      (%play-tone game-session
                                  (if (>= (- (%crater-command-state-score current) score-before) 100)
                                      hit-tone impact-tone)
                                  :duration 0.14 :volume 0.22))))
                current)
     :on-draw (lambda (current game-session)
                (let ((screen (session-screen game-session)))
                  (px.surface:fill screen '(13 24 42))
                  (px.surface:fill screen '(18 38 61) '(24 98 852 460))
                  (px.surface:blit screen terrain '(0 0))
                  (loop for target in targets
                        for index from 0
                        when (plusp (nth index (%crater-command-state-target-hp current)))
                          do (px.surface:blit screen target-art
                                              (list (- (first target) 17) (- (second target) 20))))
                  (let* ((angle (round (%crater-command-state-angle current)))
                         (radians (* pi (/ angle 180.0)))
                         (center (list (+ 110.0 (* 25.0 (cos radians)))
                                       (- 420.0 (* 25.0 (sin radians)))))
                         (barrel-rect (px.surface:get-rect
                                       (aref cannon-frames (- angle 20)) :center center)))
                    (px.surface:blit screen (aref cannon-frames (- angle 20))
                                     (px.rect:top-left barrel-rect)))
                  (px.surface:blit screen cannon-base '(90 400))
                  (when (%crater-command-state-projectile current)
                    (let ((p (%crater-command-state-projectile current)))
                      (px.surface:blit screen shell-art
                                       (list (- (round (getf p :x)) 5)
                                             (- (round (getf p :y)) 5)))))
                  (%hud game-session "CRATER COMMAND" (%crater-command-state-score current)
                        :subtitle (format nil "Reactors ~D/3 · ~D shells"
                                          (- 3 (%crater-command-target-count current))
                                          (%crater-command-state-ammo current)))
                  (%text game-session
                         (format nil "ANGLE ~D°     POWER ~D"
                                 (round (%crater-command-state-angle current))
                                 (round (%crater-command-state-power current)))
                         36 526 :size 19 :color '(220 231 240)))
                current)
     :on-reset (lambda (game-session)
                 (declare (ignore game-session))
                 (px.surface:fill terrain '(0 0 0 0))
                 (px.surface:blit terrain terrain-source '(0 0))
                 (setf terrain-mask (px.mask:from-surface terrain))
                 (%crater-command-new-state))
     :snapshot #'%crater-command-snapshot)))
