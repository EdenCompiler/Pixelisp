;;;; Color-space helpers for Pixelisp's 8-bit RGBA Color values.
;;;; The scaled HSV/HSL fields follow pygame's public Color convention:
;;;; hue is in degrees and the other fields are percentages.
(in-package #:pixelisp.color)

(defun %parse-hex (text start)
  "Parse six/eight hexadecimal digits, rejecting signs and partial numbers."
  (let* ((digits (- (length text) start))
         (valid (and (member digits '(6 8))
                     (loop for index from start below (length text)
                           always (digit-char-p (char text index) 16)))))
    (unless valid (error "Expected six or eight hexadecimal color digits: ~S." text))
    (let ((value (parse-integer text :start start :radix 16)))
      (when (= digits 6) (setf value (logior (ash value 8) 255)))
      (apply #'make-color (loop for shift in '(24 16 8 0) collect (ldb (byte 8 shift) value))))))

(defun parse (value)
  "Return a fresh Color from a color, RGB(A) sequence, name, hex string, or RRGGBBAA integer."
  (etypecase value
    (pixelisp:color (multiple-value-call #'make-color (pixelisp.internal:rgba value)))
    (string
     (cond ((and (plusp (length value)) (char= (char value 0) #\#)) (%parse-hex value 1))
           ((and (>= (length value) 2) (string= value "0x" :end1 2)) (%parse-hex value 2))
           (t (let ((channels (pixelisp.colordict:lookup value)))
                (unless channels (error "Unknown color name: ~S." value))
                (apply #'make-color channels)))))
    (integer
     (check-type value (unsigned-byte 32))
     (apply #'make-color (loop for shift in '(24 16 8 0) collect (ldb (byte 8 shift) value))))
    (sequence (multiple-value-call #'make-color (pixelisp.internal:rgba value)))))

(defun to-integer (value)
  "Return canonical #xRRGGBBAA, independent of any surface's native pixel layout."
  (let ((color (parse value)))
    (logior (ash (r color) 24) (ash (g color) 16) (ash (b color) 8) (a color))))

(defun update-color (color &rest values)
  "Replace COLOR after validation. Three numeric channels preserve its current alpha.
A single color value replaces all RGBA channels, including default alpha 255."
  (check-type color pixelisp:color)
  (let ((replacement
          (case (length values)
            (1 (parse (first values)))
            (3 (apply #'make-color (append values (list (a color)))))
            (4 (apply #'make-color values))
            (otherwise (error "Provide one color value, or three/four channels.")))))
    ;; Construct first, then mutate: invalid input never leaves half a color.
    (setf (r color) (r replacement) (g color) (g replacement)
          (b color) (b replacement) (a color) (a replacement)))
  color)

(defun grayscale (value)
  "Return a luminance-weighted grayscale Color, preserving alpha."
  (let* ((color (parse value))
         (gray (floor (+ (* 0.299d0 (r color)) (* 0.587d0 (g color)) (* 0.114d0 (b color))))))
    (make-color gray gray gray (a color))))

(defun premul-alpha (value)
  "Return a Color with RGB multiplied by pixel alpha, retaining alpha."
  (let* ((color (parse value)) (alpha (a color)))
    (apply #'make-color
           (append (mapcar (lambda (channel) (floor (* (1+ channel) alpha) 256))
                           (list (r color) (g color) (b color)))
                   (list alpha)))))

(defun %components (value field &key alpha)
  "Read a 3- or 4-value property input and validate its numeric range."
  (unless (and (typep value 'sequence)
               (if alpha (member (length value) '(3 4)) (= (length value) 3)))
    (error "~A expects ~:[three~;three or four~] values, got ~S."
           field alpha value))
  (let ((values (loop for i below (length value) collect (elt value i))))
    (unless (every #'realp values)
      (error "~A values must be real numbers, got ~S." field value))
    values))

(defun %check-range (values ranges field)
  (unless (every (lambda (value range) (<= (first range) value (second range)))
                 values ranges)
    (error "Invalid ~A value: ~S." field values))
  values)

(defun %unit-channel (value)
  "Convert a normalized channel into an 8-bit integer, rounding like pygame."
  (max 0 (min 255 (round (* 255 value)))))

(defun %property-channel (value)
  "Convert a normalized HSV/HSL/CMY channel using pygame's truncation rule."
  (max 0 (min 255 (floor (* 255 value)))))

(defun %rgb-to-hsv (red green blue)
  "Return normalized hue, saturation, and value for normalized RGB channels."
  (let* ((high (max red green blue))
         (low (min red green blue))
         (delta (- high low))
         (hue (cond ((zerop delta) 0)
                    ((= high red) (mod (/ (- green blue) delta) 6))
                    ((= high green) (+ (/ (- blue red) delta) 2))
                    (t (+ (/ (- red green) delta) 4))))
         (saturation (if (zerop high) 0 (/ delta high))))
    (values (/ hue 6) saturation high)))

(defun %hsv-to-rgb (hue saturation value)
  "Convert normalized HSV values into three normalized RGB channels."
  (let* ((h (* 6 (mod hue 1)))
         (sector (floor h))
         (fraction (- h sector))
         (p (* value (- 1 saturation)))
         (q (* value (- 1 (* saturation fraction))))
         (r (* value (- 1 (* saturation (- 1 fraction))))))
    (case (mod sector 6)
      (0 (values value r p))
      (1 (values q value p))
      (2 (values p value r))
      (3 (values p q value))
      (4 (values r p value))
      (otherwise (values value p q)))))

(defun %rgb-to-hsl (red green blue)
  "Return normalized hue, saturation, and lightness for normalized RGB."
  (let* ((high (max red green blue))
         (low (min red green blue))
         (delta (- high low))
         (lightness (/ (+ high low) 2))
         (hue (cond ((zerop delta) 0)
                    ((= high red) (mod (/ (- green blue) delta) 6))
                    ((= high green) (+ (/ (- blue red) delta) 2))
                    (t (+ (/ (- red green) delta) 4))))
         (saturation (if (zerop delta) 0
                         (/ delta (- 1 (abs (- (* 2 lightness) 1)))))))
    (values (/ hue 6) saturation lightness)))

(defun %hsl-to-rgb (hue saturation lightness)
  "Convert normalized HSL values into normalized RGB channels."
  (let* ((chroma (* (- 1 (abs (- (* 2 lightness) 1))) saturation))
         (h (* 6 (mod hue 1)))
         (x (* chroma (- 1 (abs (- (mod h 2) 1)))))
         (m (- lightness (/ chroma 2))))
    (multiple-value-bind (red green blue)
        (case (floor h)
          (0 (values chroma x 0))
          (1 (values x chroma 0))
          (2 (values 0 chroma x))
          (3 (values 0 x chroma))
          (4 (values x 0 chroma))
          (otherwise (values chroma 0 x)))
      (values (+ red m) (+ green m) (+ blue m)))))

(defun hsva (color)
  "Return COLOR as (hue saturation value alpha), with degrees/percentages."
  (multiple-value-bind (hue saturation value)
      (%rgb-to-hsv (/ (r color) 255) (/ (g color) 255) (/ (b color) 255))
    (list (* hue 360) (* saturation 100) (* value 100) (* (/ (a color) 255) 100))))

(defun (setf hsva) (input color)
  "Set COLOR from three or four HSV percentages, preserving omitted alpha."
  (let* ((parts (%components input "HSVA" :alpha t))
         (hue (first parts)) (saturation (second parts))
         (value (third parts)) (alpha (fourth parts)))
    (%check-range (subseq parts 0 3) '((0 360) (0 100) (0 100)) "HSVA")
    (when alpha (%check-range (list alpha) '((0 100)) "HSVA"))
    (multiple-value-bind (red green blue)
        (%hsv-to-rgb (/ hue 360) (/ saturation 100) (/ value 100))
      (setf (r color) (%property-channel red)
            (g color) (%property-channel green)
            (b color) (%property-channel blue)
            (a color) (if alpha (%property-channel (/ alpha 100)) (a color))))
    input))

(defun hsla (color)
  "Return COLOR as (hue saturation lightness alpha), in degrees/percentages."
  (multiple-value-bind (hue saturation lightness)
      (%rgb-to-hsl (/ (r color) 255) (/ (g color) 255) (/ (b color) 255))
    (list (* hue 360) (* saturation 100) (* lightness 100) (* (/ (a color) 255) 100))))

(defun (setf hsla) (input color)
  "Set COLOR from three or four HSL percentages, preserving omitted alpha."
  (let* ((parts (%components input "HSLA" :alpha t))
         (hue (first parts)) (saturation (second parts))
         (lightness (third parts)) (alpha (fourth parts)))
    (%check-range (subseq parts 0 3) '((0 360) (0 100) (0 100)) "HSLA")
    (when alpha (%check-range (list alpha) '((0 100)) "HSLA"))
    (multiple-value-bind (red green blue)
        (%hsl-to-rgb (/ hue 360) (/ saturation 100) (/ lightness 100))
      (setf (r color) (%property-channel red)
            (g color) (%property-channel green)
            (b color) (%property-channel blue)
            (a color) (if alpha (%property-channel (/ alpha 100)) (a color))))
    input))

(defun cmy (color)
  "Return normalized cyan, magenta, and yellow components for COLOR."
  (list (- 1 (/ (r color) 255))
        (- 1 (/ (g color) 255))
        (- 1 (/ (b color) 255))))

(defun (setf cmy) (input color)
  "Set COLOR from normalized CMY values, leaving alpha unchanged."
  (let ((parts (%components input "CMY")))
    (%check-range parts '((0 1) (0 1) (0 1)) "CMY")
    (setf (r color) (%property-channel (- 1 (first parts)))
          (g color) (%property-channel (- 1 (second parts)))
          (b color) (%property-channel (- 1 (third parts))))
    input))

(defun correct-gamma (color gamma)
  "Return a fresh COLOR with every RGBA channel raised to GAMMA."
  (check-type gamma real)
  (flet ((correct (channel)
           ;; Nonpositive exponents saturate every channel at white. Handle
           ;; that before EXPT: a large negative exponent could overflow even
           ;; though its final, clamped octet is already known to be 255.
           (cond ((not (plusp gamma)) 255)
                 ((zerop channel) 0)
                 (t (%unit-channel (expt (/ channel 255) gamma))))))
    (make-color (correct (r color)) (correct (g color))
                (correct (b color)) (correct (a color)))))

(defun %rgba-binary (left right operation)
  "Apply OPERATION independently to two colors and clamp each result to 0..255.

Parsing both inputs makes the public helpers accept the same color formats as
PARSE. Constructing a new Color keeps the operands untouched."
  (let ((left-color (parse left))
        (right-color (parse right)))
    (flet ((channel (x y)
             (max 0 (min 255 (funcall operation x y)))))
      (make-color (channel (r left-color) (r right-color))
                  (channel (g left-color) (g right-color))
                  (channel (b left-color) (b right-color))
                  (channel (a left-color) (a right-color))))))

(defun add (left right)
  "Add matching RGBA channels with saturation at 255; return a fresh Color."
  (%rgba-binary left right #'+))

(defun subtract (left right)
  "Subtract matching RGBA channels with saturation at 0; return a fresh Color."
  (%rgba-binary left right #'-))

(defun multiply (left right)
  "Multiply matching RGBA channels with saturation at 255; return a fresh Color."
  (%rgba-binary left right #'*))

(defun floor-divide (left right)
  "Floor-divide matching RGBA channels; a zero divisor channel produces 0."
  (%rgba-binary left right (lambda (x y) (if (zerop y) 0 (floor x y)))))

(defun modulo (left right)
  "Take matching RGBA channel remainders; a zero divisor channel produces 0."
  (%rgba-binary left right (lambda (x y) (if (zerop y) 0 (mod x y)))))

(defun invert (value)
  "Return a fresh Color with each RGBA channel replaced by 255 minus itself."
  (let ((color (parse value)))
    (make-color (- 255 (r color)) (- 255 (g color))
                (- 255 (b color)) (- 255 (a color)))))

(defun i1i2i3 (color)
  "Return normalized I1I2I3 components for COLOR.

I1 is the average intensity (R+G+B)/3. I2 is the red/blue difference
(R-B)/2, and I3 contrasts green with red and blue (-R+2G-B)/4. Each
RGB channel is first normalized to 0..1; the resulting ranges are I1 in
0..1 and I2/I3 in -0.5..0.5. Alpha does not participate."
  (let ((red (/ (r color) 255))
        (green (/ (g color) 255))
        (blue (/ (b color) 255)))
    (list (/ (+ red green blue) 3)
          (/ (- red blue) 2)
          (/ (+ (- red) (* 2 green) (- blue)) 4))))

(defun (setf i1i2i3) (input color)
  "Set COLOR from three normalized I1I2I3 values, preserving its alpha.

Validate all components and ranges before calculating or changing any channel.
The inverse transform is R=I1+I2-2I3/3, G=I1+4I3/3, and
B=I1-I2-2I3/3. RGB results use pygame's property conversion rule: multiply
by 255 and truncate down to an 8-bit channel."
  (let ((parts (%components input "I1I2I3")))
    (%check-range parts '((0 1) (-0.5 0.5) (-0.5 0.5)) "I1I2I3")
    (let* ((i1 (first parts))
           (i2 (second parts))
           (i3 (third parts))
           (red (%property-channel (+ i1 i2 (- (* 2/3 i3)))))
           (green (%property-channel (+ i1 (* 4/3 i3))))
           (blue (%property-channel (+ i1 (- i2) (- (* 2/3 i3))))))
      (setf (r color) red
            (g color) green
            (b color) blue))
    input))
