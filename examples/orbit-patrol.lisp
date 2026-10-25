;;;; Orbit Patrol: a compact, finite asteroids-and-drones arcade game.
;;;; Rotations and their matching masks are built once by the factory. The
;;;; update loop only moves actors and tests silhouettes after a cheap bounds test.
(in-package #:pixelisp.examples)

(defstruct (%orbit-actor (:constructor %make-orbit-actor))
  kind (x 0d0) (y 0d0) (vx 0d0) (vy 0d0) (angle 0d0) (age 0d0) (id 0))

(defstruct (%orbit-patrol-state (:constructor %orbit-patrol-state-create))
  (x 450d0) (y 330d0) (vx 0d0) (vy 0d0) (angle 0d0)
  (fire-cooldown 0d0) (invulnerable 0d0) (spawn-clock 0d0)
  (bullets nil) (targets nil) (score 0) (kills 0) (lives 3)
  (next-id 1) (elapsed 0d0) (status :playing))

(defun %orbit-patrol-new-state ()
  "Create a fresh, native-independent Orbit Patrol state."
  (let ((state (%orbit-patrol-state-create)))
    (dotimes (index 4)
      (push (%make-orbit-actor :kind :asteroid
                               :x (+ 130d0 (* index 205d0))
                               :y (if (evenp index) 155d0 485d0)
                               :vx (if (evenp index) 42d0 -38d0)
                               :vy (if (zerop (mod index 3)) 34d0 -29d0)
                               :angle (* index 31d0) :id (incf (%orbit-patrol-state-next-id state)))
            (%orbit-patrol-state-targets state)))
    state))

(defun %orbit-patrol-index (angle)
  (mod (round (* (/ (mod angle 360d0) 360d0) 16)) 16))

(defun %orbit-patrol-fire (state)
  "Fire one bolt when the weapon is ready; return true if it fired."
  (when (and (eq (%orbit-patrol-state-status state) :playing)
             (<= (%orbit-patrol-state-fire-cooldown state) 0d0))
    (let* ((angle (%orbit-patrol-state-angle state))
           (dx (sin (* angle (/ pi 180d0))))
           (dy (- (cos (* angle (/ pi 180d0))))))
      (push (%make-orbit-actor :kind :bolt
                               :x (+ (%orbit-patrol-state-x state) (* 22d0 dx))
                               :y (+ (%orbit-patrol-state-y state) (* 22d0 dy))
                               :vx (+ (%orbit-patrol-state-vx state) (* 410d0 dx))
                               :vy (+ (%orbit-patrol-state-vy state) (* 410d0 dy))
                               :age 0d0
                               :id (incf (%orbit-patrol-state-next-id state)))
            (%orbit-patrol-state-bullets state))
      (setf (%orbit-patrol-state-fire-cooldown state) 0.22d0)
      t)))

(defun %orbit-patrol-hit (state)
  "Record a destroyed target and resolve the finite victory condition."
  (when (eq (%orbit-patrol-state-status state) :playing)
    (incf (%orbit-patrol-state-kills state))
    (incf (%orbit-patrol-state-score state) 100)
    (when (>= (%orbit-patrol-state-kills state) 12)
      (setf (%orbit-patrol-state-status state) :won)))
  state)

(defun %orbit-patrol-remove-target (state target)
  "Remove TARGET exactly once and award the player a confirmed hit."
  (when (and (eq (%orbit-patrol-state-status state) :playing)
             (member target (%orbit-patrol-state-targets state) :test #'eq))
    (setf (%orbit-patrol-state-targets state)
          (delete target (%orbit-patrol-state-targets state) :test #'eq))
    (%orbit-patrol-hit state))
  state)

(defun %orbit-patrol-steer (state dt turn thrusting-p)
  "Apply signed turn input and forward thrust, then damp velocity by elapsed time."
  (incf (%orbit-patrol-state-angle state) (* 205d0 dt turn))
  (let* ((heading (px.math:rotate (px:make-vector2 0 -1) (%orbit-patrol-state-angle state)))
         (thrust (if thrusting-p 260d0 0d0))
         (velocity (px.math:add
                    (px:make-vector2 (%orbit-patrol-state-vx state) (%orbit-patrol-state-vy state))
                    (px.math:multiply heading (* thrust dt))))
         (drag (exp (* 60d0 dt (log 0.994d0)))))
    ;; A swizzle returns ordinary Lisp coordinates, ready for destructuring.
    (destructuring-bind (vx vy) (px.math:swizzle (px.math:multiply velocity drag) "xy")
      (setf (%orbit-patrol-state-vx state) vx (%orbit-patrol-state-vy state) vy)))
  state)

(defun %orbit-patrol-bolt-hits-p (shot target collision-p)
  (let ((dx (- (%orbit-actor-x target) (%orbit-actor-x shot)))
        (dy (- (%orbit-actor-y target) (%orbit-actor-y shot))))
    (and (< (+ (* dx dx) (* dy dy)) 2304d0)
         (or (null collision-p)
             (funcall collision-p
                      :bolt (%orbit-actor-x shot) (%orbit-actor-y shot) 0d0
                      (%orbit-actor-kind target) (%orbit-actor-x target)
                      (%orbit-actor-y target) (%orbit-actor-angle target))))))

(defun %orbit-patrol-resolve-shots (state &optional collision-p)
  "Resolve already-positioned bolts, consuming each confirmed hit exactly once."
  (let ((remaining nil) (hits 0))
    (dolist (shot (%orbit-patrol-state-bullets state))
      (let ((target (when (eq (%orbit-patrol-state-status state) :playing)
                      (find-if (lambda (candidate)
                                 (%orbit-patrol-bolt-hits-p shot candidate collision-p))
                               (%orbit-patrol-state-targets state)))))
        (if target
            (progn (%orbit-patrol-remove-target state target) (incf hits))
            (when (< (%orbit-actor-age shot) 1.6d0) (push shot remaining)))))
    (setf (%orbit-patrol-state-bullets state) (nreverse remaining))
    hits))

(defun %orbit-patrol-damage (state)
  "Apply one collision, respecting the ship's short shield window."
  (when (and (eq (%orbit-patrol-state-status state) :playing)
             (<= (%orbit-patrol-state-invulnerable state) 0d0))
    (decf (%orbit-patrol-state-lives state))
    (setf (%orbit-patrol-state-invulnerable state) 1.35d0
          (%orbit-patrol-state-x state) 450d0
          (%orbit-patrol-state-y state) 330d0
          (%orbit-patrol-state-vx state) 0d0
          (%orbit-patrol-state-vy state) 0d0)
    (when (<= (%orbit-patrol-state-lives state) 0)
      (setf (%orbit-patrol-state-lives state) 0
            (%orbit-patrol-state-status state) :lost)))
  state)

(defun %orbit-patrol-reset-state () (%orbit-patrol-new-state))

(defun %orbit-wrap (value low high)
  (let ((span (- high low)))
    (cond ((or (< value low) (>= value high)) (+ low (mod (- value low) span)))
          (t value))))

(defun %orbit-patrol-step (state seconds session &optional collision-p)
  "Advance pure gameplay state. COLLISION-P receives two kind/x/y/angle tuples."
  (when (eq (%orbit-patrol-state-status state) :playing)
    (let ((dt (max 0d0 (min 0.05d0 (coerce seconds 'double-float)))))
      (incf (%orbit-patrol-state-elapsed state) dt)
      (decf (%orbit-patrol-state-fire-cooldown state) dt)
      (decf (%orbit-patrol-state-invulnerable state) dt)
      (decf (%orbit-patrol-state-spawn-clock state) dt)
      (%orbit-patrol-steer
       state dt
       (- (if (or (%held-p session :right) (%held-p session :d)) 1 0)
          (if (or (%held-p session :left) (%held-p session :a)) 1 0))
       (or (%held-p session :up) (%held-p session :w)))
      (incf (%orbit-patrol-state-x state) (* (%orbit-patrol-state-vx state) dt))
      (incf (%orbit-patrol-state-y state) (* (%orbit-patrol-state-vy state) dt))
      (setf (%orbit-patrol-state-x state) (%orbit-wrap (%orbit-patrol-state-x state) 38d0 862d0)
            (%orbit-patrol-state-y state) (%orbit-wrap (%orbit-patrol-state-y state) 112d0 544d0))
      (when (and (%held-p session :space) (%orbit-patrol-fire state))
        (%play-tone session 720 :duration 0.055 :volume 0.12))
      (dolist (actor (%orbit-patrol-state-targets state))
        (when (eq (%orbit-actor-kind actor) :drone)
          (let* ((dx (- (%orbit-patrol-state-x state) (%orbit-actor-x actor)))
                 (dy (- (%orbit-patrol-state-y state) (%orbit-actor-y actor)))
                 (distance (max 1d0 (sqrt (+ (* dx dx) (* dy dy))))))
            (incf (%orbit-actor-vx actor) (* 18d0 (/ dx distance) dt))
            (incf (%orbit-actor-vy actor) (* 18d0 (/ dy distance) dt))))
        (incf (%orbit-actor-x actor) (* (%orbit-actor-vx actor) dt))
        (incf (%orbit-actor-y actor) (* (%orbit-actor-vy actor) dt))
        (incf (%orbit-actor-angle actor) (* (if (eq (%orbit-actor-kind actor) :asteroid) 34d0 -20d0) dt))
        (setf (%orbit-actor-x actor) (%orbit-wrap (%orbit-actor-x actor) 38d0 862d0)
              (%orbit-actor-y actor) (%orbit-wrap (%orbit-actor-y actor) 112d0 544d0)))
      (dolist (shot (%orbit-patrol-state-bullets state))
        (incf (%orbit-actor-age shot) dt)
        (incf (%orbit-actor-x shot) (* (%orbit-actor-vx shot) dt))
        (incf (%orbit-actor-y shot) (* (%orbit-actor-vy shot) dt)))
      ;; A broad circle rejects most pairs. The factory callback then checks the
      ;; cached silhouette masks, including each actor's cached rotation frame.
      (dotimes (index (%orbit-patrol-resolve-shots state collision-p))
        (declare (ignore index))
        (%play-tone session 1040 :duration 0.09 :volume 0.2))
      (when (and (eq (%orbit-patrol-state-status state) :playing)
                 (some
                  (lambda (target)
                    (let ((dx (- (%orbit-actor-x target) (%orbit-patrol-state-x state)))
                          (dy (- (%orbit-actor-y target) (%orbit-patrol-state-y state))))
                      (and (< (+ (* dx dx) (* dy dy)) 1500d0)
                           (or (null collision-p)
                               (funcall collision-p
                                        :ship (%orbit-patrol-state-x state) (%orbit-patrol-state-y state)
                                        (%orbit-patrol-state-angle state)
                                        (%orbit-actor-kind target) (%orbit-actor-x target)
                                        (%orbit-actor-y target) (%orbit-actor-angle target))))))
                  (%orbit-patrol-state-targets state)))
        (when (<= (%orbit-patrol-state-invulnerable state) 0d0)
          (%orbit-patrol-damage state)
          (%play-tone session 180 :duration 0.18 :volume 0.24)))
      ;; New threats arrive as the mission advances. Early play stays readable;
      ;; the mix alternates rocks with quicker drones that home gently on the ship.
      (when (and (eq (%orbit-patrol-state-status state) :playing)
                 (< (%orbit-patrol-state-kills state) 12)
                 (< (length (%orbit-patrol-state-targets state)) 5)
                 (<= (%orbit-patrol-state-spawn-clock state) 0d0))
        (let* ((drone (and (>= (%orbit-patrol-state-kills state) 3)
                           (zerop (mod (%orbit-patrol-state-kills state) 2))))
               (edge (if (zerop (%game-random session 2)) 38d0 862d0))
               (target-x (if (= edge 38d0) 850d0 50d0))
               (target-y (+ 130d0 (%game-random session 390))))
          (push (%make-orbit-actor :kind (if drone :drone :asteroid)
                                   :x target-x :y target-y
                                   :vx (if drone (if (< target-x 450d0) 55d0 -55d0) (if (< target-x 450d0) 42d0 -42d0))
                                   :vy (if drone 0d0 24d0)
                                   :id (incf (%orbit-patrol-state-next-id state)))
                (%orbit-patrol-state-targets state))
          (setf (%orbit-patrol-state-spawn-clock state) 1.15d0)))))
  state)

(defun %orbit-patrol-snapshot (state)
  (list :status (%orbit-patrol-state-status state)
        :score (%orbit-patrol-state-score state)
        :lives (%orbit-patrol-state-lives state)
        :kills (%orbit-patrol-state-kills state)
        :target 12
        :remaining (max 0 (- 12 (%orbit-patrol-state-kills state)))
        :elapsed (%orbit-patrol-state-elapsed state)))

(defun %orbit-art (kind)
  (ecase kind
    (:ship
     (let ((image (px.surface:make-surface '(40 44) :alpha t)))
       (px.draw:polygon image '(80 220 245) '((20 1) (37 39) (20 31) (3 39)))
       (px.draw:polygon image '(235 250 255) '((20 4) (29 31) (20 26) (11 31)))
       (px.draw:polygon image '(255 166 70) '((15 32) (20 43) (25 32))) image))
    (:asteroid
     (let ((image (px.surface:make-surface '(42 42) :alpha t)))
       (px.draw:polygon image '(132 144 165)
                        '((7 4) (27 2) (39 13) (37 29) (26 40) (10 36) (2 23)))
       (px.draw:polygon image '(175 188 205) '((10 7) (25 5) (18 14) (7 18)))
       (px.draw:circle image '(89 103 124) '(28 25) 4) image))
    (:drone
     (let ((image (px.surface:make-surface '(38 34) :alpha t)))
       (px.draw:polygon image '(245 99 103) '((19 1) (36 17) (19 33) (2 17)))
       (px.draw:polygon image '(255 189 134) '((19 5) (28 17) (19 29) (10 17)))
       (px.draw:circle image '(255 245 210) '(19 17) 3) image))
    (:bolt
     (let ((image (px.surface:make-surface '(12 12) :alpha t)))
       (px.draw:circle image '(255 220 111) '(6 6) 4)
       (px.draw:circle image '(255 255 230) '(6 6) 2) image))))

(defun %orbit-frames (source)
  (let ((images (make-array 16)) (masks (make-array 16)))
    (dotimes (index 16)
      (let ((image (px.transform:rotate source (* -22.5d0 index))))
        (setf (aref images index) image
              (aref masks index) (px.mask:from-surface image))))
    (values images masks)))

(defun %orbit-mask-collision (mask-table width-table)
  (lambda (first-kind first-x first-y first-angle second-kind second-x second-y second-angle)
    (let* ((first-index (%orbit-patrol-index first-angle))
           (second-index (%orbit-patrol-index second-angle))
           (first-mask (aref (gethash first-kind mask-table) first-index))
           (second-mask (aref (gethash second-kind mask-table) second-index))
           (first-size (aref (gethash first-kind width-table) first-index))
           (second-size (aref (gethash second-kind width-table) second-index))
           (fx (round (- first-x (/ (first first-size) 2))))
           (fy (round (- first-y (/ (second first-size) 2))))
           (sx (round (- second-x (/ (first second-size) 2))))
           (sy (round (- second-y (/ (second second-size) 2))))
           (left (max fx sx)) (top (max fy sy))
           (right (min (+ fx (first first-size)) (+ sx (first second-size))))
           (bottom (min (+ fy (second first-size)) (+ sy (second second-size)))))
      (and (< left right) (< top bottom)
           (px.mask:overlap first-mask second-mask (list (- sx fx) (- sy fy)))))))

(defun make-orbit-patrol (session)
  "Construct the Orbit Patrol callbacks and cached artwork for SESSION."
  (let* ((mask-table (make-hash-table)) (image-table (make-hash-table))
         (size-table (make-hash-table))
         ;; Decorative randomness must not change the mission's spawn sequence.
         (art-session (make-game-session :seed (session-seed session)))
         (ship-source (%orbit-art :ship)) (rock-source (%orbit-art :asteroid))
         (drone-source (%orbit-art :drone)) (bolt-image (%orbit-art :bolt))
         (bolt-mask (px.mask:from-surface bolt-image)))
    (multiple-value-bind (images masks) (%orbit-frames ship-source)
      (setf (gethash :ship image-table) images (gethash :ship mask-table) masks))
    (multiple-value-bind (images masks) (%orbit-frames rock-source)
      (setf (gethash :asteroid image-table) images (gethash :asteroid mask-table) masks))
    (multiple-value-bind (images masks) (%orbit-frames drone-source)
      (setf (gethash :drone image-table) images (gethash :drone mask-table) masks))
    (setf (gethash :bolt image-table) (vector bolt-image)
          (gethash :bolt mask-table) (vector bolt-mask))
    (dolist (kind '(:ship :asteroid :drone))
      (let ((sizes (make-array 16)))
        (dotimes (index 16)
          (setf (aref sizes index) (px.surface:size (aref (gethash kind image-table) index))))
        (setf (gethash kind size-table) sizes)))
    (setf (gethash :bolt size-table) (vector (px.surface:size bolt-image)))
    (let ((collision-p (%orbit-mask-collision mask-table size-table))
          (background (px.surface:make-surface '(900 620))))
      (px.surface:fill background '(9 16 31))
      (px.draw:rect background '(18 34 54) '(24 98 852 460))
      (dotimes (index 100)
        (let ((x (+ 30 (%game-random art-session 840)))
              (y (+ 104 (%game-random art-session 448))))
          (px.draw:circle background (if (zerop (mod index 5)) '(88 135 171) '(46 77 107))
                          (list x y) (if (zerop (mod index 5)) 2 1))))
      (labels ((draw-actor (screen kind x y angle)
                 (let* ((images (gethash kind image-table))
                        (index (if (eq kind :bolt) 0 (%orbit-patrol-index angle)))
                        (image (aref images index))
                        (size (aref (gethash kind size-table) index)))
                   (px.surface:blit screen image
                                    (list (round (- x (/ (first size) 2)))
                                          (round (- y (/ (second size) 2))))))))
        (let ((state (%orbit-patrol-new-state)))
          (make-mini-game
           :id :orbit-patrol :title "ORBIT PATROL"
           :instructions "Turn: ←/→ or A/D   Thrust: ↑/W   Fire: Space"
           :state state
           :on-event (lambda (current event game-session)
                       (declare (ignore current event game-session)))
           :on-step (lambda (current seconds game-session)
                      (%orbit-patrol-step current seconds game-session collision-p))
           :on-draw (lambda (current game-session)
                      (let ((screen (session-screen game-session)))
                        (px.surface:blit screen background '(0 0))
                        ;; Layers are deliberate: projectiles sit over the field,
                        ;; targets over shots, and the ship is always readable.
                        (dolist (shot (%orbit-patrol-state-bullets current))
                          (draw-actor screen :bolt (%orbit-actor-x shot) (%orbit-actor-y shot) 0d0))
                        (dolist (target (%orbit-patrol-state-targets current))
                          (draw-actor screen (%orbit-actor-kind target) (%orbit-actor-x target)
                                      (%orbit-actor-y target) (%orbit-actor-angle target)))
                        (unless (and (plusp (%orbit-patrol-state-invulnerable current))
                                     (oddp (floor (* 12 (%orbit-patrol-state-elapsed current)))))
                          (draw-actor screen :ship (%orbit-patrol-state-x current)
                                      (%orbit-patrol-state-y current) (%orbit-patrol-state-angle current)))
                        (%hud game-session "ORBIT PATROL" (%orbit-patrol-state-score current)
                              :subtitle (format nil "TARGET 12  ·  DESTROYED ~2,'0D"
                                                (%orbit-patrol-state-kills current))
                              :lives (%orbit-patrol-state-lives current))))
           :on-reset (lambda (game-session) (declare (ignore game-session)) (%orbit-patrol-reset-state))
           :snapshot #'%orbit-patrol-snapshot))))))
