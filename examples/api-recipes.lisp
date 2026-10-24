;;;; Short recipes for the value and event APIs. These stay ordinary functions
;;;; so callers can inspect their return values without entering an application.
(in-package #:pixelisp.examples)

(defun palette-demo ()
  "Return an owned named-color swatch image with grayscale strips and labels."
  (let ((image (px.surface:make-surface '(384 192))))
    (handler-case
        (px:with-resource (font (px.font:make-font nil 13))
          (loop for name in '("tomato" "gold" "springgreen" "deepskyblue"
                              "navy" "orchid" "lightsalmon" "gray42")
                for index from 0
                for x = (* (mod index 4) 96) for y = (* (floor index 4) 96) do
                  (px.draw:rect image name (list x y 96 96))
                  (px.draw:rect image (px.color:grayscale name) (list x (+ y 64) 96 32))
                  (px:with-resource (label (px.font:render font name t "white" "black"))
                    (px.surface:blit image label (list (+ x 3) (+ y 77)))))
          image)
      (error (condition) (px:dispose image) (error condition)))))

(defun audio-events-demo (&key (timeout-ms 2000))
  "Play two queued chimes, process their completion events, and return their count.
The timeout bounds the event loop, including when an audio backend fails to progress."
  (check-type timeout-ms (integer 1 *))
  (px:with-init (:video nil)
    (px:with-resource (sound (%make-chime))
      (let* ((channel (px.mixer:make-channel 0))
             (finished-type (px.event:custom-type))
             (deadline (+ (px.time:get-ticks) timeout-ms))
             (finished 0))
        (px.mixer:set-endevent channel finished-type)
        (px.mixer:play sound :channel channel)
        (px.mixer:queue channel sound)
        ;; Pumping delivers the notification and advances the queued sound.
        ;; No application Lisp runs on SDL's audio thread.
        (loop while (< finished 2) do
          (incf finished (length (px.event:get :types finished-type)))
          (when (>= (px.time:get-ticks) deadline)
            (error "Timed out waiting for queued sound completion events."))
          (when (< finished 2) (px.time:delay 5)))
        finished))))
