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

(defun %echo-pad-sprites (atlas)
  "Keep reusable pad art in sprites whose reverse group links are weak."
  (loop for rect in +echo-pad-rects+ for column from 0
        collect (px.sprite:make-weak-sprite
                 :image atlas :rect (apply #'px:make-rect rect)
                 :source-rect (list (* column 334) 0 334 132))))

(defun %echo-pad-group (pads)
  "Build the ordered display group for the current Echo Grove scene."
  (apply #'px.sprite:make-ordered-group pads))

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

(defun %echo-afterglow-colors (colors dim-colors)
  "Blend lit and dim cues once, then reuse the colors in the indexed atlas."
  (px.surface:with-surface (lit '(4 1))
    (px.surface:with-surface (dim '(4 1))
      (loop for color in colors for dim-color in dim-colors for x from 0 do
        (px.surface:set-at lit (list x 0) color)
        (px.surface:set-at dim (list x 0) dim-color))
      (px:with-resource (mean (px.transform:average-surfaces (list lit dim)))
        (loop for x below 4 collect
          (px.color:to-list (px.surface:get-at mean (list x 0))))))))

(defun %echo-pad-row (state column)
  "Let the final part of a cue fade before the next note or player input."
  (cond ((not (eql column (%echo-state-active state))) 0)
        ((< 0d0 (%echo-state-flash-time state) 0.14d0) 2)
        (t 1)))

(defun %echo-pad-atlas (colors)
  "Pack dim, lit and afterglow frames into one editable indexed sheet."
  (let* ((dim-colors (mapcar (lambda (color)
                              (mapcar (lambda (c) (round (* c 0.32))) color)) colors))
         (afterglow (%echo-afterglow-colors colors dim-colors))
         (sheet (px.surface:make-surface '(1336 396) :depth 8)))
    ;; Each frame stores palette indices. Entry 8 changes every lit pad's
    ;; warning highlight; entries 10..13 hold the averaged afterglow colors.
    (px.surface:set-palette sheet
      (append dim-colors colors '((245 250 255) (8 17 30)) afterglow))
    (loop for column below 4 do
      (loop for mode in '(:dim :lit :afterglow) for row from 0 do
        (let ((x (* column 334)) (y (* row 132)))
          ;; Exact indices keep warnings separate even in duplicate-color themes.
          (px.surface:fill sheet
                           (+ column (ecase mode (:dim 0) (:lit 4) (:afterglow 10)))
                           (list x y 334 132))
          (px.draw:rect sheet (if (eq mode :lit) 8 (+ column 4)) (list x y 334 5))
          (px.draw:rect sheet 9 (list x (+ y 124) 334 8)))))
    sheet))

(defun make-echo-grove (session)
  "Build four pad sprites; source rectangles select their current atlas frame."
  (let* ((colors '((67 184 248) (76 219 163) (255 146 99) (182 138 255)))
         (atlas (%echo-pad-atlas colors))
         (pads (%echo-pad-sprites atlas))
         (group (%echo-pad-group pads)))
    (make-mini-game
     :id :echo-grove :title "ECHO GROVE"
     :instructions "1–4 / arrow keys / click pads · Repeat six melodies"
     :state (%echo-new-state session) :on-event #'%echo-event :on-step #'%echo-step
     ;; Keep reusable pads and their atlas across restarts, but let the old
     ;; scene group go. Weak reverse membership means pads do not retain it.
     :on-reset (lambda (current-session)
                 (setf group (%echo-pad-group pads))
                 (%echo-new-state current-session))
     :snapshot #'%echo-snapshot
     :on-draw
     (lambda (state current-session)
       (px.surface:fill (session-screen current-session) '(11 22 34))
       (%hud current-session "ECHO GROVE" (%echo-state-score state)
             :subtitle (format nil "Round ~D / 6 · Remember the growing melody" (%echo-state-round state))
             :lives (%echo-state-lives state))
       (%text current-session (%echo-state-message state) 450 121 :anchor :center
              :size 21 :color '(216 232 243))
       ;; A warm highlight warns that only one mistake life remains. Restore
       ;; the normal palette on restart without rebuilding any sprite pixels.
       (px.surface:set-palette-at atlas 8
         (if (= (%echo-state-lives state) 1) '(255 90 60) '(245 250 255)))
       ;; The cue changes the sampled atlas row; all pads keep the same image.
       ;; Screen rectangles stay independent of the source-image coordinates.
       (loop for pad in pads for column from 0
             do (setf (px.sprite:source-rect pad)
                      (list (* column 334) (* 132 (%echo-pad-row state column))
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
