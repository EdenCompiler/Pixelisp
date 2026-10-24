;;;; A small pixel-editing workbench. The source stays immutable; each preview
;;;; starts from it, so changing the tolerance never compounds earlier edits.
(in-package #:pixelisp.examples)

(defun %pixel-lab-source ()
  "Return a warm color chart with an exact tomato-colored circle and blue detail."
  (let ((image (px.surface:make-surface '(96 64))))
    (handler-case
        (progn
          (dotimes (row 4)
            (dotimes (column 6)
              (px.draw:rect image (list (+ 160 (* column 18)) (+ 40 (* row 25)) (+ 30 (* column 8)))
                            (list (* column 16) (* row 16) 16 16))))
          (px.draw:circle image "tomato" '(24 28) 12)
          (px.draw:circle image "deepskyblue" '(72 32) 18)
          (px.draw:rect image "navy" '(68 24 12 16))
          image)
      (error (condition) (px:dispose image) (error condition)))))

(defun %pixel-lab-edit (source distance red-only transposed)
  "Return an owned edited image and its selected-pixel count as two values."
  (px:with-resource (working (px.surface:copy source))
    (px.pixelarray:with-pixel-array (pixels working)
      (let* ((weights (if red-only '(1 0 0) '(0.299 0.587 0.114)))
             (selection (px.pixelarray:extract pixels "tomato" :distance distance :weights weights))
             (count (loop for index below (array-total-size selection)
                          sum (row-major-aref selection index))))
        (px.pixelarray:replace pixels "tomato" "gold" :distance distance :weights weights)
        ;; The returned image owns a copy. Close a dependent transpose before
        ;; its parent pixels, then release WORKING before the caller draws.
        (values (if transposed
                    (px.buffer:with-view (turned (px.pixelarray:transpose pixels))
                      (px.pixelarray:make-surface turned))
                    (px.pixelarray:make-surface pixels))
                count)))))

(defun %pixel-lab-label (target font text position &key centered)
  (px:with-resource (label (px.font:render font text t "gainsboro"))
    (px.surface:blit target label (if centered (px.surface:get-rect label :mid-top position) position))))

(defun %pixel-lab-sheet (source edited font count distance red-only)
  "Render a cached side-by-side preview using positional vector batch blits."
  (let ((sheet (px.surface:make-surface '(620 380))))
    (handler-case
        (px:with-resource (left (px.transform:scale-by source 2))
          (px:with-resource (right (px.transform:scale-by edited 2))
            (px.surface:fill sheet '(16 23 36))
            (%pixel-lab-label sheet font "Weighted pixel replacement: tomato to gold" '(20 20))
            (px.draw:rect sheet '(29 40 57) '(20 62 280 220) :border-radius 12)
            (px.draw:rect sheet '(29 40 57) '(320 62 280 220) :border-radius 12)
            (%pixel-lab-label sheet font "Source" '(160 64) :centered t)
            (%pixel-lab-label sheet font "Edited / optional transpose" '(460 64) :centered t)
            ;; No damage-list allocation is needed for a fully cached picture.
            (px.surface:blits sheet
                              (vector (vector left (px.surface:get-rect left :center '(160 180)))
                                      (vector right (px.surface:get-rect right :center '(460 180))))
                              :return-rects nil)
            (%pixel-lab-label sheet font
                             (format nil "Distance: ~,2F    Matches: ~D    Weights: ~A"
                                     distance count (if red-only "red only" "perceptual RGB")) '(20 295))
            (%pixel-lab-label sheet font "Left/Right: tolerance   Space: weights   T: transpose   R: reset" '(20 322))
            (%pixel-lab-label sheet font
                             (format nil "RGBA shifts: ~{~D~^/~}   Blend mode: ~A   Esc: quit"
                                     (px.surface:get-shifts source) (px.surface:get-blendmode source)) '(20 350))
            sheet))
      (error (condition) (px:dispose sheet) (error condition)))))

(defun pixel-match-demo (&key (distance 3/20) red-only transposed)
  "Return an owned 620x380 picture of weighted color replacement and transpose."
  (px:with-resource (source (%pixel-lab-source))
    (px:with-resource (font (px.font:make-font nil 14))
      (multiple-value-bind (edited count) (%pixel-lab-edit source distance red-only transposed)
        (px:with-resource (image edited)
          (%pixel-lab-sheet source image font count distance red-only))))))

(defun pixel-lab (&key frames (fps 60))
  "Explore weighted pixel replacement. Hold Left/Right to change tolerance;
Space switches RGB weights, T transposes, R resets, and Escape quits.
FRAMES bounds the loop. Return the final settings and match count as a plist."
  (check-type frames (or null (integer 0 *)))
  (check-type fps (integer 1 *))
  (px:with-init ()
    (let* ((screen (px.display:set-mode '(620 380) :title "Pixelisp — Pixel Lab"))
           (source (%pixel-lab-source))
           (font (px.font:make-font nil 14))
           (clock (px.time:make-clock))
           (distance 3/20) (red-only nil) (transposed nil)
           (matches 0) (sheet nil) (changed t) (running t))
      (px.key:set-repeat 250 60)
      (loop for frame from 0
            while (and running (or (null frames) (< frame frames))) do
              (dolist (event (px.event:get))
                (case (px.event:type event)
                  (:quit (setf running nil))
                  (:key-down
                   (case (px.event:attribute event :key)
                     (:escape (setf running nil))
                     (:left (setf distance (max 0 (- distance 1/20)) changed t))
                     (:right (setf distance (min 1 (+ distance 1/20)) changed t))
                     (:space (setf red-only (not red-only) changed t))
                     (:t (setf transposed (not transposed) changed t))
                     (:r (setf distance 3/20 red-only nil transposed nil changed t))))))
              (when changed
                (multiple-value-bind (edited count) (%pixel-lab-edit source distance red-only transposed)
                  (px:with-resource (image edited)
                    (when sheet (px:dispose sheet))
                    (setf sheet (%pixel-lab-sheet source image font count distance red-only)
                          matches count changed nil))))
              (px.surface:blit screen sheet '(0 0))
              (px.display:flip)
              (px.time:tick clock fps))
      (list :distance distance :red-only red-only :transposed transposed :matches matches))))
