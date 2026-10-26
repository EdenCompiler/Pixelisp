;;;; Echo Grove: remember a growing melody. Timing is part of the state machine,
;;;; so cues, timeouts, and player input keep working without blocking the loop.
(in-package #:pixelisp.examples)

(defstruct (%echo-state (:constructor %make-echo-state))
  (pattern nil) (round 1) (position 0) (cue-index 0)
  (phase :lead-in) (timer 0.7d0) active (flash-time 0d0)
  (score 0) (lives 3) (status :playing) (message "Watch the lights"))

(defun %echo-new-state (session)
  (%make-echo-state :pattern (list (%game-random session 4))))

(defun %echo-note (state session pad)
  (setf (%echo-state-active state) pad (%echo-state-flash-time state) 0.3d0)
  ;; Decode each cached cue from an in-memory WAV, just like an asset bundled
  ;; inside a game archive. The note plays without creating a temporary file.
  (%play-tone session (nth pad '(262 330 392 523)) :duration 0.32 :volume 0.3 :encoded t))

(defun %echo-mistake (state session)
  (decf (%echo-state-lives state))
  (%play-tone session 130 :duration 0.24 :volume 0.22)
  (setf (%echo-state-position state) 0 (%echo-state-cue-index state) 0
        (%echo-state-active state) nil (%echo-state-phase state) :lead-in
        (%echo-state-timer state) 1.1d0
        (%echo-state-message state) "Try the same melody again")
  (when (zerop (%echo-state-lives state)) (setf (%echo-state-status state) :lost)))

(defun %echo-press (state session pad)
  "Accept a pad only during the player's turn; mistakes replay this round."
  (when (and (eq (%echo-state-status state) :playing)
             (eq (%echo-state-phase state) :input))
    (%echo-note state session pad)
    (if (/= pad (nth (%echo-state-position state) (%echo-state-pattern state)))
        (%echo-mistake state session)
        (progn
          (incf (%echo-state-score state) 25)
          (incf (%echo-state-position state))
          (setf (%echo-state-timer state) 8d0)
          (when (= (%echo-state-position state) (%echo-state-round state))
            (incf (%echo-state-score state) (* 100 (%echo-state-round state)))
            (if (= (%echo-state-round state) 6)
                (setf (%echo-state-status state) :won)
                (progn
                  (incf (%echo-state-round state))
                  (setf (%echo-state-pattern state)
                        (append (%echo-state-pattern state) (list (%game-random session 4)))
                        (%echo-state-position state) 0 (%echo-state-cue-index state) 0
                        (%echo-state-phase state) :lead-in (%echo-state-timer state) 1d0
                        (%echo-state-message state) "Good! One more note...")))))))
  state)

(defun %echo-step (state seconds session)
  (when (eq (%echo-state-status state) :playing)
    (decf (%echo-state-flash-time state) seconds)
    (when (<= (%echo-state-flash-time state) 0d0) (setf (%echo-state-active state) nil))
    (decf (%echo-state-timer state) seconds)
    (when (<= (%echo-state-timer state) 0d0)
      (ecase (%echo-state-phase state)
        ((:lead-in :gap)
         (%echo-note state session (nth (%echo-state-cue-index state) (%echo-state-pattern state)))
         (setf (%echo-state-phase state) :lit (%echo-state-timer state) 0.42d0
               (%echo-state-flash-time state) 0.42d0
               (%echo-state-message state) "Watch the lights"))
        (:lit
         (incf (%echo-state-cue-index state))
         (setf (%echo-state-active state) nil)
         (if (= (%echo-state-cue-index state) (%echo-state-round state))
             (setf (%echo-state-phase state) :input (%echo-state-timer state) 8d0
                   (%echo-state-message state) "Your turn — repeat the melody")
             (setf (%echo-state-phase state) :gap (%echo-state-timer state) 0.18d0)))
        (:input (%echo-mistake state session)))))
  state)

(defparameter +echo-pad-rects+ '((100 168 334 132) (466 168 334 132)
                                (100 326 334 132) (466 326 334 132)))

(defun %echo-event (state event session)
  (let ((pad
          (case (px.event:type event)
            (:key-down
             (unless (px.event:attribute event :repeat)
               (case (px.event:attribute event :key)
                 ((:1 :up) 0) ((:2 :right) 1) ((:3 :left) 2) ((:4 :down) 3))))
            (:mouse-button-down
             (when (eql 1 (px.event:attribute event :button))
               (let ((pos (px.event:attribute event :pos)))
                 (when pos
                   (position-if (lambda (rect) (px.rect:collide-point (apply #'px:make-rect rect) pos))
                                +echo-pad-rects+))))))))
    (when pad (%echo-press state session pad)))
  state)

(defun %echo-snapshot (state)
  (list :status (%echo-state-status state) :score (%echo-state-score state)
        :lives (%echo-state-lives state) :round (%echo-state-round state)
        :phase (%echo-state-phase state) :position (%echo-state-position state)
        :pattern (copy-list (%echo-state-pattern state))))

(defun %echo-pad-image (color lit)
  (let ((image (px.surface:make-surface '(334 132))))
    (px.surface:fill image (if lit color (mapcar (lambda (c) (round (* c 0.32))) color)))
    (px.surface:fill image (if lit '(245 250 255) color) '(0 0 334 5))
    (px.surface:fill image '(8 17 30) '(0 124 334 8))
    image))

(defun %echo-pad-atlas (colors)
  "Pack dim/lit frames into one sheet: columns select pads, rows select light."
  (let ((sheet (px.surface:make-surface '(1336 264))))
    (loop for color in colors for column from 0 do
      (loop for lit in '(nil t) for row from 0 do
        (px:with-resource (frame (%echo-pad-image color lit))
          (px.surface:blit sheet frame (list (* column 334) (* row 132))))))
    sheet))

(defun make-echo-grove (session)
  "Build four pad sprites; source rectangles select their current atlas frame."
  (let* ((colors '((67 184 248) (76 219 163) (255 146 99) (182 138 255)))
         (atlas (%echo-pad-atlas colors))
         (pads (loop for rect in +echo-pad-rects+ for column from 0
                     collect (px.sprite:make-sprite
                              :image atlas :rect (apply #'px:make-rect rect)
                              :source-rect (list (* column 334) 0 334 132))))
         (group (apply #'px.sprite:make-ordered-group pads)))
    (make-mini-game
     :id :echo-grove :title "ECHO GROVE"
     :instructions "1–4 / arrow keys / click pads · Repeat six melodies"
     :state (%echo-new-state session) :on-event #'%echo-event :on-step #'%echo-step
     :on-reset #'%echo-new-state :snapshot #'%echo-snapshot
     :on-draw
     (lambda (state current-session)
       (px.surface:fill (session-screen current-session) '(11 22 34))
       (%hud current-session "ECHO GROVE" (%echo-state-score state)
             :subtitle (format nil "Round ~D / 6 · Remember the growing melody" (%echo-state-round state))
             :lives (%echo-state-lives state))
       (%text current-session (%echo-state-message state) 450 121 :anchor :center
              :size 21 :color '(216 232 243))
       ;; The cue changes the sampled atlas row; all pads keep the same image.
       ;; Screen rectangles stay independent of the source-image coordinates.
       (loop for pad in pads for column from 0
             do (setf (px.sprite:source-rect pad)
                      (list (* column 334) (if (eql column (%echo-state-active state)) 132 0)
                            334 132)))
       (px.sprite:draw group (session-screen current-session))
       (loop for rect in +echo-pad-rects+ for label in '("1 / ↑" "2 / →" "3 / ←" "4 / ↓")
             do (%text current-session label (+ (first rect) 167) (+ (second rect) 64)
                       :anchor :center :size 33))
       (%text current-session
              (if (eq :input (%echo-state-phase state))
                  (format nil "~D / ~D notes   ·   ~D seconds" (%echo-state-position state)
                          (%echo-state-round state) (max 0 (ceiling (%echo-state-timer state))))
                  "Watch now. Play when it says YOUR TURN.")
              450 501 :anchor :center :size 18 :color '(141 175 202))))))
