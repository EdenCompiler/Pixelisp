;;;; Rendering masks to software Surfaces.
;;;;
;;;; Colors are copied as stored RGBA values. This is a pixel operation, not a
;;;; blended blit, so transparent pixels and source alpha survive unchanged.
(in-package #:pixelisp.mask)

(defun %snapshot-plane (surface)
  "Copy a color plane before drawing, so overlapping Surface views are safe."
  (when surface
    (let ((pixels (make-array (list (px.surface:height surface)
                                    (px.surface:width surface)))))
      (dotimes (y (px.surface:height surface) pixels)
        (dotimes (x (px.surface:width surface))
          (setf (aref pixels y x) (px.surface:get-at surface (list x y))))))))

(defun %same-pixel-format-p (first second)
  "Check pygame's to_surface format rule: depth, bytes per pixel, and alpha."
  (and (= (px.surface:get-bitsize first) (px.surface:get-bitsize second))
       (= (px.surface:get-bytesize first) (px.surface:get-bytesize second))
       (= (fourth (px.surface:get-masks first))
          (fourth (px.surface:get-masks second)))))

(defun to-surface (mask &key surface set-surface unset-surface
                               (set-color '(255 255 255 255))
                               (unset-color '(0 0 0 255))
                               (dest '(0 0)))
  "Draw MASK into SURFACE and return it, creating an alpha Surface if omitted.

Set and unset pixels use the corresponding optional source Surface when that
plane contains the mask coordinate; otherwise they use SET-COLOR or
UNSET-COLOR. A NIL color skips that kind of pixel. DEST moves only the result
position; the source planes remain aligned to the mask."
  (dolist (plane (remove nil (list set-surface unset-surface)))
    (check-type plane px.surface:surface)
    ;; Check even when the mask is empty or this plane is never selected.
    (pixelisp.internal:ensure-live plane))
  (when surface
    (check-type surface px.surface:surface)
    ;; Also check an empty mask and two NIL colors, which perform no pixel I/O.
    (pixelisp.internal:ensure-live surface))
  ;; Convert colors exactly once before allocation or any destination writes.
  (let* ((set-color (when set-color (multiple-value-list (pixelisp.internal:rgba set-color))))
         (unset-color (when unset-color (multiple-value-list (pixelisp.internal:rgba unset-color))))
         (owned-result-p (null surface))
         (dest-pair (multiple-value-list (pixelisp.internal:pair dest)))
         (dx (truncate (first dest-pair)))
         (dy (truncate (second dest-pair)))
         (result (or surface (px.surface:make-surface (get-size mask) :alpha t)))
         (set-pixels nil)
         (unset-pixels nil)
         (completed-p nil))
    (unwind-protect
         (progn
           (dolist (plane (remove nil (list set-surface unset-surface)))
             (unless (%same-pixel-format-p plane result)
               (error "Mask source Surface and destination must have matching depth, bytesize, and alpha format.")))
           ;; Snapshot before writing. Subsurfaces can alias one another or the
           ;; destination while occupying different coordinates.
           (setf set-pixels (%snapshot-plane set-surface)
                 unset-pixels (%snapshot-plane unset-surface))
           (dotimes (y (height mask))
             (dotimes (x (width mask))
               (let* ((set (= 1 (aref (mask-bits mask) y x)))
                      (plane (if set set-pixels unset-pixels))
                      (color (if set set-color unset-color))
                      (target-x (+ dx x))
                      (target-y (+ dy y)))
                 (when (and plane (< y (array-dimension plane 0))
                            (< x (array-dimension plane 1)))
                   (setf color (aref plane y x)))
                 ;; Surface:SET-AT applies the destination clip and safely
                 ;; ignores coordinates outside the destination bounds.
                 (when color
                   (when (and (<= 0 target-x) (< target-x (px.surface:width result))
                              (<= 0 target-y) (< target-y (px.surface:height result)))
                     (px.surface:set-at result (list target-x target-y) color))))))
           (setf completed-p t)
           result)
      (when (and owned-result-p result (not completed-p))
        ;; Keep the caller's resource list clean when validation or drawing
        ;; fails after creating the output Surface.
        (px:dispose result)))))
