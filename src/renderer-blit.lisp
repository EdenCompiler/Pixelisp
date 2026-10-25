;;;; A familiar blit entry point for the separate SDL renderer API.
;;;; Drawing stays in DRAW-TEXTURE/DRAW-IMAGE, which already manage ownership
;;;; and per-image modifiers. This file only translates the convenience inputs.
(in-package #:pixelisp.sdl2.video)

(defun %blit-rect (value)
  "Copy a rectangle and validate its coordinates before changing drawing state."
  (let ((rect (px.rect:copy (pixelisp.internal:as-rect value))))
    (dolist (coordinate (list (px.rect:x rect) (px.rect:y rect)
                              (px.rect:width rect) (px.rect:height rect)))
      (check-type coordinate (signed-byte 32)))
    rect))

(defun %blit-source-region (source)
  "Return the texture owner and the source's native-sized region."
  (etypecase source
    (texture
     (%pointer source)
     (values source (apply #'px:make-rect 0 0 (texture-size source))))
    (image
     (values (image-texture source) (image-source-rect source)))))

(defun %blit-area (area region)
  "Accept a contained source-local crop, including empty crops."
  (when area
    (let ((rect (%blit-rect area)))
      (unless (and (<= 0 (px.rect:x rect)) (<= 0 (px.rect:y rect))
                   (<= 0 (px.rect:width rect)) (<= 0 (px.rect:height rect))
                   (<= (+ (px.rect:x rect) (px.rect:width rect)) (px.rect:width region))
                   (<= (+ (px.rect:y rect) (px.rect:height rect)) (px.rect:height region)))
        (error "BLIT area must be contained in the source's region: ~S." area))
      rect)))

(defun %blit-destination (destination region)
  "A point uses the full source size; NIL asks SDL to fill the viewport."
  (when destination
    (%blit-rect
     (if (and (typep destination 'sequence) (= (length destination) 2))
         (multiple-value-bind (x y) (pixelisp.internal:pair destination)
           (px:make-rect x y (px.rect:width region) (px.rect:height region)))
         destination))))

(defun blit (renderer source &optional destination &key area (special-flags 0))
  "Draw a Texture or Image and return its requested destination Rect.

DESTINATION accepts a Rect, a four-value sequence, a point, or NIL for the
viewport. AREA is a contained source-local crop. As in pygame's renderer API,
SPECIAL-FLAGS is accepted but ignored; use texture/image blend modes instead.
The return Rect is not clipped damage and does not include image rotation.
NIL or a zero-sized destination returns the viewport, matching pygame."
  ;; SDL handles are untyped pointers: reject the wrong Lisp subtype first.
  (check-type renderer renderer)
  (%pointer renderer)
  (check-type special-flags (signed-byte 32))
  (multiple-value-bind (texture region) (%blit-source-region source)
    (unless (eq renderer (%parent texture))
      (error 'pixelisp:error :operation 'blit
             :message "The source belongs to a different renderer."))
    (let* ((crop (%blit-area area region))
           (destination (%blit-destination destination region))
           (empty-crop (and crop (or (zerop (px.rect:width crop))
                                     (zerop (px.rect:height crop))))))
      ;; Image crops are normally required to be nonempty. An empty blit crop
      ;; is a no-op; do not create an invalid Image view just to represent it.
      (unless empty-crop
        (etypecase source
          (texture (draw-texture renderer source :source crop :destination destination))
          (image (draw-image renderer source :source crop :destination destination))))
      ;; Return a fresh Lisp value. Keep SDL's viewport offset and the caller's
      ;; un-clipped rectangle even when only part of the draw was visible.
      (if (or (null destination) (zerop (px.rect:width destination))
              (zerop (px.rect:height destination)))
          (apply #'px:make-rect (viewport renderer))
          destination))))
