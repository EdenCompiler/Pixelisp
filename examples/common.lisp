;;;; Shared support for the mini-games. Each game keeps its rules in ordinary
;;;; Lisp state; this file handles the window, input, text, audio, and cleanup.
(defpackage #:pixelisp.examples
  (:use #:cl) (:nicknames #:px.examples)
  (:export #:list-examples #:run-example #:play))
(in-package #:pixelisp.examples)

(defstruct (game-session (:conc-name session-))
  screen (width 900) (height 620) (elapsed 0d0) (seed 1)
  (backend :surface) window renderer texture frame-image (fullscreen nil)
  held-keys (mouse-pos (list 450 310)) (audio-enabled nil)
  (fonts (make-hash-table)) (labels (make-hash-table :test #'equal))
  (tones (make-hash-table :test #'equal)))

(defstruct mini-game
  "A game owns mutable Lisp STATE and callbacks over it. ON-EVENT, ON-STEP,
and ON-DRAW receive that state and the session; ON-RESET returns fresh state.
SNAPSHOT returns ordinary values that remain usable after native cleanup."
  id title instructions state on-event on-step on-draw on-reset snapshot)

(defun %held-p (session key)
  (not (null (member key (session-held-keys session)))))

(defun %game-random (session limit)
  "Small repeatable generator, independent of the host Lisp's random state."
  (check-type limit (integer 1 *))
  (setf (session-seed session)
        (mod (+ (* 1664525 (session-seed session)) 1013904223) (expt 2 32)))
  (mod (ash (session-seed session) -8) limit))

(defun %random-choice (session sequence)
  (elt sequence (%game-random session (length sequence))))

(defun %text (session string x y &key (size 18) (color '(225 235 250))
                                    (anchor :top-left))
  "Render a cached label. The bounded cache also handles changing scores."
  (let* ((labels (session-labels session))
         (key (list string size color))
         (image (gethash key labels)))
    (unless image
      (when (>= (hash-table-count labels) 256)
        (maphash (lambda (key surface) (declare (ignore key)) (px:dispose surface)) labels)
        (clrhash labels))
      (let ((font (or (gethash size (session-fonts session))
                      (setf (gethash size (session-fonts session))
                            (px.font:make-font nil size)))))
        (setf image (px.font:render font string t color)
              (gethash key labels) image)))
    (px.surface:blit (session-screen session) image
                     (px.surface:get-rect image anchor (list (round x) (round y))))))

(defun %panel (session rectangle color &key border-color)
  "Use native fills for large panels; rasterize small reusable art just once."
  (let* ((screen (session-screen session)) (rect (apply #'px:make-rect rectangle))
         (x (px.rect:x rect)) (y (px.rect:y rect))
         (w (px.rect:width rect)) (h (px.rect:height rect)))
    (px.surface:fill screen color rect)
    (when border-color
      (dolist (edge (list (list x y w 1) (list x (+ y h -1) w 1)
                          (list x y 1 h) (list (+ x w -1) y 1 h)))
        (px.surface:fill screen border-color edge)))))

(defun %hud (session title score &key (subtitle "") lives)
  (%panel session '(0 0 900 84) '(10 17 30))
  (%text session title 26 13 :size 27 :color '(240 248 255))
  (%text session subtitle 28 51 :size 17 :color '(141 175 202))
  (%text session (format nil "~6,'0D" score) 874 14 :size 28 :anchor :top-right
         :color '(255 216 126))
  (when lives
    (%text session (format nil "~D lives" lives) 872 52 :size 16 :anchor :top-right)))

(defun %circle-image (radius color)
  (let ((image (px.surface:make-surface (list (+ 2 (* 2 radius)) (+ 2 (* 2 radius))) :alpha t)))
    (px.surface:fill image '(0 0 0 0))
    (px.draw:circle image color (list (1+ radius) (1+ radius)) radius)
    image))

(defun %tone-samples (frequency duration volume)
  "Create mono signed 16-bit samples with a short envelope to prevent clicks."
  (let* ((count (max 1 (round (* 22050 duration))))
         (samples (make-array count :element-type '(signed-byte 16))))
    (dotimes (i count samples)
      (let ((envelope (min 1d0 (/ i 160d0) (/ (- count i 1) 300d0))))
        (setf (aref samples i)
              (round (* 24000 volume envelope
                        (sin (* 2 pi frequency (/ i 22050d0))))))))))

(defun %tone-wave (samples)
  "Package mono PCM as a WAV asset, without writing an intermediate file."
  (let* ((data-size (* 2 (length samples)))
         (bytes (make-array (+ 44 data-size) :element-type '(unsigned-byte 8)
                                               :initial-element 0)))
    ;; WAV headers use little-endian integers, regardless of the host byte order.
    (labels ((integer-at (offset value size)
               (dotimes (i size)
                 (setf (aref bytes (+ offset i)) (ldb (byte 8 (* i 8)) value))))
             (tag-at (offset tag)
               (loop for character across tag for i from offset
                     do (setf (aref bytes i) (char-code character)))))
      (tag-at 0 "RIFF") (integer-at 4 (+ 36 data-size) 4) (tag-at 8 "WAVE")
      (tag-at 12 "fmt ") (integer-at 16 16 4) (integer-at 20 1 2)
      (integer-at 22 1 2) (integer-at 24 22050 4) (integer-at 28 44100 4)
      (integer-at 32 2 2) (integer-at 34 16 2)
      (tag-at 36 "data") (integer-at 40 data-size 4)
      (loop for sample across samples for offset from 44 by 2
            do (integer-at offset sample 2)))
    bytes))

(defun %play-tone (session frequency &key (duration 0.12) (volume 0.25) encoded)
  "Cache each note; ENCODED exercises the same decoder used for packed WAV assets."
  (when (session-audio-enabled session)
    (let* ((key (list frequency duration volume encoded))
           (sound (or (gethash key (session-tones session))
                      (setf (gethash key (session-tones session))
                            (let ((samples (%tone-samples frequency duration volume)))
                              (if encoded
                                  (px.mixer:make-sound nil :file (%tone-wave samples))
                                  (px.sndarray:make-sound samples)))))))
      (px.mixer:play sound))))

(defun %track-input (session event)
  (case (px.event:type event)
    (:key-down (pushnew (px.event:attribute event :key) (session-held-keys session)))
    (:key-up (setf (session-held-keys session)
                   (remove (px.event:attribute event :key) (session-held-keys session))))
    ((:mouse-motion :mouse-button-down :mouse-button-up)
     (let ((pos (px.event:attribute event :pos)))
       (when pos (setf (session-mouse-pos session) (coerce pos 'list)))))
    (:window-event
     ;; Losing focus must not leave a thrust or movement key stuck down.
     (when (eql 13 (px.event:attribute event :event))
       (setf (session-held-keys session) nil)))))

(defun %game-playing-p (game)
  (eq :playing (getf (funcall (mini-game-snapshot game) (mini-game-state game)) :status)))

(defun %open-game-session (backend seed)
  "Keep the same CPU game canvas for either presentation backend."
  (if (eq backend :surface)
      (make-game-session :seed seed
                        :screen (px.display:set-mode '(900 620) :title "Pixelisp mini-games"))
      ;; SDL forbids using a window surface and renderer on the same window.
      ;; This independent window owns the renderer and its streaming texture.
      (let* ((window (px.sdl2.video:make-window :size '(900 620) :resizable t))
             (renderer (handler-case (px.sdl2.video:make-renderer window :accelerated t)
                         (px:error () (px.sdl2.video:make-renderer window))))
             (texture (px.sdl2.video:make-texture renderer '(900 620) :access :streaming)))
        (setf (px.sdl2.video:logical-size renderer) '(900 620)
              (px.sdl2.video:texture-blend-mode texture) :none)
        (make-game-session :seed seed :backend backend :window window
                           :renderer renderer :texture texture :frame-image (px.sdl2.video:make-image texture)
                           :screen (px.surface:make-surface '(900 620))))))

(defun %toggle-game-fullscreen (session)
  "Keep fullscreen requests on the video thread for either window backend."
  (setf (session-fullscreen session)
        (if (session-window session)
            (let ((window (session-window session)))
              (if (px.sdl2.video:window-fullscreen-mode window)
                  (progn (px.sdl2.video:set-windowed window) nil)
                  (progn (px.sdl2.video:set-fullscreen window :desktop t) t)))
            (px.display:toggle-fullscreen))))

(defun %present-game (session screenshot)
  "Upload the finished frame, capturing renderer pixels before presenting."
  (let ((renderer (session-renderer session)) (screen (session-screen session)))
    (if renderer
        (progn
          (px.sdl2.video:update-texture (session-texture session) screen)
          (px.sdl2.video:clear renderer '(0 0 0))
          (px.sdl2.video:blit renderer (session-frame-image session) '(0 0 900 620))
          ;; SDL does not promise the backbuffer survives PRESENT. Read it now.
          (when screenshot
            (px:with-resource (capture (px.sdl2.video:to-surface renderer))
              (px.image:save capture screenshot)))
          (px.sdl2.video:present renderer))
        (progn
          (when screenshot (px.image:save screen screenshot))
          (px.display:flip)))))

(defun %draw-game-frame (game session paused &optional screenshot)
  (let* ((state (mini-game-state game))
         (snapshot (funcall (mini-game-snapshot game) state))
         (status (getf snapshot :status)))
    (funcall (mini-game-on-draw game) state session)
    (%panel session '(0 574 900 46) '(10 17 30))
    (%text session (mini-game-instructions game) 26 580 :size 15)
    (%text session "P pause   R restart   F11 fullscreen   Esc quit" 874 602 :anchor :top-right
           :size 12 :color '(141 175 202))
    (when (or paused (member status '(:won :lost)))
      (%panel session '(225 238 450 150) '(15 25 45) :border-color '(100 165 205))
      (%text session (cond (paused "PAUSED") ((eq status :won) "MISSION COMPLETE")
                           (t "TRY AGAIN")) 450 276 :anchor :center :size 30)
      (%text session (if paused "Press P to resume" "Press R for a fresh run")
             450 330 :anchor :center :size 18 :color '(255 216 126)))
    (%present-game session screenshot)))

(defun %run-mini-game (factory &key frames (fps 60) (audio t) (seed 1) fixed-dt screenshot
                                  (backend :surface))
  "Run a real event/update/draw loop and return its final, native-free snapshot.
FRAMES and FIXED-DT make the same gameplay loop usable in bounded tests."
  (when frames (check-type frames (integer 0 *)))
  (check-type fps (real 0 *))
  (check-type seed (integer 0 *))
  (check-type backend (member :surface :renderer))
  (when fixed-dt (check-type fixed-dt (real (0) 0.05)))
  (px:with-init ()
    (let* ((session (%open-game-session backend seed))
           (game (funcall factory session))
           (clock (px.time:make-clock))
           (paused nil) (running t) (frame 0))
      (let ((title (format nil "Pixelisp · ~A" (mini-game-title game))))
        (if (session-window session)
            (setf (px.sdl2.video:title (session-window session)) title)
            (px.display:set-caption title)))
      (when audio
        (handler-case
            (progn
              (px.mixer:init :frequency 22050 :size -16 :channels 1 :buffer 256)
              (setf (session-audio-enabled session) t))
          (error (condition)
            (format *error-output* "Audio unavailable; visual play continues: ~A~%" condition))))
      ;; Draw even a zero-frame run, so screenshots never capture uninitialized art.
      (%draw-game-frame game session paused)
      (loop while (and running (or (null frames) (< frame frames))) do
        (let ((dt (or fixed-dt (min 0.05d0 (/ (px.time:tick clock fps) 1000d0)))))
          ;; Fixed simulations still honor the requested presentation cap.
          (when fixed-dt (px.time:tick clock fps))
          (dolist (event (px.event:get))
            (%track-input session event)
            (let ((key (and (eq :key-down (px.event:type event))
                            (not (px.event:attribute event :repeat))
                            (px.event:attribute event :key))))
              (cond
                ((or (eq :quit (px.event:type event)) (eq key :escape)) (setf running nil))
                ((eq key :p) (setf paused (not paused)))
                ((eq key :f11) (%toggle-game-fullscreen session))
                ((eq key :r)
                 (setf paused nil (session-elapsed session) 0d0
                       (session-held-keys session) nil (session-seed session) seed
                       (mini-game-state game) (funcall (mini-game-on-reset game) session)))
                ((and running (not paused) (%game-playing-p game))
                 (funcall (mini-game-on-event game) (mini-game-state game) event session)))))
          (when (and running (not paused) (%game-playing-p game))
            (incf (session-elapsed session) dt)
            (funcall (mini-game-on-step game) (mini-game-state game) dt session))
          (%draw-game-frame game session paused)
          (incf frame)))
      (when screenshot (%draw-game-frame game session paused screenshot))
      ;; The snapshot contains ordinary values; WITH-INIT then releases all art,
      ;; fonts, sounds, and the display, including when a callback signals an error.
      (append (funcall (mini-game-snapshot game) (mini-game-state game))
              (list :game (mini-game-id game) :frames frame :paused paused
                    :audio (session-audio-enabled session) :backend backend
                    :fullscreen (session-fullscreen session))))))
