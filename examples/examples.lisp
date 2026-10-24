;;;; Small examples intended to be read, edited, and run from the REPL.
;;;; All art and sound below are generated in Lisp. The bundled font is the only
;;;; external asset. FRAMES lets automation exercise the same loop and exit.
(defpackage #:pixelisp.examples
  (:use #:cl) (:nicknames #:px.examples)
  (:export #:play #:pixel-demo #:sound-demo #:mask-demo #:effects-demo
           #:sprite-lab #:mask-lab #:image-lab #:run-example #:list-examples
           #:palette-demo #:audio-events-demo #:ui-demo #:ui-lab
           #:pixel-match-demo #:pixel-lab #:image-memory-demo #:display-report))
(in-package #:pixelisp.examples)

(defun %make-chime ()
  "Generate a short, fading sine wave in the mixer's mono signed-16 format."
  (px.mixer:init :frequency 22050 :size -16 :channels 1)
  (let* ((count 3307)
         (samples (make-array count :element-type '(signed-byte 16))))
    (dotimes (index count)
      (let ((envelope (- 1.0 (/ index count))))
        (setf (aref samples index)
              (round (* 6500 envelope (sin (* 2 pi 880 (/ index 22050.0))))))))
    (px.sndarray:make-sound samples)))

(defun %player-image ()
  (let ((image (px.surface:make-surface '(30 30) :alpha t)))
    (px.draw:circle image '(70 195 225) '(15 15) 14)
    (px.draw:circle image '(190 245 255) '(11 10) 4)
    (px.draw:circle image '(20 60 85) '(20 16) 2)
    image))

(defun %star-image ()
  (let ((image (px.surface:make-surface '(28 28) :alpha t)))
    (px.draw:polygon image '(255 205 80)
                     '((14 1) (18 9) (27 10) (20 17) (22 27)
                       (14 22) (6 27) (8 17) (1 10) (10 9)))
    image))

(defun %move-player (player seconds)
  (let* ((horizontal (- (if (or (px.key:pressed-p :right) (px.key:pressed-p :d)) 1 0)
                        (if (or (px.key:pressed-p :left) (px.key:pressed-p :a)) 1 0)))
         (vertical (- (if (or (px.key:pressed-p :down) (px.key:pressed-p :s)) 1 0)
                      (if (or (px.key:pressed-p :up) (px.key:pressed-p :w)) 1 0)))
         (distance (* 250 seconds))
         (rect (px.sprite:rect player)))
    (px.rect:move-ip rect (* horizontal distance) (* vertical distance))
    (setf (px.sprite:rect player) (px.rect:clamp rect (px:make-rect 10 80 620 370)))))

(defun play (&key frames (audio t))
  "Play Star Collector. Move with arrows/WASD; Escape or closing the window exits.
FRAMES bounds the loop for a smoke test. AUDIO=NIL avoids opening an audio device."
  (px:with-init ()
    (let* ((screen (px.display:set-mode '(640 480) :title "Pixelisp — Star Collector" :resizable t))
           (clock (px.time:make-clock))
           (font (px.font:make-font nil 22))
           (hero (px:make-sprite :image (%player-image)))
           (star-original (%star-image))
           (star (px:make-sprite :image (px.surface:copy star-original)))
           (actors (px:make-group hero star))
           (background (px.surface:make-surface '(640 480)))
           (instructions (px.font:render font "Arrows / WASD to move · Escape to quit" t '(165 185 205)))
           (chime (when audio
                    (handler-case (%make-chime)
                      (px:error (condition)
                        (format *error-output* "Audio unavailable: ~A~%" condition)
                        nil))))
           (score 0)
           (score-image nil)
           (running t))
      (setf (px.rect:center (px.sprite:rect hero)) '(320 280)
            (px.rect:center (px.sprite:rect star)) '(160 180)
            (px.sprite:mask hero) (px.mask:from-surface (px.sprite:image hero)))
      ;; Cache static art once. Each frame then uses a fast native blit instead
      ;; of rasterizing the same large rounded rectangle pixel by pixel.
      (px.surface:fill background '(15 23 37))
      (px.draw:rect background '(24 36 54) '(10 80 620 370) :border-radius 16)
      (px.surface:blit background instructions '(22 47))
      (loop for frame from 0
            while (and running (or (null frames) (< frame frames)))
            for seconds = (/ (px.time:tick clock 60) 1000.0)
            do
               ;; Explicit pygame-style loop: events, update, draw, present.
               (dolist (event (px.event:get))
                 (when (or (eq (px.event:type event) :quit)
                           (and (eq (px.event:type event) :key-down)
                                (eq (px.event:attribute event :key) :escape)))
                   (setf running nil)))
               (%move-player hero seconds)
               ;; Always transform the original image; repeated resampling of a
               ;; previous frame would gradually lose pixel detail.
               (let ((center (px.rect:center (px.sprite:rect star))))
                 (px:dispose (px.sprite:image star))
                 (setf (px.sprite:image star) (px.transform:rotate star-original (* frame 2))
                       (px.sprite:rect star) (px.surface:get-rect (px.sprite:image star) :center center)
                       (px.sprite:mask star) (px.mask:from-surface (px.sprite:image star))))
               (when (and (px.sprite:collide-rect hero star) (px.sprite:collide-mask hero star))
                 (incf score)
                 (when chime (px.mixer:play chime))
                 (setf (px.rect:center (px.sprite:rect star))
                       (list (+ 35 (random 570)) (+ 110 (random 320))))
                 (when score-image (px:dispose score-image) (setf score-image nil)))
               (unless score-image
                 (setf score-image (px.font:render font (format nil "Star Collector    Score: ~D" score)
                                                    t '(235 240 250))))
               (px.surface:blit screen background '(0 0))
               (px.surface:blit screen score-image '(22 16))
               (px.sprite:draw actors screen)
               (px.display:flip))
      score)))

(defun pixel-demo ()
  "Return a generated gradient surface; the caller owns and must dispose it."
  (let ((surface (px.surface:make-surface '(128 128))))
    (px.buffer:with-view (pixels (px.surfarray:pixels3d surface))
      (dotimes (x 128)
        (dotimes (y 128)
          (setf (px.buffer:view-ref pixels x y 0) (* x 2)
                (px.buffer:view-ref pixels x y 1) (* y 2)
                (px.buffer:view-ref pixels x y 2) 100))))
    surface))

(defun sound-demo ()
  "Play a generated chime and release its samples after playback."
  (px:with-init (:video nil)
    (let ((sound (%make-chime)))
      (px.mixer:play sound)
      (px.time:delay 180))))

(defun effects-demo ()
  "Return an owned four-panel image: alpha, additive, tinted, and premultiplied.
No window is opened. Save the returned surface or blit it into your own loop."
  (let ((canvas (px.surface:make-surface '(512 144))))
    (handler-case
        (px.surface:with-surface (art '(64 48) :alpha t)
          (px.surface:fill canvas '(25 35 50))
          ;; HSV makes it easy to choose a hue without calculating RGB channels.
          (let ((color (px:make-color 0 0 0)))
            (setf (px.color:hsva color) '(195 75 95 75))
            (px.draw:circle art color '(32 24) 22)
            (px.draw:circle art '(240 250 255 210) '(25 17) 8))
          (let ((fitted (px.rect:fit (px.surface:get-rect art) (px:make-rect 8 8 112 128))))
            (px:with-resource (image (px.transform:smoothscale art (px.rect:size fitted)))
              (px.surface:blit canvas image (px.rect:top-left fitted))
              (px.surface:blit canvas image (px.rect:top-left (px.rect:move fitted 128 0))
                               :special-flags :blend-rgb-add)
              (px:with-resource (tinted (px.surface:copy image))
                (px.surface:fill tinted '(255 110 160) nil :special-flags :blend-rgb-mult)
                (px.surface:blit canvas tinted (px.rect:top-left (px.rect:move fitted 256 0))))
              (px:with-resource (premultiplied (px.surface:premul-alpha image))
                (px.surface:blit canvas premultiplied (px.rect:top-left (px.rect:move fitted 384 0))
                                 :special-flags :blend-premultiplied))))
          canvas)
      (error (condition) (px:dispose canvas) (error condition)))))

(defun mask-demo ()
  "Return the overlap coordinate and area of two generated collision masks."
  (let ((first (px.mask:make-mask '(8 8) :fill t))
        (second (px.mask:make-mask '(4 4) :fill t)))
    (values (px.mask:overlap first second '(6 6))
            (px.mask:overlap-area first second '(6 6)))))
