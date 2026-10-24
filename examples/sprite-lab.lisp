;;;; A compact sprite sandbox. Run (px.examples:sprite-lab) from the REPL.
;;;; Move the player with arrows or WASD, click to launch a particle, and press
;;;; Escape or close the window to quit. All pictures are drawn in Lisp.
(in-package #:pixelisp.examples)

(defclass %sprite-lab-particle (px.sprite:sprite)
  ((vx :initarg :vx :reader %sprite-lab-particle-vx)
   (vy :initarg :vy :reader %sprite-lab-particle-vy)
   (age :initform 0 :accessor %sprite-lab-particle-age)))

(defmethod px.sprite:update ((particle %sprite-lab-particle) &rest arguments)
  ;; UPDATE's generic keeps optional game-specific arguments in &REST. This
  ;; particle expects exactly one elapsed-seconds value from its group update.
  (destructuring-bind (seconds) arguments
    (incf (%sprite-lab-particle-age particle) seconds)
    (let ((rect (px.sprite:rect particle)))
      (px.rect:move-ip rect (* (%sprite-lab-particle-vx particle) seconds)
                            (* (%sprite-lab-particle-vy particle) seconds))))
  particle)

(defun %sprite-lab-image (color radius)
  "Create a soft-edged circular sprite image with no external art asset."
  (let* ((diameter (* 2 radius))
         (image (px.surface:make-surface (list diameter diameter) :alpha t)))
    (px.draw:circle image color (list radius radius) radius)
    image))

(defun sprite-lab (&key frames (fps 60))
  "Open a small interactive sprite lab and return the number of launched particles.
FRAMES=N bounds the run for automated use; NIL runs until the user quits."
  (when (and frames (or (not (integerp frames)) (minusp frames)))
    (error "FRAMES must be NIL or a non-negative integer."))
  (check-type fps (integer 1 *))
  (px:with-init ()
    (let* ((screen (px.display:set-mode '(720 480) :title "Pixelisp — Sprite Lab"))
           (clock (px.time:make-clock))
           (font (px.font:make-font nil 18))
           (player (px:make-sprite :image (%sprite-lab-image '(100 205 255) 17)))
           ;; Every particle can share this immutable image, so particle count
           ;; does not create a matching number of native image surfaces.
           (particle-image (%sprite-lab-image '(255 150 80 210) 7))
           ;; GroupSingle demonstrates that a player can be replaced in place
           ;; while ordinary groups keep as many short-lived particles as needed.
           (player-group (px.sprite:make-group-single player))
           (particles (px.sprite:make-group))
           (instructions (px.font:render font "Arrows / WASD move · Click launches · Escape quits" t '(205 220 235)))
           (running t)
           (launched 0))
      (setf (px.rect:center (px.sprite:rect player)) '(360 260))
      (px.surface:fill screen '(14 21 34))
      (loop for frame from 0
            while (and running (or (null frames) (< frame frames)))
            for seconds = (/ (px.time:tick clock fps) 1000.0)
            do
               ;; Keep the familiar pygame sequence: events, update, draw, present.
               (dolist (event (px.event:get))
                 (case (px.event:type event)
                   (:quit (setf running nil))
                   (:key-down
                    (when (eq (px.event:attribute event :key) :escape)
                      (setf running nil)))
                   (:mouse-button-down
                    (let* ((center (px.rect:center (px.sprite:rect player)))
                           (dx (- (first (px.event:attribute event :pos)) (first center)))
                           (dy (- (second (px.event:attribute event :pos)) (second center)))
                           ;; Scale the launch vector to a steady speed and avoid
                           ;; division by zero when clicking the player itself.
                           (length (max 1 (px.math:length (list dx dy))))
                           (particle (make-instance '%sprite-lab-particle
                                                    :image particle-image
                                                    :rect (px:make-rect (- (first center) 7) (- (second center) 7) 14 14)
                                                    :vx (* 220 (/ dx length))
                                                    :vy (* 220 (/ dy length))
                                                    :blend-flags :blend-rgb-add)))
                      (px.sprite:add particles particle)
                      (incf launched)))))
               (let* ((dx (- (if (or (px.key:pressed-p :right) (px.key:pressed-p :d)) 1 0)
                             (if (or (px.key:pressed-p :left) (px.key:pressed-p :a)) 1 0)))
                      (dy (- (if (or (px.key:pressed-p :down) (px.key:pressed-p :s)) 1 0)
                             (if (or (px.key:pressed-p :up) (px.key:pressed-p :w)) 1 0)))
                      (rect (px.sprite:rect player)))
                 (px.rect:move-ip rect (* dx 240 seconds) (* dy 240 seconds))
                 (setf (px.sprite:rect player) (px.rect:clamp rect (px:make-rect 8 8 704 464))))
               (px.sprite:update particles seconds)
               ;; Remove particles after a short lifetime or once they leave view.
               (dolist (particle (px.sprite:sprites particles))
                 (when (or (> (%sprite-lab-particle-age particle) 2.5)
                           (not (px.rect:collide-point (px:make-rect 0 0 720 480)
                                                      (px.rect:center (px.sprite:rect particle)))))
                   (px.sprite:kill particle)))
               (px.surface:fill screen '(14 21 34))
               (px.draw:rect screen '(27 41 61) '(8 8 704 464) :width 1)
               (px.surface:blit screen instructions '(18 18))
               (px.sprite:draw particles screen)
               (px.sprite:draw player-group screen)
               (px.display:flip))
      ;; The example owns the shared generated art and releases it once.
      (px.sprite:empty particles)
      (px:dispose particle-image)
      launched)))
