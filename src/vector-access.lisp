;;;; Indexed component access and swizzling for native-independent vectors.

(in-package #:pixelisp.math)

(defun %vector-dimension (value)
  (typecase value
    (vector2 2)
    (vector3 3)
    (t (error 'type-error :datum value :expected-type '(or vector2 vector3)))))

(defun %component-index (value index)
  "Validate INDEX and return its zero-based position, accepting negatives."
  (unless (integerp index)
    (error 'type-error :datum index :expected-type 'integer))
  (check-type index integer)
  (let* ((dimension (%vector-dimension value))
         (normalized (if (minusp index) (+ dimension index) index)))
    (unless (and (<= 0 normalized) (< normalized dimension))
      (error 'type-error :datum index :expected-type `(integer ,(- dimension) ,(1- dimension))))
    normalized))

(defun component (value index)
  "Return VALUE's component at zero-based INDEX; negative indices count from the end."
  (let ((position (%component-index value index)))
    (case position
      (0 (x value))
      (1 (y value))
      (2 (z value)))))

(defun (setf component) (number value index)
  "Set VALUE's component at INDEX, accepting negative indices, and return NUMBER."
  (unless (realp number)
    (error 'type-error :datum number :expected-type 'real))
  (case (%component-index value index)
    (0 (setf (x value) number))
    (1 (setf (y value) number))
    (2 (setf (z value) number)))
  number)

(defun %parse-swizzle (value pattern)
  (unless (stringp pattern)
    (error 'type-error :datum pattern :expected-type 'string))
  (when (zerop (cl:length pattern))
    (error "A swizzle pattern cannot be empty."))
  (let ((dimension (%vector-dimension value)))
    (let ((selectors
            (map 'list
                 (lambda (selector)
                   (cond ((char= selector #\0) (cons :constant 0))
                         ((char= selector #\1) (cons :constant 1))
                         (t (let ((position (position selector "xyz")))
                              (unless (and position (< position dimension))
                                (error "Invalid ~D-dimensional vector swizzle selector: ~S"
                                       dimension selector))
                              (cons :component position)))))
                 pattern)))
      ;; Pygame's vector swizzle constants are available alongside coordinates,
      ;; but an all-constant pattern is not a valid vector swizzle.
      (unless (some (lambda (selector) (eq (car selector) :component)) selectors)
        (error "A swizzle pattern must select at least one vector component."))
      selectors)))

(defun swizzle (value pattern)
  "Read x/y/z selectors and embedded 0/1 constants from VALUE.

A one-character pattern returns a number; longer patterns return a fresh list.
Repeated selectors and constants are allowed for reads, but a pattern must
contain at least one vector component."
  (let ((selected (mapcar (lambda (selector)
                            (if (eq (car selector) :constant)
                                (cdr selector)
                                (component value (cdr selector))))
                          (%parse-swizzle value pattern))))
    (if (= 1 (cl:length selected)) (first selected) selected)))

(defun (setf swizzle) (new-value value pattern)
  "Set components selected by PATTERN, validating everything before mutation.

NEW-VALUE may be a real number for a one-character pattern or a sequence of
real numbers with one value per selector. Repeated destinations are rejected
because a single component cannot have multiple simultaneous assigned values."
  (let* ((selectors (%parse-swizzle value pattern))
         (indices (progn
                    (when (some (lambda (selector) (eq (car selector) :constant)) selectors)
                      (error "A writable swizzle cannot contain constants."))
                    (mapcar #'cdr selectors)))
         (count (cl:length indices))
         (values (if (realp new-value)
                     (if (= count 1) (list new-value)
                         (error "A scalar can only be assigned to a one-component swizzle."))
                     (progn
                       (unless (and (typep new-value 'sequence)
                                    (= count (cl:length new-value)))
                         (error "A swizzle assignment needs ~D component values." count))
                       (coerce new-value 'list)))))
    (unless (= count (cl:length (remove-duplicates indices)))
      (error "A writable swizzle cannot select a component more than once."))
    (unless (every #'realp values)
      (error "Swizzle values must all be real numbers."))
    ;; All potentially failing checks precede the first write.
    (loop for index in indices
          for number in values
          do (setf (component value index) number))
    new-value))
