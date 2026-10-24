;;;; Additional pygame-style rectangle operations.
;;;; These routines use only Pixelisp's integer rectangles, so this file is
;;;; safe to load in command-line tools without initializing SDL.
(in-package #:pixelisp.rect)

(defun update-rect (r &rest values)
  "Replace R's four values after validating all inputs.

Accept four coordinates, one rectangle or four-value sequence, or two
coordinate pairs. Values are truncated to integers like MAKE-RECT."
  (let* ((coordinates
           (case (cl:length values)
             (4 values)
             (1 (let ((value (first values)))
                  (if (typep value 'pixelisp:rect)
                      (list (x value) (y value) (width value) (height value))
                      (progn
                        (unless (typep value 'sequence)
                          (error 'type-error :datum value
                                 :expected-type '(or pixelisp:rect sequence)))
                        (coerce value 'list)))))
             (2 (multiple-value-bind (x y) (pixelisp.internal:pair (first values))
                  (multiple-value-bind (width height) (pixelisp.internal:pair (second values))
                    (list x y width height))))
             (otherwise (error "UPDATE-RECT expects four values, one rectangle/sequence, or two pairs."))))
         (new-values (progn
                       (unless (= 4 (cl:length coordinates))
                         (error "A rectangle needs four values."))
                       (unless (every #'realp coordinates)
                         (error "Rectangle values must be real numbers."))
                       (mapcar #'truncate coordinates))))
    (setf (x r) (first new-values)
          (y r) (second new-values)
          (width r) (third new-values)
          (height r) (fourth new-values)))
  r)

(defun center-x (r)
  "Return the integer horizontal center of R."
  (+ (x r) (floor (width r) 2)))
(defun (setf center-x) (value r)
  "Move R horizontally so its center is VALUE, truncating VALUE first."
  (let ((new-x (- (truncate value) (floor (width r) 2))))
    (setf (x r) new-x))
  value)
(defun center-y (r)
  "Return the integer vertical center of R."
  (+ (y r) (floor (height r) 2)))
(defun (setf center-y) (value r)
  "Move R vertically so its center is VALUE, truncating VALUE first."
  (let ((new-y (- (truncate value) (floor (height r) 2))))
    (setf (y r) new-y))
  value)

(defun clamp-ip (r outer)
  "Move R inside OUTER in place, returning R."
  (let ((result (clamp r outer)))
    (setf (x r) (x result) (y r) (y result)))
  r)

(defun union-ip (r other)
  "Expand R to cover OTHER, returning R."
  (let ((result (union r other)))
    (setf (x r) (x result) (y r) (y result)
          (width r) (width result) (height r) (height result)))
  r)

(defun union-all-ip (r rectangles)
  "Expand R to cover every rectangle in RECTANGLES, returning R.
Validate the full sequence before changing R, so a bad element is atomic."
  (let ((result (union-all r rectangles)))
    (setf (x r) (x result) (y r) (y result)
          (width r) (width result) (height r) (height result)))
  r)

(defun scale-by-ip (r factor-x &optional (factor-y nil factor-y-p))
  "Scale R around its integer center in place; negative factors use magnitudes.
Pass one scalar for uniform scaling, two scalars for separate axes, or a
two-value sequence as FACTOR-X. Dimensions and origins are truncated like
pygame. As in pygame, a zero second factor selects the first factor."
  ;; A pair can be supplied as the single factor argument. Check its shape
  ;; before reading either value or changing the rectangle.
  (when (and (typep factor-x 'sequence) (not factor-y-p))
    (multiple-value-setq (factor-x factor-y) (pixelisp.internal:pair factor-x))
    (setf factor-y-p t))
  ;; Validate both factors before changing any slot.
  (check-type factor-x real)
  (let ((factor-y (if factor-y-p factor-y factor-x)))
    (check-type factor-y real)
    ;; pygame truncates each half-size in this order. Keeping these steps
    ;; explicit matters for odd dimensions, including when a factor is one.
    (let* ((fx (abs factor-x))
           (fy (let ((magnitude (abs factor-y))) (if (zerop magnitude) fx magnitude)))
           (old-x (x r)) (old-y (y r)) (old-w (width r)) (old-h (height r))
           (new-x (truncate (- (+ old-x (truncate old-w 2)) (/ (* old-w fx) 2))))
           (new-y (truncate (- (+ old-y (truncate old-h 2)) (/ (* old-h fy) 2))))
           (new-w (truncate (* old-w fx)))
           (new-h (truncate (* old-h fy))))
      (setf (x r) new-x (y r) new-y (width r) new-w (height r) new-h)))
  r)

(defun scale-by (r factor-x &optional (factor-y nil factor-y-p))
  "Return a centered copy of R scaled by one factor, a pair, or two factors."
  (when factor-y-p
    (return-from scale-by (scale-by-ip (copy r) factor-x factor-y)))
  (scale-by-ip (copy r) factor-x))

(defun collide-objects (r objects &key (key #'identity))
  "Return the first object whose KEY-produced rectangle collides with R."
  (loop for object across (coerce objects 'vector)
        for rectangle = (funcall key object)
        when (collide-rect r rectangle) do (return object)))

(defun collide-objects-all (r objects &key (key #'identity))
  "Return all objects whose KEY-produced rectangles collide with R."
  (loop for object across (coerce objects 'vector)
        when (collide-rect r (funcall key object)) collect object))

(defun collide-dict (r table &key (use-values nil))
  "Return the first colliding hash-table entry as a (key . value) cons.
By default keys are rectangles; with USE-VALUES, values are rectangles."
  (check-type table hash-table)
  (block found
    (maphash (lambda (key value)
               (when (collide-rect r (if use-values value key))
                 (return-from found (cons key value))))
             table)
    nil))

(defun collide-dict-all (r table &key (use-values nil))
  "Return colliding hash-table entries as (key . value) conses.
The order is the order in which TABLE's hash traversal visits its entries."
  (check-type table hash-table)
  (let (matches)
    (maphash (lambda (key value)
               (when (collide-rect r (if use-values value key))
                 (push (cons key value) matches)))
             table)
    (nreverse matches)))
