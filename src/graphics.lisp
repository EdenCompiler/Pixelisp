;;;; CPU graphics for Pixelisp.
;;;;
;;;; Drawing modifies Surface pixels directly, just as pygame.draw does. Transforms
;;;; produce independent images; masks keep one Lisp bit per pixel. None of these
;;;; algorithms require an SDL renderer or the additional SDL2_gfx library.

(defpackage #:pixelisp.draw
  (:nicknames #:px.draw)
  (:use #:cl)
  (:export #:rect #:line #:lines #:aaline #:aalines #:circle #:ellipse #:polygon #:arc))
(defpackage #:pixelisp.gfxdraw
  (:nicknames #:px.gfxdraw)
  (:use #:cl)
  (:export #:pixel #:hline #:vline #:rectangle #:box #:line #:aaline #:circle
           #:aacircle #:filled-circle #:ellipse #:aaellipse #:filled-ellipse
           #:arc #:pie #:trigon #:aatrigon #:filled-trigon #:polygon #:aapolygon
           #:filled-polygon #:textured-polygon #:bezier))
(defpackage #:pixelisp.transform
  (:nicknames #:px.transform)
  (:use #:cl)
  (:export #:flip #:scale #:scale-by #:smoothscale #:smoothscale-by #:rotate #:rotozoom
           #:scale2x #:chop #:grayscale #:laplacian #:average-color #:average-surfaces #:threshold
           #:get-smoothscale-backend #:set-smoothscale-backend))
(defpackage #:pixelisp.mask
  (:nicknames #:px.mask)
  (:use #:cl)
  (:shadow #:count #:fill #:clear)
  (:export #:mask #:make-mask #:width #:height #:get-size #:get-rect #:copy
           #:get-at #:set-at #:count #:fill #:clear #:invert #:from-surface
           #:from-threshold #:overlap #:overlap-area #:overlap-mask #:draw #:erase
           #:scale #:centroid #:angle #:outline #:connected-component
           #:connected-components #:get-bounding-rects #:convolve #:to-surface))

(in-package #:pixelisp.draw)

;;; A drawing operation keeps its clipping rectangle and damaged bounds in dynamic
;;; bindings. Plotting individual pixels then has a single, shared clipping rule.
(defvar *target*)
(defvar *clip*)
(defvar *damage*)

(defun %point (position)
  (multiple-value-bind (x y) (pixelisp.internal:pair position)
    (list (round x) (round y))))

(defun %color (value surface)
  "Normalize a color once per operation, preserving native packed integers."
  (if (integerp value) (px.surface::%checked-mapped-pixel surface value)
      (multiple-value-call #'pixelisp:make-color (pixelisp.internal:rgba value))))

(defun %drawing-clip (surface)
  (let ((clip (px.surface:get-clip surface)))
    (list (max 0 (pixelisp:rect-x clip))
          (max 0 (pixelisp:rect-y clip))
          (min (px.surface:width surface) (+ (pixelisp:rect-x clip) (pixelisp:rect-width clip)))
          (min (px.surface:height surface) (+ (pixelisp:rect-y clip) (pixelisp:rect-height clip))))))

(defun %damage-rect ()
  (if *damage*
      (destructuring-bind (left top right bottom) *damage*
        (pixelisp:make-rect left top (1+ (- right left)) (1+ (- bottom top))))
      (pixelisp:make-rect 0 0 0 0)))

(defmacro %with-drawing ((surface) &body body)
  `(let* ((*target* ,surface) (*clip* (%drawing-clip *target*)) (*damage* nil))
     ;; Lock once for a whole operation; Surface pixel access supports nested locks.
     (px.surface:lock *target*)
     (unwind-protect (progn ,@body (%damage-rect))
       (px.surface:unlock *target*))))

(defun %plot (x y color &optional (coverage 1))
  (when (and (<= (first *clip*) x) (< x (third *clip*))
             (<= (second *clip*) y) (< y (fourth *clip*))
             (plusp coverage))
    (let ((color color))
      (when (< coverage 1)
        ;; Coverage blending needs channels; full samples keep the original
        ;; packed bits. In particular, equal palette colors may have distinct
        ;; indices, and unused bits in a truecolor pixel must survive a draw.
        (when (integerp color)
          (setf color (px.surface:unmap-rgb *target* color)))
        (let ((background (px.surface:get-at *target* (list x y))))
          (flet ((mix (source destination)
                   (round (+ (* coverage source) (* (- 1 coverage) destination)))))
            (setf color (pixelisp:make-color
                         (mix (pixelisp:color-r color) (pixelisp:color-r background))
                         (mix (pixelisp:color-g color) (pixelisp:color-g background))
                         (mix (pixelisp:color-b color) (pixelisp:color-b background))
                         (mix (pixelisp:color-a color) (pixelisp:color-a background)))))))
      (if (integerp color)
          (px.surface::%write-packed-pixel *target* x y color)
          (px.surface:set-at *target* (list x y) color)))
    (if *damage*
        (setf (first *damage*) (min x (first *damage*))
              (second *damage*) (min y (second *damage*))
              (third *damage*) (max x (third *damage*))
              (fourth *damage*) (max y (fourth *damage*)))
        (setf *damage* (list x y x y)))))

(defun %span (left right y color)
  (loop for x from (max (ceiling left) (first *clip*))
        to (min (floor right) (1- (third *clip*)))
        do (%plot x y color)))

(defun %clipped-segment (x1 y1 x2 y2 padding)
  "Liang–Barsky clipping prevents enormous offscreen lines from doing wasted work."
  (let* ((dx (- x2 x1)) (dy (- y2 y1))
         (start 0) (end 1)
         (left (- (first *clip*) padding))
         (top (- (second *clip*) padding))
         (right (+ (1- (third *clip*)) padding))
         (bottom (+ (1- (fourth *clip*)) padding)))
    (loop for p in (list (- dx) dx (- dy) dy)
          for q in (list (- x1 left) (- right x1) (- y1 top) (- bottom y1))
          do (cond ((zerop p) (when (minusp q) (return-from %clipped-segment nil)))
                   ((minusp p) (setf start (max start (/ q p))))
                   (t (setf end (min end (/ q p)))))
          when (> start end) do (return-from %clipped-segment nil))
    (list (round (+ x1 (* start dx))) (round (+ y1 (* start dy)))
          (round (+ x1 (* end dx))) (round (+ y1 (* end dy))))))

(defun %stroke (color start end width)
  "Rasterize a segment with Bresenham's integer error accumulator."
  (when (plusp width)
    (let ((clipped (%clipped-segment (first start) (second start)
                                     (first end) (second end) (ceiling width 2))))
      (when clipped
        (destructuring-bind (x y end-x end-y) clipped
          (let* ((dx (abs (- end-x x))) (dy (- (abs (- end-y y))))
                 (step-x (if (< x end-x) 1 -1))
                 (step-y (if (< y end-y) 1 -1))
                 (error (+ dx dy))
                 (low (- (floor width 2))) (high (+ low width -1)))
            (loop
              (loop for offset-y from low to high
                    do (%span (+ x low) (+ x high) (+ y offset-y) color))
              (when (and (= x end-x) (= y end-y)) (return))
              (let ((twice-error (* 2 error)))
                (when (>= twice-error dy) (incf error dy) (incf x step-x))
                (when (<= twice-error dx) (incf error dx) (incf y step-y))))))))))

(defun line (surface color start end &key (width 1))
  "Draw a straight segment, including both endpoints; return the affected Rect."
  (%with-drawing (surface) (%stroke (%color color surface) (%point start) (%point end) (truncate width))))

(defun lines (surface color closed points &key (width 1))
  "Draw connected segments. CLOSED also connects the final point to the first."
  (let ((points (map 'list #'%point points)) (color (%color color surface)))
    (unless (>= (length points) 2) (error "LINES needs at least two points."))
    (%with-drawing (surface)
      (loop for (first second) on points while second do (%stroke color first second width))
      (when closed (%stroke color (car (last points)) (first points) width)))))

(defun %aa-stroke (color start end blend)
  "Xiaolin Wu's coverage rule splits each sample between two neighboring pixels."
  (let* ((x1 (first start)) (y1 (second start)) (x2 (first end)) (y2 (second end))
         (steep (> (abs (- y2 y1)) (abs (- x2 x1)))))
    (when steep (rotatef x1 y1) (rotatef x2 y2))
    (when (> x1 x2) (rotatef x1 x2) (rotatef y1 y2))
    (if (= x1 x2)
        (%stroke color start end 1)
        (let* ((gradient (/ (- y2 y1) (- x2 x1)))
               (begin (max x1 (if steep (second *clip*) (first *clip*))))
               (finish (min x2 (1- (if steep (fourth *clip*) (third *clip*))))))
          (loop for x from begin to finish
                for sample = (+ y1 (* (- x x1) gradient))
                for y = (floor sample)
                for fraction = (- sample y)
                do (flet ((plot (y coverage)
                            (if steep (%plot y x color (if blend coverage (if (plusp coverage) 1 0)))
                                (%plot x y color (if blend coverage (if (plusp coverage) 1 0))))))
                     (plot y (- 1 fraction)) (plot (1+ y) fraction)))))))

(defun aaline (surface color start end &key (blend t))
  "Draw a one-pixel antialiased segment, blending coverage with existing pixels."
  (%with-drawing (surface) (%aa-stroke (%color color surface) (%point start) (%point end) blend)))
(defun aalines (surface color closed points &key (blend t))
  "Draw connected antialiased segments and return their combined damaged Rect."
  (let ((points (map 'list #'%point points)) (color (%color color surface)))
    (unless (>= (length points) 2) (error "AALINES needs at least two points."))
    (%with-drawing (surface)
      (loop for (first second) on points while second do (%aa-stroke color first second blend))
      (when closed (%aa-stroke color (car (last points)) (first points) blend)))))

(defun %fit-corner-radii (radii width height)
  "Scale corner radii together until each pair fits its shared edge."
  (let* ((top (+ (first radii) (second radii)))
         (bottom (+ (third radii) (fourth radii)))
         (left (+ (first radii) (third radii)))
         (right (+ (second radii) (fourth radii)))
         (width (max 0 width)) (height (max 0 height))
         (scale (min 1
                     (if (plusp top) (/ width top) 1)
                     (if (plusp bottom) (/ width bottom) 1)
                     (if (plusp left) (/ height left) 1)
                     (if (plusp right) (/ height right) 1))))
    (mapcar (lambda (radius) (* radius scale)) radii)))

(defun %inside-rounded-rect (x y left top width height radii)
  (and (<= left x) (< x (+ left width)) (<= top y) (< y (+ top height))
       (let* ((right (+ left width -1)) (bottom (+ top height -1))
              (tl (first radii)) (tr (second radii))
              (bl (third radii)) (br (fourth radii)))
         (flet ((in-circle (cx cy radius)
                  (or (zerop radius)
                      (<= (+ (expt (- x cx) 2) (expt (- y cy) 2))
                          (* radius radius)))))
           (cond ((and (< x (+ left tl)) (< y (+ top tl)))
                  (in-circle (+ left tl) (+ top tl) tl))
                 ((and (> x (- right tr)) (< y (+ top tr)))
                  (in-circle (- right tr) (+ top tr) tr))
                 ((and (< x (+ left bl)) (> y (- bottom bl)))
                  (in-circle (+ left bl) (- bottom bl) bl))
                 ((and (> x (- right br)) (> y (- bottom br)))
                  (in-circle (- right br) (- bottom br) br))
                 (t t))))))

(defun rect (surface color rectangle &key (width 0) (border-radius 0)
                                        (border-top-left-radius -1)
                                        (border-top-right-radius -1)
                                        (border-bottom-left-radius -1)
                                        (border-bottom-right-radius -1))
  "Draw a filled or inward-stroked rectangle, optionally rounding each corner."
  (let* ((rect (pixelisp.internal:as-rect rectangle))
         (left (pixelisp:rect-x rect)) (top (pixelisp:rect-y rect))
         (w (pixelisp:rect-width rect)) (h (pixelisp:rect-height rect))
         ;; Negative corner values inherit the common radius; zero squares a corner.
         (radii (%fit-corner-radii
                 (mapcar (lambda (radius)
                           (max 0 (truncate (if (minusp radius) border-radius radius))))
                         (list border-top-left-radius border-top-right-radius
                               border-bottom-left-radius border-bottom-right-radius))
                 w h))
         (inner-width (max 0 (- w (* 2 width))))
         (inner-height (max 0 (- h (* 2 width))))
         (inner-radii (%fit-corner-radii
                       (mapcar (lambda (radius) (max 0 (- radius width))) radii)
                       inner-width inner-height))
         (color (%color color surface)))
    (%with-drawing (surface)
      (when (and (plusp w) (plusp h) (not (minusp width)))
        (loop for y from (max top (second *clip*)) below (min (+ top h) (fourth *clip*))
              do (loop for x from (max left (first *clip*)) below (min (+ left w) (third *clip*))
                       when (and (%inside-rounded-rect x y left top w h radii)
                                 (or (zerop width)
                                     (not (%inside-rounded-rect
                                           x y (+ left width) (+ top width)
                                           inner-width inner-height inner-radii))))
                         do (%plot x y color)))))))

(defun ellipse (surface color rectangle &key (width 0))
  "Draw an ellipse inside RECTANGLE. A positive WIDTH draws an inward outline."
  (let* ((rect (pixelisp.internal:as-rect rectangle))
         (rx (/ (pixelisp:rect-width rect) 2)) (ry (/ (pixelisp:rect-height rect) 2))
         (cx (+ (pixelisp:rect-x rect) rx)) (cy (+ (pixelisp:rect-y rect) ry))
         (inner-x (- rx width)) (inner-y (- ry width)) (color (%color color surface)))
    (%with-drawing (surface)
      (when (and (plusp rx) (plusp ry) (not (minusp width)))
        (loop for y from (max (floor (- cy ry)) (second *clip*))
              below (min (ceiling (+ cy ry)) (fourth *clip*))
              do (loop for x from (max (floor (- cx rx)) (first *clip*))
                       below (min (ceiling (+ cx rx)) (third *clip*))
                       for dx = (- (+ x 1/2) cx) for dy = (- (+ y 1/2) cy)
                       when (and (<= (+ (/ (* dx dx) (* rx rx)) (/ (* dy dy) (* ry ry))) 1)
                                 (or (zerop width) (not (and (plusp inner-x) (plusp inner-y)
                                      (< (+ (/ (* dx dx) (* inner-x inner-x))
                                            (/ (* dy dy) (* inner-y inner-y))) 1)))))
                         do (%plot x y color)))))))

(defun circle (surface color center radius &key (width 0)
                   (draw-top-right t) (draw-top-left t) (draw-bottom-left t) (draw-bottom-right t))
  "Draw a circle or ring. Quadrant keywords can select individual quarters."
  (destructuring-bind (cx cy) (%point center)
    (let ((radius (truncate radius)) (color (%color color surface)))
      (%with-drawing (surface)
        ;; Like pygame, nonpositive radii leave the surface unchanged.
        (when (and (plusp radius) (not (minusp width)))
          (loop for y from (max (- cy radius) (second *clip*))
                to (min (+ cy radius) (1- (fourth *clip*)))
                do (loop for x from (max (- cx radius) (first *clip*))
                         to (min (+ cx radius) (1- (third *clip*)))
                         for squared = (+ (expt (- x cx) 2) (expt (- y cy) 2))
                         when (and (<= squared (* radius radius))
                                   (or (zerop width) (>= width radius)
                                       (> squared (expt (- radius width) 2)))
                                   (if (< y cy)
                                       (if (< x cx) draw-top-left draw-top-right)
                                       (if (< x cx) draw-bottom-left draw-bottom-right)))
                           do (%plot x y color))))))))

(defun polygon (surface color points &key (width 0))
  "Fill a polygon using half-open scanline edges, or stroke its closed boundary."
  (let ((points (map 'list #'%point points)) (color (%color color surface)))
    (unless (>= (length points) 3) (error "A polygon needs at least three points."))
    (%with-drawing (surface)
      (cond ((plusp width)
             (loop for (first second) on (append points (list (first points)))
                   while second do (%stroke color first second width)))
            ((zerop width)
             (loop for y from (max (reduce #'min points :key #'second) (second *clip*))
                   below (min (reduce #'max points :key #'second) (fourth *clip*))
                   for sample-y = (+ y 1/2)
                   for intersections =
                     (loop for (first second) on (append points (list (first points)))
                           while second
                           when (or (and (<= (second first) sample-y) (< sample-y (second second)))
                                    (and (<= (second second) sample-y) (< sample-y (second first))))
                             collect (+ (first first)
                                        (* (/ (- sample-y (second first))
                                              (- (second second) (second first)))
                                           (- (first second) (first first)))))
                   do (loop for (left right) on (sort intersections #'<) by #'cddr
                            while right do (%span (ceiling (- left 1/2))
                                                  (1- (ceiling (- right 1/2))) y color))))))))

(defun arc (surface color rectangle start-angle stop-angle &key (width 1))
  "Draw an elliptical arc; angles are radians and increase counterclockwise."
  (let* ((rect (pixelisp.internal:as-rect rectangle))
         (rx (/ (pixelisp:rect-width rect) 2)) (ry (/ (pixelisp:rect-height rect) 2))
         (cx (+ (pixelisp:rect-x rect) rx)) (cy (+ (pixelisp:rect-y rect) ry))
         (stop (if (< stop-angle start-angle) (+ stop-angle (* 2 pi)) stop-angle))
         (span (- stop start-angle))
         (steps (max 1 (ceiling (* (min span (* 2 pi)) (max rx ry) 2))))
         (color (%color color surface)))
    (%with-drawing (surface)
      (when (and (plusp rx) (plusp ry) (plusp width) (plusp span))
        (let ((previous nil))
          (loop for index from 0 to steps
                for angle = (+ start-angle (* (/ index steps) (min span (* 2 pi))))
                for point = (list (round (+ cx (* rx (cos angle))))
                                  (round (- cy (* ry (sin angle)))))
                do (when previous (%stroke color previous point width))
                   (setf previous point)))))))

(in-package #:pixelisp.transform)

(defun %dimensions (size)
  (multiple-value-bind (width height) (pixelisp.internal:pair size)
    (unless (and (integerp width) (integerp height) (not (minusp width)) (not (minusp height)))
      (error "Image dimensions must be nonnegative integers."))
    (values width height)))

(defun %new-like (source width height)
  ;; Keep the source's storage layout. In particular, indexed surfaces must
  ;; retain their palette so raw pixel indices continue to mean the same thing.
  (let ((result (px.surface::%make-like source (list width height))))
    (px.surface:set-alpha result (px.surface:get-alpha source))
    (px.surface:set-colorkey result (px.surface::%native-colorkey source))
    result))

(defun %read-pixel (surface x y)
  (px.surface::%read-packed-pixel surface x y))

(defun %write-pixel (surface x y value)
  ;; Surface transform writes address the requested pixels directly. A surface
  ;; clip rectangle affects drawing and blitting, not transform output.
  (px.surface::%write-packed-pixel surface x y value))

(defmacro %with-pixel-locks ((source target) &body body)
  `(progn
     (px.surface:lock ,source)
     (unwind-protect
          (progn
            (unless (eq ,source ,target) (px.surface:lock ,target))
       (unwind-protect (progn ,@body)
              (unless (eq ,source ,target) (px.surface:unlock ,target))))
       (px.surface:unlock ,source))))

(defun %copy-pixel (source source-x source-y target target-x target-y)
  (%write-pixel target target-x target-y (%read-pixel source source-x source-y)))

(defun %same-format-p (first second)
  (and (= (px.surface:get-bitsize first) (px.surface:get-bitsize second))
       (equal (px.surface:get-masks first) (px.surface:get-masks second))))

(defun %check-destination (source destination width height operation)
  (unless (and (= width (px.surface:width destination))
               (= height (px.surface:height destination)))
    (error "The ~A destination has the wrong dimensions." operation))
  (unless (%same-format-p source destination)
    (error "The ~A destination Surface has a different pixel format." operation))
  (when (eq source destination)
    (error "The ~A operation requires a distinct destination Surface." operation)))

(defun %check-filter-depth (surface operation)
  (when (< (px.surface:get-bitsize surface) 24)
    (error "~A supports only 24-bit and 32-bit Surfaces." operation)))

(defun flip (surface horizontal vertical)
  "Return a new image mirrored horizontally, vertically, or both."
  (let* ((width (px.surface:width surface)) (height (px.surface:height surface))
         (result (%new-like surface width height)))
    (%with-pixel-locks (surface result)
      (dotimes (y height result)
        (dotimes (x width)
          (%copy-pixel surface (if horizontal (- width x 1) x)
                       (if vertical (- height y 1) y) result x y))))))

(defun scale (surface size &optional destination)
  "Resize with nearest-neighbor sampling. An optional DESTINATION must match SIZE."
  (multiple-value-bind (width height) (%dimensions size)
    (let* ((source-width (px.surface:width surface)) (source-height (px.surface:height surface))
           (result (or destination (%new-like surface width height))))
      (%check-destination surface result width height "scale")
      (%with-pixel-locks (surface result)
        (when (and (plusp source-width) (plusp source-height))
          (dotimes (y height)
            (dotimes (x width)
              (%copy-pixel surface (min (1- source-width) (floor (* x source-width) width))
                           (min (1- source-height) (floor (* y source-height) height)) result x y)))))
      result)))

(defun %factor-size (surface factor)
  (multiple-value-bind (x y) (if (numberp factor) (values factor factor) (pixelisp.internal:pair factor))
    (unless (and (not (minusp x)) (not (minusp y))) (error "Scale factors cannot be negative."))
    (list (truncate (* x (px.surface:width surface))) (truncate (* y (px.surface:height surface))))))
(defun scale-by (surface factor &optional destination)
  "Nearest-neighbor resize using one factor or separate X/Y factors."
  (scale surface (%factor-size surface factor) destination))

(defun %weighted-color (samples)
  (let ((red 0d0) (green 0d0) (blue 0d0) (alpha 0d0) (total 0d0))
    (dolist (sample samples)
      (destructuring-bind (color weight) sample
        (incf red (* weight (pixelisp:color-r color)))
        (incf green (* weight (pixelisp:color-g color)))
        (incf blue (* weight (pixelisp:color-b color)))
        (incf alpha (* weight (pixelisp:color-a color)))
        (incf total weight)))
    (if (zerop total) (pixelisp:make-color 0 0 0 0)
        (flet ((channel (value) (max 0 (min 255 (round (/ value total))))))
          (pixelisp:make-color (channel red) (channel green) (channel blue) (channel alpha))))))

(defun %axis-samples (index source-size target-size)
  "Use box integration for shrinking and linear interpolation for enlargement."
  (if (> source-size target-size)
      (let* ((left (/ (* index source-size) target-size))
             (right (/ (* (1+ index) source-size) target-size)))
        (loop for source from (floor left) below (ceiling right)
              for weight = (- (min right (1+ source)) (max left source))
              when (plusp weight) collect (list source weight)))
      (let* ((coordinate (max 0 (min (1- source-size)
                                     (- (/ (* (+ index 1/2) source-size) target-size) 1/2))))
             (low (floor coordinate)) (fraction (- coordinate low)))
        (list (list low (- 1 fraction)) (list (min (1- source-size) (1+ low)) fraction)))))

(defun smoothscale (surface size &optional destination)
  "Resize using area averaging while shrinking and bilinear sampling while growing."
  (%check-filter-depth surface "Smoothscale")
  (multiple-value-bind (width height) (%dimensions size)
    (let* ((source-width (px.surface:width surface)) (source-height (px.surface:height surface))
           (result (or destination (%new-like surface width height))))
      (%check-destination surface result width height "smoothscale")
      (when (and (plusp source-width) (plusp source-height))
        (dotimes (y height)
          (dotimes (x width)
            (let ((samples nil))
              (dolist (ys (%axis-samples y source-height height))
                (dolist (xs (%axis-samples x source-width width))
                  (push (list (px.surface:get-at surface (list (first xs) (first ys)))
                              (* (second xs) (second ys))) samples)))
              (px.surface:set-at result (list x y) (%weighted-color samples))))))
      result)))
(defun smoothscale-by (surface factor &optional destination)
  "Filtered resize using one factor or separate X/Y factors."
  (smoothscale surface (%factor-size surface factor) destination))

(defun %bilinear (surface x y)
  (let* ((width (px.surface:width surface)) (height (px.surface:height surface))
         (x (max 0 (min (1- width) x))) (y (max 0 (min (1- height) y)))
         (left (floor x)) (top (floor y)) (fx (- x left)) (fy (- y top)))
    (%weighted-color
     (loop for (px wx) in (list (list left (- 1 fx)) (list (min (1- width) (1+ left)) fx))
           append (loop for (py wy) in (list (list top (- 1 fy)) (list (min (1- height) (1+ top)) fy))
                        collect (list (px.surface:get-at surface (list px py)) (* wx wy)))))))

(defun %rotation-image (surface pixel-source degrees zoom filtered)
  "Build a rotated image, disposing a partial result if pixel processing fails."
  (let* ((radians (* degrees (/ pi 180)))
         (cosine (cos radians)) (sine (sin radians))
         (source-width (px.surface:width surface))
         (source-height (px.surface:height surface))
         ;; Tiny trigonometric error must not add a row at exact quarter turns.
         (width (ceiling (- (* zoom (+ (* source-width (abs cosine))
                                      (* source-height (abs sine)))) 1d-10)))
         (height (ceiling (- (* zoom (+ (* source-width (abs sine))
                                       (* source-height (abs cosine)))) 1d-10)))
         (result (if filtered
                     (px.surface:make-surface (list (max 0 width) (max 0 height))
                                              :depth 32 :alpha t)
                     (%new-like surface (max 0 width) (max 0 height))))
         (complete nil))
    (unwind-protect
         (progn
           (%with-pixel-locks (pixel-source result)
             (when (and (plusp source-width) (plusp source-height))
               (let ((background
                       (if (or filtered (px.surface:alpha-p surface))
                           (px.surface:map-rgb result '(0 0 0 0))
                           (or (px.surface::%native-colorkey surface)
                               (%read-pixel pixel-source 0 0)))))
                 (dotimes (y height)
                   (dotimes (x width)
                     (%write-pixel result x y background)))
                 (dotimes (y height)
                   (dotimes (x width)
                     (let* ((dx (/ (- (+ x 1/2) (/ width 2)) zoom))
                            (dy (/ (- (+ y 1/2) (/ height 2)) zoom))
                            ;; Positive Y points down; invert the rotation's
                            ;; counterclockwise transform to find each source.
                            (sx (+ (* cosine dx) (- (* sine dy))
                                   (/ source-width 2) -1/2))
                            (sy (+ (* sine dx) (* cosine dy)
                                   (/ source-height 2) -1/2)))
                       (when (and (<= -1/2 sx) (< sx (- source-width 1/2))
                                  (<= -1/2 sy) (< sy (- source-height 1/2)))
                         (if filtered
                             (px.surface:set-at result (list x y)
                                               (%bilinear pixel-source sx sy))
                             (%write-pixel result x y
                               (%read-pixel pixel-source
                                 (max 0 (min (1- source-width)
                                             (floor (+ sx 1/2))))
                                 (max 0 (min (1- source-height)
                                             (floor (+ sy 1/2))))))))))))))
           (setf complete t)
           result)
      (unless complete (px:dispose result)))))

(defun %rotation (surface degrees zoom filtered)
  (unless (realp degrees) (error "Rotation angle must be a real number."))
  (unless (and (realp zoom) (plusp zoom))
    (error "Rotation scale must be a positive real number."))
  ;; pygame's rotozoom always produces filtered 32-bit pixels. Convert through
  ;; Surface conversion so indexed and 16-bit sources can use the same sampler.
  ;; Conversion preserves the stored pixels while translating key to pixel alpha.
  (let ((pixel-source (if filtered (px.surface:convert-alpha surface) surface)))
    (unwind-protect
         (%rotation-image surface pixel-source degrees zoom filtered)
      (when filtered (px:dispose pixel-source)))))
(defun rotate (surface degrees)
  "Rotate counterclockwise into an expanded image using nearest-neighbor samples."
  (%rotation surface degrees 1 nil))
(defun rotozoom (surface degrees zoom)
  "Rotate and uniformly resize in one bilinearly filtered operation."
  (%rotation surface degrees zoom t))

(defun scale2x (surface &optional destination)
  "Double pixel art using the Scale2x edge-preserving neighborhood rule."
  (let* ((width (px.surface:width surface)) (height (px.surface:height surface))
         (result (or destination (%new-like surface (* 2 width) (* 2 height)))))
    (%check-destination surface result (* 2 width) (* 2 height) "Scale2x")
    (%with-pixel-locks (surface result)
    (dotimes (y height result)
      (dotimes (x width)
        (flet ((pixel (dx dy)
                 (%read-pixel surface (max 0 (min (1- width) (+ x dx)))
                              (max 0 (min (1- height) (+ y dy))))))
          (let ((above (pixel 0 -1)) (left (pixel -1 0)) (center (pixel 0 0))
                (right (pixel 1 0)) (below (pixel 0 1)))
            (loop for (dx dy first second) in
                  (list (list 0 0 left above) (list 1 0 above right)
                        (list 0 1 left below) (list 1 1 below right))
                  do (%write-pixel result (+ (* 2 x) dx) (+ (* 2 y) dy)
                       (if (and (/= above below) (/= left right)
                                (= first second)) first center))))))))))

(defun chop (surface rectangle)
  "Remove the rectangle's horizontal and vertical bands and join the remainder."
  (let* ((rect (pixelisp.rect:clip (px.surface:get-rect surface) (pixelisp.internal:as-rect rectangle)))
         (cut-x (pixelisp:rect-x rect)) (cut-y (pixelisp:rect-y rect))
         (cut-width (pixelisp:rect-width rect)) (cut-height (pixelisp:rect-height rect))
         (width (- (px.surface:width surface) cut-width))
         (height (- (px.surface:height surface) cut-height))
         (result (%new-like surface width height)))
    (%with-pixel-locks (surface result)
      (dotimes (y height result)
        (dotimes (x width)
          (%copy-pixel surface (if (< x cut-x) x (+ x cut-width))
                       (if (< y cut-y) y (+ y cut-height)) result x y))))))

(defun grayscale (surface &optional destination)
  "Return luminance-weighted grayscale pixels, preserving alpha."
  (let ((result (or destination (%new-like surface (px.surface:width surface) (px.surface:height surface)))))
    (unless (equal (px.surface:size result) (px.surface:size surface)) (error "Surface sizes differ."))
    (dotimes (y (px.surface:height surface) result)
      (dotimes (x (px.surface:width surface))
        (let* ((color (px.surface:get-at surface (list x y)))
               (gray (round (+ (* 0.299d0 (pixelisp:color-r color))
                                (* 0.587d0 (pixelisp:color-g color))
                                (* 0.114d0 (pixelisp:color-b color))))))
          (px.surface:set-at result (list x y) (pixelisp:make-color gray gray gray (pixelisp:color-a color))))))))

(defun laplacian (surface &optional destination)
  "Return the pygame 2.6.1 3x3 Laplacian of SURFACE, optionally into DESTINATION.
Each RGBA channel uses center*8 minus the eight neighbors, clamped to 0..255.
Missing neighbors use deterministic opaque white padding. Pixels are
written directly; surface alpha blending, color keys, and destination clipping
do not affect the calculation. Unlike pygame's raw in-place loop, aliased input
and output are handled from a pixel snapshot so each result uses original pixels."
  ;; Validate live resources and destination compatibility before allocating a
  ;; result. Pygame requires matching dimensions and bytes per pixel.
  (pixelisp.internal:ensure-live surface)
  (when destination (pixelisp.internal:ensure-live destination))
  (let* ((width (px.surface:width surface)) (height (px.surface:height surface))
         (created-p (null destination)))
    (when destination
      (unless (equal (px.surface:size destination) (list width height))
        (error "Destination Surface size differs from source."))
      (unless (= (px.surface:get-bytesize destination) (px.surface:get-bytesize surface))
        (error "Source and destination Surfaces need the same pixel byte size.")))
    (let ((result (or destination (%new-like surface width height)))
          (completed-p nil))
      (unwind-protect
           (prog1
               (let ((pixels (make-array (list height width))))
                 ;; This snapshot makes even in-place filtering well-defined.
                 (dotimes (y height)
                   (dotimes (x width)
                     (setf (aref pixels y x) (px.surface:get-at surface (list x y)))))
                 (labels ((channel (x y accessor)
                            (if (and (<= 0 x) (< x width) (<= 0 y) (< y height))
                                (funcall accessor (aref pixels y x))
                                255))
                          (edge-channel (x y accessor)
                            (max 0 (min 255
                                        (- (* 8 (funcall accessor (aref pixels y x)))
                                           (loop for dy from -1 to 1 sum
                                             (loop for dx from -1 to 1
                                                   unless (and (zerop dx) (zerop dy))
                                                     sum (channel (+ x dx) (+ y dy) accessor))))))))
                   (dotimes (y height)
                     (dotimes (x width)
                       (pixelisp.internal:write-surface-pixel result (list x y)
                         (pixelisp:make-color
                          (edge-channel x y #'pixelisp:color-r)
                          (edge-channel x y #'pixelisp:color-g)
                          (edge-channel x y #'pixelisp:color-b)
                          (edge-channel x y #'pixelisp:color-a))))))
                 result)
             (setf completed-p t))
        (when (and created-p (not completed-p)) (px:dispose result))))))

(defun average-color (surface &key rect consider-alpha)
  "Return average RGBA channels in a rectangle, optionally weighting RGB by alpha."
  (let ((rect (if rect (pixelisp.rect:clip (px.surface:get-rect surface) (pixelisp.internal:as-rect rect))
                  (px.surface:get-rect surface)))
        (red 0) (green 0) (blue 0) (alpha 0) (weight 0) (count 0))
    (loop for y from (pixelisp:rect-y rect) below (+ (pixelisp:rect-y rect) (pixelisp:rect-height rect))
          do (loop for x from (pixelisp:rect-x rect) below (+ (pixelisp:rect-x rect) (pixelisp:rect-width rect))
                   for color = (px.surface:get-at surface (list x y))
                   for sample-weight = (if consider-alpha (pixelisp:color-a color) 1)
                   do (incf red (* sample-weight (pixelisp:color-r color)))
                      (incf green (* sample-weight (pixelisp:color-g color)))
                      (incf blue (* sample-weight (pixelisp:color-b color)))
                      (incf alpha (pixelisp:color-a color)) (incf weight sample-weight) (incf count)))
    (pixelisp:make-color (if (zerop weight) 0 (floor red weight))
                        (if (zerop weight) 0 (floor green weight))
                        (if (zerop weight) 0 (floor blue weight))
                        (if (zerop count) 0 (floor alpha count)))))

(defun threshold (destination source search-color &key (threshold '(0 0 0 255))
                        (set-color '(0 0 0 0)) (set-behavior 1) search-surface inverse)
  "Count pixels within a channel threshold, optionally replacing selected pixels.
SET-BEHAVIOR 0 only counts, 1 writes SET-COLOR, and 2 copies source pixels."
  (unless (member set-behavior '(0 1 2)) (error "SET-BEHAVIOR must be 0, 1, or 2."))
  (when (and (plusp set-behavior) (null destination)) (error "A destination Surface is required."))
  (dolist (other (remove nil (list destination search-surface)))
    (unless (equal (px.surface:size other) (px.surface:size source)) (error "Surface sizes differ.")))
  (let ((limits (multiple-value-list (pixelisp.internal:rgba threshold)))
        (search (unless search-surface (multiple-value-list (pixelisp.internal:rgba search-color))))
        (count 0))
    (dotimes (y (px.surface:height source) count)
      (dotimes (x (px.surface:width source))
        (let* ((color (px.surface:get-at source (list x y)))
               (channels (multiple-value-list (pixelisp.internal:rgba color)))
               (target (if search-surface
                           (multiple-value-list (pixelisp.internal:rgba (px.surface:get-at search-surface (list x y))))
                           search))
               (matches (every (lambda (a b limit) (<= (abs (- a b)) limit)) channels target limits)))
          (when matches (incf count))
          (when (and (plusp set-behavior) (if inverse matches (not matches)))
            (px.surface:set-at destination (list x y) (if (= set-behavior 2) color set-color))))))))

(in-package #:pixelisp.mask)

(defstruct (mask (:constructor %make-mask (width height bits))) width height bits)
(defun make-mask (size &key fill)
  "Create a one-bit collision mask. SIZE is (width height); FILL sets every bit."
  (multiple-value-bind (width height) (pixelisp.transform::%dimensions size)
    (%make-mask width height (make-array (list height width) :element-type 'bit :initial-element (if fill 1 0)))))
(defun width (mask) (mask-width mask))
(defun height (mask) (mask-height mask))
(defun get-size (mask) (list (width mask) (height mask)))
(defun get-rect (mask &rest anchor-args)
  "Return a Rect with MASK's size, positioned by pygame Rect anchor keywords.

Accepts compact or hyphenated point anchors and scalar X/LEFT, Y/TOP,
RIGHT/BOTTOM, and CENTER-X/CENTER-Y anchors. Values are validated before
positioning, and repeated anchors apply in order, with the last one winning."
  (unless (evenp (length anchor-args))
    (error "GET-RECT expects anchor/value keyword pairs: ~S." anchor-args))
  (let ((points nil)
        (r (pixelisp:make-rect 0 0 (width mask) (height mask))))
    ;; Match Surface:GET-RECT's keyword spellings and application order. Keep
    ;; parsing separate from mutation so bad input never returns a partial Rect.
    (loop for (keyword value) on anchor-args by #'cddr do
      (unless (keywordp keyword) (error "GET-RECT anchor must be a keyword: ~S." keyword))
      (let* ((anchor (case keyword
                       ((:topleft :top-left) :topleft)
                       ((:topright :top-right) :topright)
                       ((:bottomleft :bottom-left) :bottomleft)
                       ((:bottomright :bottom-right) :bottomright)
                       ((:midtop :mid-top) :midtop)
                       ((:midleft :mid-left) :midleft)
                       ((:midbottom :mid-bottom) :midbottom)
                       ((:midright :mid-right) :midright)
                       ((:x :left) :left)
                       ((:y :top) :top)
                       (:right :right)
                       (:bottom :bottom)
                       ((:center-x :centerx) :center-x)
                       ((:center-y :centery) :center-y)
                       (:center :center)
                       (otherwise (error "Unknown GET-RECT anchor keyword ~S." keyword))))
             (position (if (member anchor '(:left :top :right :bottom :center-x :center-y))
                           (progn (check-type value real) (truncate value))
                           (multiple-value-list (pixelisp.internal:pair value)))))
        (push (cons anchor position) points)))
    (dolist (entry (nreverse points) r)
      (let ((point (cdr entry)))
        (ecase (car entry)
          (:topleft (setf (px.rect:top-left r) point))
          (:topright (setf (px.rect:top-right r) point))
          (:bottomleft (setf (px.rect:bottom-left r) point))
          (:bottomright (setf (px.rect:bottom-right r) point))
          (:midtop (setf (px.rect:mid-top r) point))
          (:midleft (setf (px.rect:mid-left r) point))
          (:midbottom (setf (px.rect:mid-bottom r) point))
          (:midright (setf (px.rect:mid-right r) point))
          (:left (setf (px.rect:left r) point))
          (:top (setf (px.rect:top r) point))
          (:right (setf (px.rect:right r) point))
          (:bottom (setf (px.rect:bottom r) point))
          (:center-x (setf (px.rect:center-x r) point))
          (:center-y (setf (px.rect:center-y r) point))
          (:center (setf (px.rect:center r) point)))))))
(defun copy (mask)
  "Return an independent mask with the same bits."
  (let ((result (make-mask (get-size mask)))) (bit-ior (mask-bits mask) (mask-bits mask) (mask-bits result)) result))
(defun %position (mask position)
  (multiple-value-bind (x y) (pixelisp.internal:pair position)
    (unless (and (integerp x) (integerp y) (<= 0 x) (< x (width mask)) (<= 0 y) (< y (height mask)))
      (error "Mask position ~S is outside ~S." position (get-size mask)))
    (values x y)))
(defun get-at (mask position)
  "Return 0 or 1 at POSITION; signal an error outside the mask."
  (multiple-value-bind (x y) (%position mask position) (aref (mask-bits mask) y x)))
(defun set-at (mask position &optional (value 1))
  "Set one collision bit; VALUE must be 0 or 1."
  (check-type value bit)
  (multiple-value-bind (x y) (%position mask position) (setf (aref (mask-bits mask) y x) value)) value)
(defun count (mask)
  "Count set collision bits."
  (loop for index below (array-total-size (mask-bits mask)) sum (row-major-aref (mask-bits mask) index)))
(defun fill (mask) "Set all collision bits."
  (dotimes (index (array-total-size (mask-bits mask))) (setf (row-major-aref (mask-bits mask) index) 1)) mask)
(defun clear (mask) "Clear all collision bits."
  (dotimes (index (array-total-size (mask-bits mask))) (setf (row-major-aref (mask-bits mask) index) 0)) mask)
(defun invert (mask) "Invert every collision bit in place."
  (bit-not (mask-bits mask) (mask-bits mask)) mask)
(defun from-surface (surface &key (threshold 127))
  "Build collision bits from a color key, or alpha strictly greater than THRESHOLD."
  (let* ((result (make-mask (px.surface:size surface)))
         (key (px.surface::%native-colorkey surface)))
    (dotimes (y (height result) result)
      (dotimes (x (width result))
        (let ((color (px.surface:get-at surface (list x y))))
          (when (if key
                    (not (px.surface::%colorkey-pixel-p
                           surface (px.surface:get-at-mapped surface (list x y)) key))
                    (> (pixelisp:color-a color) threshold))
            (setf (aref (mask-bits result) y x) 1)))))))
(defun from-threshold (surface color &key (threshold '(0 0 0 255)) other-surface)
  "Set bits whose RGBA channels are within THRESHOLD of COLOR or OTHER-SURFACE."
  (when (and other-surface (not (equal (px.surface:size surface) (px.surface:size other-surface))))
    (error "Threshold surfaces must have equal sizes."))
  (let ((result (make-mask (px.surface:size surface)))
        (limits (multiple-value-list (pixelisp.internal:rgba threshold)))
        (reference (unless other-surface (multiple-value-list (pixelisp.internal:rgba color)))))
    (dotimes (y (height result) result)
      (dotimes (x (width result))
        (let ((actual (multiple-value-list (pixelisp.internal:rgba (px.surface:get-at surface (list x y)))))
              (expected (if other-surface
                            (multiple-value-list (pixelisp.internal:rgba (px.surface:get-at other-surface (list x y))))
                            reference)))
          (when (every (lambda (a b limit) (<= (abs (- a b)) limit)) actual expected limits)
            (setf (aref (mask-bits result) y x) 1)))))))

(defmacro %overlapping-pixels ((first second offset x y other-x other-y) &body body)
  (let ((dx (gensym "DX")) (dy (gensym "DY")))
    `(multiple-value-bind (,dx ,dy) (pixelisp.internal:pair ,offset)
       (setf ,dx (truncate ,dx) ,dy (truncate ,dy))
       (loop for ,y from (max 0 ,dy) below (min (height ,first) (+ ,dy (height ,second)))
             for ,other-y = (- ,y ,dy)
             do (loop for ,x from (max 0 ,dx) below (min (width ,first) (+ ,dx (width ,second)))
                      for ,other-x = (- ,x ,dx) do (progn ,@body))))))
(defun overlap (first second offset)
  "Return the first overlapping point in FIRST's coordinates, or NIL."
  (%overlapping-pixels (first second offset x y other-x other-y)
    (when (and (= 1 (aref (mask-bits first) y x)) (= 1 (aref (mask-bits second) other-y other-x)))
      (return-from overlap (list x y)))))
(defun overlap-area (first second offset)
  "Count overlapping set bits after translating SECOND by OFFSET."
  (let ((count 0))
    (%overlapping-pixels (first second offset x y other-x other-y)
      (when (and (= 1 (aref (mask-bits first) y x)) (= 1 (aref (mask-bits second) other-y other-x))) (incf count))) count))
(defun overlap-mask (first second offset)
  "Return a mask the size of FIRST containing only overlapping bits."
  (let ((result (make-mask (get-size first))))
    (%overlapping-pixels (first second offset x y other-x other-y)
      (setf (aref (mask-bits result) y x)
            (logand (aref (mask-bits first) y x) (aref (mask-bits second) other-y other-x)))) result))
(defun draw (destination source offset)
  "OR translated SOURCE bits into DESTINATION, clipping outside pixels."
  (%overlapping-pixels (destination source offset x y source-x source-y)
    (setf (aref (mask-bits destination) y x)
          (logior (aref (mask-bits destination) y x) (aref (mask-bits source) source-y source-x)))) destination)
(defun erase (destination source offset)
  "Clear DESTINATION bits covered by translated SOURCE set bits."
  (%overlapping-pixels (destination source offset x y source-x source-y)
    (when (= 1 (aref (mask-bits source) source-y source-x)) (setf (aref (mask-bits destination) y x) 0))) destination)
(defun scale (mask size)
  "Return a nearest-neighbor resize of MASK."
  (let ((result (make-mask size)))
    (when (and (plusp (width mask)) (plusp (height mask)))
      (dotimes (y (height result))
        (dotimes (x (width result))
          (setf (aref (mask-bits result) y x)
                (aref (mask-bits mask) (floor (* y (height mask)) (height result))
                      (floor (* x (width mask)) (width result))))))) result))
(defun centroid (mask)
  "Return the integer center of mass of set bits; empty masks return (0 0)."
  (let ((sum-x 0) (sum-y 0) (count 0))
    (dotimes (y (height mask)) (dotimes (x (width mask))
      (when (= 1 (aref (mask-bits mask) y x)) (incf sum-x x) (incf sum-y y) (incf count))))
    (if (zerop count) '(0 0) (list (floor sum-x count) (floor sum-y count)))))
(defun angle (mask)
  "Return the principal axis angle of the set pixels in degrees."
  (let ((sum-x 0) (sum-y 0) (sum-xx 0) (sum-yy 0) (sum-xy 0) (pixels 0))
    (dotimes (y (height mask)) (dotimes (x (width mask))
      (when (= 1 (aref (mask-bits mask) y x))
        (incf sum-x x) (incf sum-y y)
        (incf sum-xx (* x x)) (incf sum-yy (* y y)) (incf sum-xy (* x y))
        (incf pixels))))
    (if (zerop pixels) 0
        ;; Center covariance algebraically. Using CENTROID's integer result
        ;; here biases the principal axis for asymmetric shapes.
        (let ((xx (- sum-xx (/ (* sum-x sum-x) pixels)))
              (yy (- sum-yy (/ (* sum-y sum-y) pixels)))
              (xy (- sum-xy (/ (* sum-x sum-y) pixels))))
          (if (and (= xx yy) (zerop xy)) 0
              (* -1/2 (/ 180 pi) (atan (* 2 xy) (- xx yy))))))))

(defun %set-p (mask x y)
  (and (<= 0 x) (< x (width mask)) (<= 0 y) (< y (height mask))
       (= 1 (aref (mask-bits mask) y x))))
(defun %component-points (mask start visited)
  "Flood-fill eight-connected bits with an explicit stack instead of recursion."
  (let ((stack (list start)) (result nil))
    (setf (aref visited (second start) (first start)) 1)
    (loop while stack do
      (destructuring-bind (x y) (pop stack)
        (push (list x y) result)
        (loop for dy from -1 to 1 do
          (loop for dx from -1 to 1
                for nx = (+ x dx) for ny = (+ y dy)
                when (and (%set-p mask nx ny) (zerop (aref visited ny nx)))
                  do (setf (aref visited ny nx) 1) (push (list nx ny) stack))))) result))
(defun connected-components (mask &optional (minimum 0))
  "Return independent eight-connected masks with at least MINIMUM set pixels."
  (let ((visited (make-array (list (height mask) (width mask)) :element-type 'bit :initial-element 0))
        (results nil))
    (dotimes (y (height mask))
      (dotimes (x (width mask))
        (when (and (%set-p mask x y) (zerop (aref visited y x)))
          (let ((points (%component-points mask (list x y) visited)))
            (when (>= (length points) minimum)
              (let ((component (make-mask (get-size mask))))
                (dolist (point points) (set-at component point)) (push component results)))))))
    (nreverse results)))
(defun connected-component (mask &optional position)
  "Return the component containing POSITION, or the largest component if omitted."
  (if position
      (multiple-value-bind (x y) (%position mask position)
        (let ((result (make-mask (get-size mask))))
          (when (%set-p mask x y)
            (dolist (point (%component-points mask (list x y)
                              (make-array (list (height mask) (width mask)) :element-type 'bit :initial-element 0)))
              (set-at result point))) result))
      (or (first (stable-sort (connected-components mask) #'> :key #'count)) (make-mask (get-size mask)))))
(defun get-bounding-rects (mask)
  "Return one tight bounding rectangle for each connected component."
  (mapcar (lambda (component)
            (let ((left (width mask)) (right -1) (top (height mask)) (bottom -1))
              (dotimes (y (height mask)) (dotimes (x (width mask))
                (when (%set-p component x y)
                  (setf left (min left x) right (max right x) top (min top y) bottom (max bottom y)))))
              (pixelisp:make-rect left top (1+ (- right left)) (1+ (- bottom top)))))
          (connected-components mask)))
(defun outline (mask &optional (every 1))
  "Trace the first component's outer boundary, keeping every Nth boundary sample."
  (unless (and (integerp every) (plusp every)) (error "Outline sampling must be a positive integer."))
  (let ((start (loop for y below (height mask)
                    thereis (loop for x below (width mask) when (%set-p mask x y) return (list x y)))))
    (unless start (return-from outline nil))
    (let* ((directions #((1 0) (1 1) (0 1) (-1 1) (-1 0) (-1 -1) (0 -1) (1 -1)))
           (current start) (backtrack 4) (first-next nil) (points (list start)))
      (loop repeat (* 8 (max 1 (count mask))) do
        (let ((next nil) (direction nil))
          (loop for step from 1 to 8
                for index = (mod (+ backtrack step) 8)
                for offset = (aref directions index)
                for x = (+ (first current) (first offset))
                for y = (+ (second current) (second offset))
                when (%set-p mask x y) do (setf next (list x y) direction index) (return))
          (unless next (return))
          (when (and first-next (equal current start) (equal next first-next)) (return))
          (unless first-next (setf first-next next))
          (setf current next backtrack (mod (+ direction 5) 8))
          (unless (equal current start) (push current points))))
      (loop for point in (nreverse points) for index from 0 when (zerop (mod index every)) collect point))))
(defun convolve (first second &optional destination (offset '(0 0)))
  "Return positions where SECOND overlaps FIRST; useful for configuration-space collision."
  (let* ((expected (list (max 0 (1- (+ (width first) (width second))))
                         (max 0 (1- (+ (height first) (height second))))))
         (result (or destination (make-mask expected)))
         (offset-pair (multiple-value-list (pixelisp.internal:pair offset)))
         (offset-x (first offset-pair)) (offset-y (second offset-pair)))
    (unless (equal expected (get-size result))
      (error "Convolution destination must have size ~S." expected))
    (dotimes (y (height result) result)
      (dotimes (x (width result))
        (when (overlap first second (list (- x (1- (width second)) offset-x)
                                         (- y (1- (height second)) offset-y)))
          (set-at result (list x y)))))))
(setf (fdefinition 'pixelisp:make-mask) #'make-mask)

(in-package #:pixelisp.gfxdraw)

;;; These functions preserve pygame.gfxdraw's color-last argument order while
;;; sharing the tested Surface rasterizers above.
(defun pixel (surface x y color) "Set one pixel and return its affected Rect."
  (px.draw:line surface color (list x y) (list x y)))
(defun hline (surface x1 x2 y color) (px.draw:line surface color (list x1 y) (list x2 y)))
(defun vline (surface x y1 y2 color) (px.draw:line surface color (list x y1) (list x y2)))
(defun rectangle (surface x1 y1 x2 y2 color)
  (px.draw:rect surface color (pixelisp:make-rect (min x1 x2) (min y1 y2) (1+ (abs (- x2 x1))) (1+ (abs (- y2 y1)))) :width 1))
(defun box (surface x1 y1 x2 y2 color)
  (px.draw:rect surface color (pixelisp:make-rect (min x1 x2) (min y1 y2) (1+ (abs (- x2 x1))) (1+ (abs (- y2 y1))))))
(defun line (surface x1 y1 x2 y2 color) (px.draw:line surface color (list x1 y1) (list x2 y2)))
(defun aaline (surface x1 y1 x2 y2 color) (px.draw:aaline surface color (list x1 y1) (list x2 y2)))
(defun circle (surface x y radius color) (px.draw:circle surface color (list x y) radius :width 1))
(defun aacircle (surface x y radius color)
  (%aa-ellipse surface x y radius radius color))
(defun filled-circle (surface x y radius color) (px.draw:circle surface color (list x y) radius))
(defun ellipse (surface x y radius-x radius-y color)
  (px.draw:ellipse surface color (pixelisp:make-rect (- x radius-x) (- y radius-y) (* 2 radius-x) (* 2 radius-y)) :width 1))
(defun aaellipse (surface x y radius-x radius-y color) (%aa-ellipse surface x y radius-x radius-y color))
(defun filled-ellipse (surface x y radius-x radius-y color)
  (px.draw:ellipse surface color (pixelisp:make-rect (- x radius-x) (- y radius-y) (* 2 radius-x) (* 2 radius-y))))
(defun %aa-ellipse (surface x y radius-x radius-y color)
  (let* ((steps (max 12 (ceiling (* 2 pi (max radius-x radius-y)))))
         (points (loop for index below steps for angle = (* 2 pi (/ index steps))
                       collect (list (+ x (* radius-x (cos angle))) (+ y (* radius-y (sin angle)))))))
    (px.draw:aalines surface color t points)))
(defun arc (surface x y radius start end color)
  (px.draw:arc surface color (pixelisp:make-rect (- x radius) (- y radius) (* 2 radius) (* 2 radius))
               (* start (/ pi 180)) (* end (/ pi 180))))
(defun pie (surface x y radius start end color)
  (let* ((span (mod (- end start) 360))
         (points (cons (list x y)
                       (loop for index from 0 to (max 1 (ceiling span))
                             for degrees = (+ start (* span (/ index (max 1 (ceiling span)))))
                             for angle = (* degrees (/ pi 180))
                             collect (list (+ x (* radius (cos angle))) (- y (* radius (sin angle))))))))
    (px.draw:polygon surface color points :width 1)))
(defun trigon (surface x1 y1 x2 y2 x3 y3 color)
  (px.draw:polygon surface color (list (list x1 y1) (list x2 y2) (list x3 y3)) :width 1))
(defun aatrigon (surface x1 y1 x2 y2 x3 y3 color)
  (px.draw:aalines surface color t (list (list x1 y1) (list x2 y2) (list x3 y3))))
(defun filled-trigon (surface x1 y1 x2 y2 x3 y3 color)
  (px.draw:polygon surface color (list (list x1 y1) (list x2 y2) (list x3 y3))))
(defun polygon (surface points color) (px.draw:polygon surface color points :width 1))
(defun aapolygon (surface points color) (px.draw:aalines surface color t points))
(defun filled-polygon (surface points color) (px.draw:polygon surface color points))
(defun textured-polygon (surface points texture offset-x offset-y)
  "Fill a polygon by repeating TEXTURE with the requested texture origin."
  (when (or (zerop (px.surface:width texture)) (zerop (px.surface:height texture)))
    (error "A texture must have positive dimensions."))
  (let ((coverage (px.surface:make-surface (px.surface:size surface) :alpha t)))
    (unwind-protect
         (let ((damage (px.draw:polygon coverage '(255 255 255 255) points)))
           (loop for y from (pixelisp:rect-y damage) below (+ (pixelisp:rect-y damage) (pixelisp:rect-height damage))
                 do (loop for x from (pixelisp:rect-x damage) below (+ (pixelisp:rect-x damage) (pixelisp:rect-width damage))
                          when (plusp (pixelisp:color-a (px.surface:get-at coverage (list x y))))
                            do (px.surface:set-at surface (list x y)
                                  (px.surface:get-at texture
                                    (list (mod (- x offset-x) (px.surface:width texture))
                                          (mod (- y offset-y) (px.surface:height texture)))))))
           damage)
      (pixelisp:dispose coverage))))
(defun bezier (surface points steps color)
  "Draw a Bezier curve through control POINTS using de Casteljau interpolation."
  (unless (and (integerp steps) (>= steps 2)) (error "Bezier STEPS must be at least two."))
  (let ((control (map 'list #'pixelisp.draw::%point points)))
    (unless (>= (length control) 3) (error "A Bezier curve needs at least three control points."))
    (px.draw:lines surface color nil
      (loop for index from 0 to steps for amount = (/ index steps)
            collect (loop with level = control while (cdr level)
                          do (setf level (loop for (first second) on level while second
                                               collect (list (+ (* (- 1 amount) (first first)) (* amount (first second)))
                                                             (+ (* (- 1 amount) (second first)) (* amount (second second))))))
                          finally (return (first level)))))))
