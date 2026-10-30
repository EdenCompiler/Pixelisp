;;;; Read the small, conventional XBM subset used for bitmap cursors.
;;;; This file only decodes data; it deliberately never initializes SDL.
(in-package #:pixelisp.cursors)

(defun %xbm-error (message)
  (error 'pixelisp:error :operation 'load-xbm :message message))

(defun %read-xbm-source (source)
  "Read a pathname or borrowed character stream as text; never close a caller stream."
  (cond
    ((streamp source)
     (multiple-value-bind (character-stream-p certain-p)
         (subtypep (stream-element-type source) 'character)
       (unless (and character-stream-p certain-p)
         (%xbm-error "XBM input streams must be character streams.")))
     (with-output-to-string (out)
       (loop for line = (read-line source nil nil) while line do
         (write-line line out))))
    ((or (pathnamep source) (stringp source))
     (with-open-file (in source :direction :input :external-format :ascii)
       (with-output-to-string (out)
         (loop for line = (read-line in nil nil) while line do
           (write-line line out)))))
    (t (error 'type-error :datum source :expected-type '(or pathname string stream)))))

(defun %strip-c-comments (text)
  "Remove C comments while preserving newlines and token boundaries."
  (with-output-to-string (out)
    (let ((i 0) (n (length text)))
      (loop while (< i n) do
        (cond
          ((and (< (1+ i) n) (char= (char text i) #\/) (char= (char text (1+ i)) #\/))
           (incf i 2)
           (loop while (and (< i n) (char/= (char text i) #\Newline)) do (incf i))
           (when (< i n) (write-char #\Newline out) (incf i)))
          ((and (< (1+ i) n) (char= (char text i) #\/) (char= (char text (1+ i)) #\*))
           (incf i 2)
           (let ((closed nil))
             (loop while (< i n) do
               (if (and (< (1+ i) n) (char= (char text i) #\*)
                        (char= (char text (1+ i)) #\/))
                   (progn (setf closed t) (incf i 2) (return))
                   (progn
                     (when (char= (char text i) #\Newline) (write-char #\Newline out))
                     (incf i))))
             (unless closed
               (%xbm-error "XBM contains an unterminated C comment.")))
           (write-char #\Space out))
          (t (write-char (char text i) out) (incf i)))))))

(defun %words (line)
  (loop with start = nil for i from 0 to (length line)
        for separator-p = (or (= i (length line)) (find (char line i) '(#\Space #\Tab #\Return)))
        when (and start separator-p) collect (subseq line start i) and do (setf start nil)
        when (and (null start) (not separator-p)) do (setf start i)))

(defun %c-integer (token)
  "Parse a C-style decimal, octal, or hexadecimal integer literal."
  (let* ((end (position-if (lambda (ch) (find ch "uUlL")) token))
         (number (subseq token 0 end))
         (suffix (and end (subseq token end)))
         (hex-p (and (> (length number) 2) (string-equal "0x" number :end2 2)))
         (octal-p (and (not hex-p) (> (length number) 1)
                       (char= (char number 0) #\0)))
         (start (if hex-p 2 0))
         (radix (cond (hex-p 16) (octal-p 8) (t 10))))
    (unless (> (length number) start) (%xbm-error "Malformed integer in XBM declaration."))
    (when (and suffix
               (not (member (string-upcase suffix)
                            '("U" "L" "LL" "UL" "ULL" "LU" "LLU")
                            :test #'string=)))
      (%xbm-error "Malformed integer suffix in XBM declaration."))
    (handler-case (parse-integer number :start start :radix radix :junk-allowed nil)
      (error () (%xbm-error "Malformed integer in XBM declaration.")))))

(defun %macro-name-suffix-p (name suffix)
  (let ((n (length name)) (m (length suffix)))
    (and (> n m) (string= suffix name :start2 (- n m)))))

(defun %xbm-metadata (text)
  (let ((width nil) (height nil) (hot-x nil) (hot-y nil))
    (with-input-from-string (in text)
      (loop for line = (read-line in nil nil) while line do
        (let ((words (%words (string-trim '(#\Space #\Tab #\Return) line))))
          (when (and (>= (length words) 3) (string= (first words) "#define"))
            (let* ((name (second words))
                   (target (cond ((%macro-name-suffix-p name "_width") 'width)
                                 ((%macro-name-suffix-p name "_height") 'height)
                                 ((%macro-name-suffix-p name "_x_hot") 'hot-x)
                                 ((%macro-name-suffix-p name "_y_hot") 'hot-y))))
              (when target
                (let ((value (%c-integer (third words))))
                  (case target
                    (width (setf width value))
                    (height (setf height value))
                    (hot-x (setf hot-x value))
                    (hot-y (setf hot-y value))))))))))
    (unless (and (integerp width) (<= 1 width #x7fffffff)
                 (integerp height) (<= 1 height #x7fffffff))
      (%xbm-error "XBM must declare positive width and height."))
    (when (or (and hot-x (null hot-y)) (and hot-y (null hot-x)))
      (%xbm-error "XBM hotspot declarations must provide both x_hot and y_hot."))
    (let ((x (or hot-x 0)) (y (or hot-y 0)))
      (unless (and (<= 0 x) (< x width) (<= 0 y) (< y height))
        (%xbm-error "XBM hotspot lies outside the declared dimensions."))
      (values width height (list x y)))))

(defun %xbm-initializer-values (text)
  "Extract byte literals from the first static char initializer."
  (let* ((start (search "static" text :test #'char-equal))
         (open (and start (position #\{ text :start start)))
         (close (and open (position #\} text :start open))))
    (unless (and start open close)
      (%xbm-error "XBM has no static char bit initializer."))
    (let ((declaration (subseq text start open)))
      (unless (and (member "static" (%words declaration) :test #'string-equal)
                   (member "char" (%words declaration) :test #'string-equal))
        (%xbm-error "XBM bit initializer must be a static char array.")))
    (let ((body (subseq text (1+ open) close)) (values nil) (token-start nil))
      (labels ((finish-token (end)
                 (when token-start
                   (let ((token (subseq body token-start end)))
                     (unless (zerop (length token))
                       (let ((value (%c-integer token)))
                         (unless (<= 0 value 255)
                           (%xbm-error "XBM initializer values must be bytes."))
                         (push value values))))
                   (setf token-start nil))))
        (loop for i from 0 to (length body) do
          (if (or (= i (length body))
                  (find (char body i) '(#\Space #\Tab #\Return #\Newline #\,)))
              (finish-token i)
              (unless token-start (setf token-start i))))
        (nreverse values)))))

(defun %reverse-byte-bits (byte)
  "Reverse XBM's least-significant-bit-first order for SDL's bitmap cursor."
  (loop with result = 0 for bit below 8 do
    (when (logbitp bit byte) (setf result (logior result (ash 1 (- 7 bit)))))
    finally (return result)))

(defun %parse-xbm (source)
  (let* ((text (%strip-c-comments (%read-xbm-source source))))
    (multiple-value-bind (width height hotspot) (%xbm-metadata text)
      ;; SDL's bitmap cursor takes a tightly packed row stride of width/8.
      ;; XBM can also pad rows of non-byte-aligned images, which SDL cannot use.
      (unless (zerop (mod width 8))
        (%xbm-error "Bitmap cursor width must be divisible by eight."))
      (let* ((expected (* height (/ width 8)))
             (bytes (%xbm-initializer-values text)))
        (when (> expected array-total-size-limit)
          (%xbm-error "XBM dimensions exceed the supported cursor size."))
        (unless (= (length bytes) expected)
          (%xbm-error "XBM initializer byte count does not match its dimensions."))
        (values (list width height) hotspot
                (map '(vector (unsigned-byte 8)) #'%reverse-byte-bits bytes))))))

(defun load-xbm (cursor-source &optional mask-source)
  "Decode XBM text without initializing SDL.

Return four values: (width height), (hot-x hot-y), SDL-ready data octets,
and mask octets. Sources may be pathnames, path strings, or borrowed
character streams. An omitted mask makes every pixel opaque."
  (multiple-value-bind (size hotspot data) (%parse-xbm cursor-source)
    (let ((mask
            (if mask-source
                (multiple-value-bind (mask-size ignored mask-data) (%parse-xbm mask-source)
                  (declare (ignore ignored))
                  (unless (equal size mask-size)
                    (%xbm-error "Cursor and mask XBM dimensions must match."))
                  mask-data)
                (make-array (length data) :element-type '(unsigned-byte 8)
                                         :initial-element #xff))))
      (values size hotspot data mask))))
