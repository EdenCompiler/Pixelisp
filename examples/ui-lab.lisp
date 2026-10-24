;;;; A UI-shaped example of Color arithmetic and independently rounded corners.
;;;; Static cards are rendered once; the loop only redraws text when it changes.
(in-package #:pixelisp.examples)

(defun %ui-label (target font text position &optional (color "gainsboro"))
  "Render one label, blit it, and immediately release its temporary surface."
  (px:with-resource (label (px.font:render font text t color))
    (px.surface:blit target label position)))

(defun ui-demo ()
  "Return an owned 720x360 card showing Color operations and corner styles."
  (let ((image (px.surface:make-surface '(720 360)))
        (base (px:make-color "steelblue")))
    (handler-case
        (px:with-resource (font (px.font:make-font nil 16))
          (let ((inverse (px.color:invert base))
                (neutral (px.color:parse base)))
            ;; Color arithmetic includes alpha. Make the inverse opaque for
            ;; this UI, and remove chroma through I1I2I3 without changing alpha.
            (setf (px.color:a inverse) 255
                  (px.color:i1i2i3 neutral) (list (first (px.color:i1i2i3 base)) 0 0))
            (px.surface:fill image '(16 23 36))
            (%ui-label image font "Color arithmetic + independent rectangle corners" '(24 20) "white")
            (loop for (title color style) in
                    (list
                     (list "Original / pill" base '(:border-radius 24))
                     (list "Add / square corner" (px.color:add base '(36 36 36 0))
                           '(:border-radius 24 :border-top-left-radius 0))
                     (list "Subtract / tab" (px.color:subtract base '(35 35 35 0))
                           '(:border-radius 24 :border-bottom-left-radius 0 :border-bottom-right-radius 0))
                     (list "Invert / one corner" inverse
                           '(:border-top-left-radius 48))
                     (list "Multiply / outline" (px.color:multiply base '(2 1 1 1))
                           '(:width 3 :border-radius 14))
                     (list "I1I2I3 / fitted radii" neutral '(:border-radius 150)))
                  for index from 0
                  for x = (+ 20 (* (mod index 3) 235))
                  for y = (+ 70 (* (floor index 3) 140)) do
                    (px.draw:rect image '(29 40 57) (list x y 220 120) :border-radius 12)
                    (%ui-label image font title (list (+ x 10) (+ y 12)))
                    (apply #'px.draw:rect image color (list (+ x 20) (+ y 48) 180 56) style)))
          image)
      (error (condition) (px:dispose image) (error condition)))))

(defun ui-lab (&key frames (fps 60))
  "Explore event controls over the generated UI card.
B toggles mouse-motion filtering, G mouse grab, K keyboard grab, and Escape exits.
FRAMES bounds the run. Return a plist describing the final observed state."
  (check-type frames (or null (integer 0 *)))
  (check-type fps (integer 1 *))
  (px:with-init ()
    (let* ((screen (px.display:set-mode '(720 470) :title "Pixelisp — UI and Events"))
           (clock (px.time:make-clock))
           (font (px.font:make-font nil 16))
           (card (ui-demo))
           (last-event "No events yet")
           (notice "")
           (cached-status nil)
           (status-image nil)
           (running t)
           (result nil))
      ;; This example owns its runtime. WITH-INIT clears filters and releases
      ;; windows, grabs, fonts, and cached surfaces even when a callback fails.
      (px.surface:fill screen '(16 23 36))
      (px.surface:blit screen card '(0 0))
      (%ui-label screen font "B: filter motion   G: mouse grab   K: keyboard grab   Esc: quit" '(24 440))
      (loop for frame from 0
            while (and running (or (null frames) (< frame frames))) do
              (dolist (event (px.event:get))
                (setf last-event (px.event:event-name (px.event:type event)))
                (case (px.event:type event)
                  (:quit (setf running nil))
                  (:key-down
                   (case (px.event:attribute event :key)
                     (:escape (setf running nil))
                     (:b (if (px.event:get-blocked :mouse-motion)
                             (px.event:set-allowed :mouse-motion)
                             (px.event:set-blocked :mouse-motion)))
                     (:g (px.event:set-grab (not (px.event:get-grab))))
                     (:k
                      (handler-case
                          (px.event:set-keyboard-grab (not (px.event:get-keyboard-grab)))
                        (px:unsupported-feature () (setf notice "Keyboard grab unavailable"))))))))
              (setf result (list :motion-blocked (px.event:get-blocked :mouse-motion)
                                 :mouse-grab (px.event:get-grab)
                                 :keyboard-grab
                                 (handler-case (px.event:get-keyboard-grab)
                                   (px:unsupported-feature () :unavailable))))
              (let ((status (format nil "Motion blocked: ~A   Mouse grab: ~A   Keyboard: ~A"
                                    (getf result :motion-blocked) (getf result :mouse-grab)
                                    (getf result :keyboard-grab))))
                (unless (equal (list status last-event notice) cached-status)
                  (when status-image (px:dispose status-image))
                  (setf cached-status (list status last-event notice)
                        status-image (px.surface:make-surface '(680 64)))
                  (px.surface:fill status-image '(16 23 36))
                  (%ui-label status-image font status '(0 0))
                  (%ui-label status-image font (format nil "Last event: ~A  ~A" last-event notice) '(0 28))
                  (px.surface:blit screen status-image '(24 370))))
              (px.display:flip)
              (px.time:tick clock fps))
      result)))
