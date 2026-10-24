;;;; Small, native-independent vector values.
;;;;
;;;; Arithmetic returns a new vector. Functions ending in -IP deliberately mutate
;;;; their first argument, which makes allocation choices visible in game loops.
;;;; Vectors accept ordinary Lisp lists/arrays at API boundaries; their X/Y/Z
;;;; accessors support SETF for convenient interactive development.

(defpackage #:pixelisp.math
  (:nicknames #:px.math)
  (:use #:cl)
  (:shadow #:length)
  (:export #:vector2 #:vector3 #:make-vector2 #:make-vector3 #:vector2-p #:vector3-p
           #:x #:y #:z #:components #:add #:subtract #:multiply #:divide #:dot #:cross
           #:length #:length-squared #:normalize #:normalize-ip #:is-normalized-p
           #:distance-to #:distance-squared-to #:lerp #:slerp #:rotate #:rotate-ip
           #:scale-to-length #:update-vector #:rotate-rad #:rotate-rad-ip
           #:move-towards #:move-towards-ip
           #:rotate-x #:rotate-y #:rotate-z #:angle-to #:reflect #:reflect-ip
           #:project #:clamp-magnitude #:clamp-magnitude-ip #:copy-vector
           #:rotate-x-ip #:rotate-y-ip #:rotate-z-ip
           #:rotate-x-rad #:rotate-y-rad #:rotate-z-rad
           #:rotate-x-rad-ip #:rotate-y-rad-ip #:rotate-z-rad-ip #:clamp
           #:as-polar #:from-polar #:as-spherical #:from-spherical #:round-vector))

(in-package #:pixelisp.math)

(defstruct (vector2 (:constructor %make-vector2 (x y))) (x 0 :type real) (y 0 :type real))
(defstruct (vector3 (:constructor %make-vector3 (x y z)))
  (x 0 :type real) (y 0 :type real) (z 0 :type real))

(defmethod pixelisp.internal:pair ((value vector2))
  "Allow Vector2 values wherever an API accepts a coordinate pair."
  (values (vector2-x value) (vector2-y value)))

(defun components (value)
  "Return a fresh list of vector components. Lists and arrays are also accepted."
  (typecase value
    (vector2 (list (vector2-x value) (vector2-y value)))
    (vector3 (list (vector3-x value) (vector3-y value) (vector3-z value)))
    (sequence (coerce value 'list))
    (t (error 'type-error :datum value :expected-type '(or vector2 vector3 sequence)))))

(defun make-vector2 (&optional (first 0) (second nil second-p))
  "Construct a Vector2 from two numbers, a sequence, another vector, or one repeated number."
  (if (realp first)
      (%make-vector2 first (if second-p second first))
      (let ((values (components first)))
        (unless (= 2 (cl:length values)) (error "A Vector2 needs two components."))
        (apply #'%make-vector2 values))))

(defun make-vector3 (&optional (first 0) (second nil second-p) (third nil third-p))
  "Construct a Vector3 from three numbers, a sequence, another vector, or one repeated number."
  (cond ((not (realp first))
         (let ((values (components first)))
           (unless (= 3 (cl:length values)) (error "A Vector3 needs three components."))
           (apply #'%make-vector3 values)))
        ((and second-p third-p) (%make-vector3 first second third))
        ((or second-p third-p) (error "A Vector3 needs either one or three numbers."))
        (t (%make-vector3 first first first))))

(defun x (value) "Return VALUE's x component." (etypecase value (vector2 (vector2-x value)) (vector3 (vector3-x value))))
(defun y (value) "Return VALUE's y component." (etypecase value (vector2 (vector2-y value)) (vector3 (vector3-y value))))
(defun z (value) "Return a Vector3's z component." (vector3-z value))
(defun (setf x) (number value)
  (etypecase value (vector2 (setf (vector2-x value) number)) (vector3 (setf (vector3-x value) number))))
(defun (setf y) (number value)
  (etypecase value (vector2 (setf (vector2-y value) number)) (vector3 (setf (vector3-y value) number))))
(defun (setf z) (number value) (setf (vector3-z value) number))

(defun %new (components)
  (ecase (cl:length components) (2 (apply #'%make-vector2 components))
    (3 (apply #'%make-vector3 components))))
(defun copy-vector (value) (%new (components value)))
(defun %binary (function first second)
  ;; Scalars expand to every component. Sequence operands must match dimensions.
  (let* ((a (components first))
         (b (if (realp second) (make-list (cl:length a) :initial-element second) (components second))))
    (unless (= (cl:length a) (cl:length b)) (error "Vector dimensions differ."))
    (%new (mapcar function a b))))
(defun %assign (target source)
  (setf (x target) (x source) (y target) (y source))
  (when (vector3-p target) (setf (z target) (z source))) target)
(defun add (first second) "Return the component-wise sum; a scalar SECOND is broadcast." (%binary #'+ first second))
(defun subtract (first second) "Return FIRST minus SECOND component-wise." (%binary #'- first second))
(defun multiply (first second) "Return the component-wise product; a scalar SECOND is broadcast." (%binary #'* first second))
(defun divide (first second) "Return FIRST divided component-wise by SECOND." (%binary #'/ first second))
(defun dot (first second)
  "Return the dot product of equal-dimension vectors."
  (let ((a (components first)) (b (components second)))
    (unless (= (cl:length a) (cl:length b)) (error "Vector dimensions differ."))
    (reduce #'+ (mapcar #'* a b))))
(defun cross (first second)
  "Return the scalar 2D cross product or vector 3D cross product."
  (let ((a (components first)) (b (components second)))
    (unless (= (cl:length a) (cl:length b)) (error "Vector dimensions differ."))
    (ecase (cl:length a)
      (2 (- (* (first a) (second b)) (* (second a) (first b))))
      (3 (%make-vector3 (- (* (second a) (third b)) (* (third a) (second b)))
                       (- (* (third a) (first b)) (* (first a) (third b)))
                       (- (* (first a) (second b)) (* (second a) (first b))))))))
(defun length-squared (value) "Return the squared Euclidean magnitude of VALUE." (dot value value))
(defun length (value) "Return the Euclidean magnitude of VALUE." (sqrt (length-squared value)))
(defun normalize (value)
  "Return a unit vector pointing in VALUE's direction; zero vectors signal an error."
  (let ((magnitude (length value)))
    (when (zerop magnitude) (error "Cannot normalize a zero vector."))
    (divide value magnitude)))
(defun normalize-ip (value) "Normalize VALUE in place and return it." (%assign value (normalize value)))
(defun scale-to-length (value target-length)
  "Scale VALUE in place to TARGET-LENGTH and return VALUE.

A zero vector cannot be scaled to a nonzero length. A negative target length
reverses the vector, matching pygame's Vector2/Vector3 behavior."
  (let ((magnitude (length value)))
    (when (and (zerop magnitude) (not (zerop target-length)))
      (error "Cannot scale a zero vector to a nonzero length."))
    (%assign value (if (zerop magnitude) (copy-vector value)
                       (multiply value (/ target-length magnitude))))))
(defun update-vector (value &rest new-components)
  "Replace VALUE's components and return it, preserving its Vector2/Vector3 dimension.

Accept either separate component arguments or one sequence/vector. A single
number is broadcast to every component, as in pygame's vector update method.
All inputs are validated before VALUE is changed."
  (let* ((dimension (cl:length (components value)))
         (parts (if (and (= (cl:length new-components) 1)
                         (not (realp (first new-components))))
                    (components (first new-components))
                    (if (and (= (cl:length new-components) 1)
                             (realp (first new-components)))
                        (make-list dimension :initial-element (first new-components))
                        new-components))))
    (unless (= dimension (cl:length parts)) (error "Vector dimensions differ."))
    (unless (every #'realp parts) (error "Vector components must be real numbers."))
    (%assign value (%new parts))))
(defun is-normalized-p (value &optional (epsilon 1d-6)) "Test whether VALUE has unit length within EPSILON." (< (abs (- (length-squared value) 1)) epsilon))
(defun distance-squared-to (first second) "Return squared distance between FIRST and SECOND." (length-squared (subtract first second)))
(defun distance-to (first second) "Return Euclidean distance between FIRST and SECOND." (sqrt (distance-squared-to first second)))
(defun move-towards (value target max-distance)
  "Return VALUE moved toward TARGET by at most MAX-DISTANCE.

When MAX-DISTANCE is negative, move away from TARGET by that distance. A zero
distance between the inputs has no direction, so a fresh copy of VALUE is returned."
  (let* ((delta (subtract target value))
         (distance (length delta)))
    (cond ((zerop distance) (copy-vector value))
          ((and (>= max-distance 0) (<= distance max-distance)) (copy-vector target))
          (t (add value (multiply delta (/ max-distance distance)))))))
(defun move-towards-ip (value target max-distance)
  "Move VALUE toward TARGET by at most MAX-DISTANCE, mutating and returning VALUE."
  (%assign value (move-towards value target max-distance)))
(defun %check-lerp-amount (amount)
  (unless (and (realp amount) (<= 0 amount 1))
    (error "Interpolation amount must be between zero and one.")))

(defun lerp (first second amount)
  "Interpolate two real numbers or vectors; AMOUNT must be in [0,1]."
  (%check-lerp-amount amount)
  (if (and (realp first) (realp second))
      (+ first (* (- second first) amount))
      (add first (multiply (subtract second first) amount))))

(defun %round-away-from-zero (value)
  ;; Pygame's vector rounding uses C-style nearest rounding for exact halves.
  (multiple-value-bind (integer remainder) (truncate value)
    (if (>= (abs remainder) 0.5d0)
        (+ integer (if (minusp value) -1 1))
        integer)))

(defun round-vector (value &optional (digits 0))
  "Return a new Vector2 or Vector3 rounded to DIGITS decimal places.

DIGITS may be negative to round to tens, hundreds, and so on. Exact halfway
values round away from zero, matching pygame Vector2/Vector3."
  (check-type digits integer)
  (let* ((scale (float (expt 10 (abs digits)) 1d0))
         (round-component
           (if (minusp digits)
               (lambda (component)
                 (* scale (%round-away-from-zero (/ (float component 1d0) scale))))
               (lambda (component)
                 (/ (%round-away-from-zero (* (float component 1d0) scale)) scale)))))
    (%new (mapcar (lambda (component)
                    ;; pygame vectors store floating-point components, even when
                    ;; rounding produces a whole number.
                    (float (funcall round-component component) 1d0))
                  (components value)))))
(defun slerp (first second amount)
  "Interpolate directions on the unit sphere while linearly interpolating magnitudes."
  (unless (<= 0 amount 1) (error "Interpolation amount must be between zero and one."))
  (let* ((a (normalize first)) (b (normalize second))
         (cosine (max -1d0 (min 1d0 (dot a b)))))
    (when (< cosine -0.999999d0) (error "Spherical interpolation is ambiguous for opposite vectors."))
    (let* ((angle (acos cosine)) (sine (sin angle))
           (direction (if (< (abs sine) 1d-8) a
                          (add (multiply a (/ (sin (* (- 1 amount) angle)) sine))
                               (multiply b (/ (sin (* amount angle)) sine))))))
      (multiply direction (+ (* (- 1 amount) (length first)) (* amount (length second)))))))
(defun %radians (degrees) (* degrees (/ pi 180)))
(defun rotate (value degrees &optional axis)
  "Return a counterclockwise rotation in degrees. Vector3 rotation accepts an AXIS."
  (let* ((angle (%radians degrees)) (cosine (cos angle)) (sine (sin angle)))
    (etypecase value
      (vector2 (%make-vector2 (- (* (x value) cosine) (* (y value) sine))
                              (+ (* (x value) sine) (* (y value) cosine))))
      (vector3
       ;; Rodrigues' formula works for an arbitrary axis after normalizing it.
       (let ((unit (normalize (or axis (%make-vector3 0 0 1)))))
         (add (add (multiply value cosine) (multiply (cross unit value) sine))
              (multiply unit (* (dot unit value) (- 1 cosine)))))))))
(defun rotate-ip (value degrees &optional axis) "Rotate VALUE in place and return it." (%assign value (rotate value degrees axis)))
(defun rotate-rad (value radians &optional axis)
  "Return VALUE rotated by RADIANS; Vector3 accepts an optional AXIS."
  (rotate value (* radians (/ 180 pi)) axis))
(defun rotate-rad-ip (value radians &optional axis)
  "Rotate VALUE in place by RADIANS and return VALUE. Vector3 accepts AXIS."
  (%assign value (rotate-rad value radians axis)))
(defun rotate-x (value degrees) (rotate value degrees (%make-vector3 1 0 0)))
(defun rotate-y (value degrees) (rotate value degrees (%make-vector3 0 1 0)))
(defun rotate-z (value degrees) (rotate value degrees (%make-vector3 0 0 1)))
(defun rotate-x-ip (value degrees) "Rotate a Vector3 around X in degrees, in place." (%assign value (rotate-x value degrees)))
(defun rotate-y-ip (value degrees) "Rotate a Vector3 around Y in degrees, in place." (%assign value (rotate-y value degrees)))
(defun rotate-z-ip (value degrees) "Rotate a Vector3 around Z in degrees, in place." (%assign value (rotate-z value degrees)))
(defun rotate-x-rad (value radians) "Return VALUE rotated around X by RADIANS." (rotate-x value (* radians (/ 180 pi))))
(defun rotate-y-rad (value radians) "Return VALUE rotated around Y by RADIANS." (rotate-y value (* radians (/ 180 pi))))
(defun rotate-z-rad (value radians) "Return VALUE rotated around Z by RADIANS." (rotate-z value (* radians (/ 180 pi))))
(defun rotate-x-rad-ip (value radians) "Rotate VALUE around X by RADIANS in place." (%assign value (rotate-x-rad value radians)))
(defun rotate-y-rad-ip (value radians) "Rotate VALUE around Y by RADIANS in place." (%assign value (rotate-y-rad value radians)))
(defun rotate-z-rad-ip (value radians) "Rotate VALUE around Z by RADIANS in place." (%assign value (rotate-z-rad value radians)))
(defun clamp (value minimum maximum)
  "Clamp scalar VALUE to MINIMUM and MAXIMUM, testing the lower bound first."
  (unless (and (realp value) (realp minimum) (realp maximum))
    (error "CLAMP expects real numbers."))
  ;; Preserve pygame's comparison order even for reversed bounds. Sorting the
  ;; bounds would silently change its result for callers that supply them so.
  (cond ((< value minimum) minimum)
        ((> value maximum) maximum)
        (t value)))
(defun angle-to (first second)
  "Return the signed 2D angle, or unsigned 3D angle, from FIRST to SECOND in degrees."
  (if (and (vector2-p first) (vector2-p second))
      (progn (when (or (zerop (length-squared first)) (zerop (length-squared second)))
               (error "A zero vector has no angle."))
             (* (/ 180 pi) (atan (cross first second) (dot first second))))
      (* (/ 180 pi) (acos (max -1d0 (min 1d0 (dot (normalize first) (normalize second))))))))
(defun reflect (value normal)
  "Reflect VALUE across a surface whose normal is NORMAL. NORMAL need not have unit length."
  (let ((unit (normalize normal))) (subtract value (multiply unit (* 2 (dot value unit))))))
(defun reflect-ip (value normal) (%assign value (reflect value normal)))
(defun project (value other)
  "Return the component of VALUE parallel to OTHER."
  (when (zerop (length-squared other)) (error "Cannot project onto a zero vector."))
  (multiply other (/ (dot value other) (length-squared other))))
(defun clamp-magnitude (value maximum &optional (minimum 0))
  "Return a vector whose magnitude lies between MINIMUM and MAXIMUM."
  (unless (<= 0 minimum maximum) (error "Invalid magnitude bounds."))
  (let ((magnitude (length value)))
    (cond ((zerop magnitude) (if (zerop minimum) (copy-vector value)
                                (error "Cannot grow a zero vector to a positive magnitude.")))
          (t (multiply value (/ (max minimum (min maximum magnitude)) magnitude))))))
(defun clamp-magnitude-ip (value maximum &optional (minimum 0))
  (%assign value (clamp-magnitude value maximum minimum)))
(defun as-polar (value) "Return VALUE's radius and angle in degrees as two values." (values (length value) (* (/ 180 pi) (atan (y value) (x value)))))
(defun from-polar (radius degrees)
  (%make-vector2 (* radius (cos (%radians degrees))) (* radius (sin (%radians degrees)))))
(defun as-spherical (value)
  "Return 3D radius, inclination, and azimuth in degrees as three values."
  (let ((radius (length value)))
    (values radius (if (zerop radius) 0 (* (/ 180 pi) (acos (/ (z value) radius))))
            (* (/ 180 pi) (atan (y value) (x value))))))
(defun from-spherical (radius theta phi)
  (let ((theta (%radians theta)) (phi (%radians phi)))
    (%make-vector3 (* radius (sin theta) (cos phi)) (* radius (sin theta) (sin phi))
                   (* radius (cos theta)))))

(setf (fdefinition 'pixelisp:make-vector2) #'make-vector2
      (fdefinition 'pixelisp:make-vector3) #'make-vector3)
