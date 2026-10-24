;;;; A small, generated-art collision lab for exploring pixel masks.
;;;;
;;;; Run (px.examples:mask-lab). Move the orange diamond with WASD or arrows;
;;;; the overlap is shown in pink and its pixel count stays live at the top.
(in-package #:pixelisp.examples)

(defun mask-lab (&key frames (fps 60))
  "Run a live mask collision demo. FRAMES may be NIL or a nonnegative integer.

Move the orange shape with the arrow keys or WASD. Escape or closing the
window exits. The pink pixels are the current mask intersection."
  (unless (or (null frames) (and (integerp frames) (not (minusp frames))))
    (error "FRAMES must be NIL or a nonnegative integer, got ~S." frames))
  (check-type fps (integer 1 *))
  (px:with-init ()
    (let* ((screen (px.display:set-mode '(720 500) :title "Pixelisp — Mask Lab"))
           (clock (px.time:make-clock))
           (font (px.font:make-font nil 20))
           (hint (px.font:render font "Move: arrows / WASD    Escape: quit" t '(165 185 205)))
           (background (px.surface:make-surface '(720 500)))
           (fixed-image (px.surface:make-surface '(150 130) :alpha t))
           (moving-image (px.surface:make-surface '(112 112) :alpha t))
           (fixed-mask nil)
           (moving-mask nil)
           (fixed-position '(270 185))
           ;; Start with a partial collision so the overlap overlay is visible
           ;; immediately; the controls let the reader separate the shapes.
           (moving-position '(330 215))
           (running t)
           (overlap 0)
           (label-overlap nil)
           (label nil))
      (unwind-protect
           (progn
             ;; Make two different silhouettes entirely in Lisp, then derive
             ;; their collision bits from alpha exactly as a game would.
             (px.draw:ellipse fixed-image '(55 185 210) '(12 12 126 106))
             (px.draw:circle fixed-image '(120 230 235) '(52 64) 29)
             (px.draw:rect moving-image '(245 145 70) '(20 16 72 78))
             (px.draw:polygon moving-image '(255 180 95)
                              '((56 2) (108 55) (56 110) (3 55)))
             (setf fixed-mask (px.mask:from-surface fixed-image)
                   moving-mask (px.mask:from-surface moving-image))
             (px.surface:fill background '(16 23 37))
             (px.draw:rect background '(25 36 54) '(20 72 680 390) :border-radius 18)
             (px.draw:rect background '(40 57 78) '(32 84 656 366) :width 1 :border-radius 12)
             (loop for frame from 0
                   while (and running (or (null frames) (< frame frames)))
                   for seconds = (/ (px.time:tick clock fps) 1000.0)
                   do
                      ;; 1. Events: window close and Escape end the lab.
                      (dolist (event (px.event:get))
                        (when (or (eq (px.event:type event) :quit)
                                  (and (eq (px.event:type event) :key-down)
                                       (eq (px.event:attribute event :key) :escape)))
                          (setf running nil)))
                      ;; 2. Update: move, clamp, then measure mask overlap.
                      (let* ((dx (- (if (or (px.key:pressed-p :right) (px.key:pressed-p :d)) 1 0)
                                    (if (or (px.key:pressed-p :left) (px.key:pressed-p :a)) 1 0)))
                             (dy (- (if (or (px.key:pressed-p :down) (px.key:pressed-p :s)) 1 0)
                                    (if (or (px.key:pressed-p :up) (px.key:pressed-p :w)) 1 0))))
                        (setf moving-position
                              (list (max 34 (min 574 (+ (first moving-position)
                                                        (round (* dx 260 seconds)))))
                                    (max 94 (min 346 (+ (second moving-position)
                                                        (round (* dy 260 seconds))))))))
                      (setf overlap
                            (px.mask:overlap-area fixed-mask moving-mask
                                                  (list (- (first moving-position) (first fixed-position))
                                                        (- (second moving-position) (second fixed-position)))))
                      ;; Text surfaces are cached until the displayed count changes.
                      (unless (eql overlap label-overlap)
                        (when label (px:dispose label))
                        (setf label (px.font:render font
                                     (format nil "Mask Lab   ·   overlap: ~D pixels" overlap)
                                     t '(225 235 248))
                              label-overlap overlap))
                      ;; 3. Draw: to-surface paints only set bits; NIL unset
                      ;; colors preserve the background. Pink marks collision.
                      (px.surface:blit screen background '(0 0))
                      (px.surface:blit screen label '(32 28))
                      (px.surface:blit screen hint '(32 52))
                      (px.mask:to-surface fixed-mask :surface screen
                                          :dest fixed-position
                                          :set-color '(55 195 205 210) :unset-color nil)
                      (px.mask:to-surface moving-mask :surface screen
                                          :dest moving-position
                                          :set-color '(240 145 65 220) :unset-color nil)
                      (let ((intersection (px.mask:overlap-mask
                                           fixed-mask moving-mask
                                           (list (- (first moving-position) (first fixed-position))
                                                 (- (second moving-position) (second fixed-position))))))
                        (px.mask:to-surface intersection :surface screen
                                            :dest fixed-position
                                            :set-color '(255 75 145 235) :unset-color nil))
                      (px.display:flip))
             overlap)
        (when label (px:dispose label))
        (px:dispose hint)
        (px:dispose moving-image)
        (px:dispose fixed-image)
        (px:dispose background)))))
