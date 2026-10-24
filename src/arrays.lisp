;;;; Native pixel memory is strided and foreign, so portable Lisp arrays are
;;;; copies. BUFFER-VIEW is the explicit, scoped alternative for shared access.
(defpackage #:pixelisp.surfarray
  (:use #:cl) (:nicknames #:px.surfarray)
  (:export #:array2d #:array3d #:array-alpha #:array-red #:array-green #:array-blue
           #:array-colorkey #:pixels2d #:pixels3d #:pixels-alpha #:pixels-red
           #:pixels-green #:pixels-blue #:make-surface #:blit-array #:map-array
           #:get-arraytype #:get-arraytypes #:use-arraytype))
(defpackage #:pixelisp.pixelcopy
  (:use #:cl) (:nicknames #:px.pixelcopy)
  (:export #:surface-to-array #:array-to-surface #:map-array #:make-surface))
(defpackage #:pixelisp.pixelarray
  (:use #:cl) (:nicknames #:px.pixelarray) (:shadow #:close #:replace)
  (:export #:make-pixel-array #:pixel-array #:ref #:close #:slice #:make-surface
           #:replace #:extract #:compare #:transpose #:with-pixel-array))

(in-package #:pixelisp.surfarray)
(defun %packed-ref (surface x y)
  (cffi:mem-ref (px.surface::pixel-pointer surface x y) :uint32))
(defun %set-packed (surface x y value)
  (check-type value (unsigned-byte 32))
  (setf (cffi:mem-ref (px.surface::pixel-pointer surface x y) :uint32) value))
(defun %channel-byte-offset (surface channel)
  "Find the channel byte in its actual native format, including host byte order."
  (let* ((format (pixelisp.internal:%ptr (sdl2:surface-format (pixelisp.internal:surface-handle surface))))
         (channels (make-list 4 :initial-element 0)))
    (setf (nth (position channel '(:red :green :blue :alpha)) channels) 255)
    (cffi:with-foreign-object (pixel :uint32)
      (setf (cffi:mem-ref pixel :uint32) (apply #'pixelisp.internal::%map-rgba format channels))
      (loop for offset below 4 when (= 255 (cffi:mem-aref pixel :uint8 offset)) return offset))))
(defun %pixel-view (surface channel)
  "Hold one surface lock until the returned view is closed."
  (px.surface:lock surface)
  (handler-case
      (let* ((width (px.surface:width surface)) (height (px.surface:height surface))
             (rgb (eq channel :rgb)) (packed (eq channel :packed))
             (offsets (unless packed
                        (mapcar (lambda (component) (%channel-byte-offset surface component))
                                (if rgb '(:red :green :blue) (list channel)))))
             (pitch (sdl2:surface-pitch (pixelisp.internal:surface-handle surface)))
             (component-stride (when (and rgb (not (some #'null offsets)))
                                 (- (second offsets) (first offsets)))))
        (when (or (and (not packed) (some #'null offsets))
                  (and rgb (/= component-stride (- (third offsets) (second offsets)))))
          (error 'pixelisp:unsupported-feature :operation 'pixels
                 :message "This surface has no shared byte channel for the requested view."))
        (px.buffer:make-view
         :owner surface :dimensions (if rgb (list width height 3) (list width height))
         :strides (if rgb (list 4 pitch component-stride) (list 4 pitch))
         :byte-offset (if packed 0 (first offsets))
         :element-type (if packed '(unsigned-byte 32) '(unsigned-byte 8))
         :reader (lambda (x y &optional component)
                   (if packed (%packed-ref surface x y)
                       (cffi:mem-ref (cffi:inc-pointer (px.surface::pixel-pointer surface x y)
                                                       (nth (if rgb component 0) offsets)) :uint8)))
         :writer (lambda (value x y &optional component)
                   (if packed (%set-packed surface x y value)
                       (progn
                         (check-type value (unsigned-byte 8))
                         ;; Shared array access addresses storage directly. A
                         ;; surface's drawing clip must not suppress raw writes.
                         (setf (cffi:mem-ref (cffi:inc-pointer (px.surface::pixel-pointer surface x y)
                                                              (nth (if rgb component 0) offsets)) :uint8)
                               value))))
         :releaser (lambda () (px.surface:unlock surface))))
    (error (condition) (px.surface:unlock surface) (error condition))))
(defun pixels2d (surface) "Share packed pixels in X/Y order." (%pixel-view surface :packed))
(defun pixels3d (surface) "Share RGB channels in X/Y/channel order." (%pixel-view surface :rgb))
(defun pixels-alpha (surface) (%pixel-view surface :alpha))
(defun pixels-red (surface) (%pixel-view surface :red))
(defun pixels-green (surface) (%pixel-view surface :green))
(defun pixels-blue (surface) (%pixel-view surface :blue))
(defun %copy-view (view)
  (unwind-protect (px.buffer:to-array view) (px.buffer:close view)))
(defun array2d (surface) "Copy packed pixels into a specialized two-dimensional array." (%copy-view (pixels2d surface)))
(defun array3d (surface) "Copy RGB channels into a specialized three-dimensional array." (%copy-view (pixels3d surface)))
(defun array-alpha (surface)
  "Copy alpha values, returning 255 throughout an opaque surface."
  (pixelisp.internal:ensure-live surface)
  (if (px.surface:alpha-p surface) (%copy-view (pixels-alpha surface))
      (make-array (list (px.surface:width surface) (px.surface:height surface))
                  :element-type '(unsigned-byte 8) :initial-element 255)))
(defun array-red (surface) (%copy-view (pixels-red surface)))
(defun array-green (surface) (%copy-view (pixels-green surface)))
(defun array-blue (surface) (%copy-view (pixels-blue surface)))
(defun array-colorkey (surface)
  (let* ((width (px.surface:width surface)) (height (px.surface:height surface))
         (result (make-array (list width height) :element-type '(unsigned-byte 8)))
         (key (px.surface:get-colorkey surface)))
    (dotimes (x width result)
      (dotimes (y height)
        (setf (aref result x y)
              (if (and key (equal (subseq (px.color:to-list key) 0 3)
                                         (subseq (px.color:to-list (px.surface:get-at surface (list x y))) 0 3))) 0 255))))))
(defun blit-array (surface array)
  "Copy packed pixels or RGB(A) channel arrays into SURFACE."
  (unless (and (member (array-rank array) '(2 3))
               (= (array-dimension array 0) (px.surface:width surface))
               (= (array-dimension array 1) (px.surface:height surface))
               (or (= (array-rank array) 2) (member (array-dimension array 2) '(3 4))))
    (error "Expected an array with dimensions (width height [3 or 4])."))
  (px.surface:lock surface)
  (unwind-protect
       (dotimes (x (px.surface:width surface))
         (dotimes (y (px.surface:height surface))
           (if (= (array-rank array) 2)
               (%set-packed surface x y (aref array x y))
               (pixelisp.internal:write-surface-pixel surface (list x y)
                 (loop for c below (array-dimension array 2) collect (aref array x y c))))))
    (px.surface:unlock surface)) surface)
(defun make-surface (array)
  "Make a surface by copying a (width height [channels]) array."
  (unless (member (array-rank array) '(2 3)) (error "Expected a rank-2 or rank-3 pixel array."))
  (let ((surface (px.surface:make-surface (list (array-dimension array 0) (array-dimension array 1))
                                        :alpha (and (= (array-rank array) 3) (= (array-dimension array 2) 4)))))
    (handler-case (blit-array surface array)
      (error (condition) (pixelisp:dispose surface) (error condition)))))
(defun map-array (surface array)
  "Map RGB(A) channel values to SURFACE's packed pixel format without changing it."
  (unless (and (= (array-rank array) 3) (member (array-dimension array 2) '(3 4)))
    (error "Expected an RGB(A) channel array."))
  (let ((result (make-array (list (array-dimension array 0) (array-dimension array 1)) :element-type '(unsigned-byte 32)))
        (format (pixelisp.internal:%ptr (sdl2:surface-format (pixelisp.internal:surface-handle surface)))))
    (dotimes (x (array-dimension array 0) result)
      (dotimes (y (array-dimension array 1))
        (setf (aref result x y)
              (pixelisp.internal::%map-rgba format (aref array x y 0) (aref array x y 1)
                                           (aref array x y 2) (if (= (array-dimension array 2) 4) (aref array x y 3) 255)))))))
(defun get-arraytype () :common-lisp)
(defun get-arraytypes () '(:common-lisp))
(defun use-arraytype (type)
  (unless (eq type :common-lisp)
    (error 'pixelisp:unsupported-feature :operation 'use-arraytype :message "Pixelisp uses native Common Lisp arrays.")) type)

(in-package #:pixelisp.pixelcopy)
(defun surface-to-array (array surface &key (kind :pixels))
  "Copy into an existing array; KIND is :PIXELS, :ALPHA, :RED, :GREEN or :BLUE."
  (let ((source (ecase kind
                  (:pixels (if (= (array-rank array) 3) (px.surfarray:array3d surface) (px.surfarray:array2d surface)))
                  (:alpha (px.surfarray:array-alpha surface)) (:red (px.surfarray:array-red surface))
                  (:green (px.surfarray:array-green surface)) (:blue (px.surfarray:array-blue surface)))))
    (unless (equal (array-dimensions source) (array-dimensions array)) (error "Destination array dimensions do not match."))
    (dotimes (i (array-total-size array) array) (setf (row-major-aref array i) (row-major-aref source i)))))
(setf (fdefinition 'array-to-surface) #'px.surfarray:blit-array
      (fdefinition 'map-array) #'px.surfarray:map-array
      (fdefinition 'make-surface) #'px.surfarray:make-surface)

(in-package #:pixelisp.pixelarray)
(deftype pixel-array () 'px.buffer:buffer-view)
(defun make-pixel-array (surface) (px.surfarray:pixels2d surface))
(setf (fdefinition 'ref) #'px.buffer:view-ref
      (fdefinition '(setf ref)) (fdefinition '(setf px.buffer:view-ref))
      (fdefinition 'close) #'px.buffer:close
      (fdefinition 'slice) #'px.buffer:slice)
(defmacro with-pixel-array ((name surface) &body body)
  `(px.buffer:with-view (,name (make-pixel-array ,surface)) ,@body))
(defun %owner-surface (pixels)
  "Find the surface backing PIXELS, even when PIXELS is a dependent view."
  (let ((owner (px.buffer:owner pixels)))
    (loop while (typep owner 'px.buffer:buffer-view)
          do (setf owner (px.buffer:owner owner)))
    (unless (typep owner 'pixelisp.surface::surface)
      (error "Pixel array is not backed by a surface."))
    owner))
(defun %validate-pixel-array (pixels)
  ;; Do this before looking at dimensions: empty views still have live owners.
  (unless (typep pixels 'pixel-array)
    (error "Expected a packed pixel array view."))
  (pixelisp.internal:ensure-live pixels)
  (unless (and (= (length (px.buffer:dimensions pixels)) 2)
               (equal (px.buffer:element-type pixels) '(unsigned-byte 32)))
    (error "Expected a live two-dimensional packed 32-bit pixel array."))
  (%owner-surface pixels))
(defun %packed-color (surface color)
  "Map a normal RGB(A) value to SURFACE, or accept an already packed integer."
  (if (integerp color)
      (progn
        (unless (<= -2147483648 color 4294967295)
          (error 'type-error :datum color :expected-type '(integer -2147483648 4294967295)))
        (ldb (byte 32 0) color))
      (px.surface:map-rgb surface
                          (if (stringp color) (pixelisp.color:parse color) color))))
(defun %normalized-options (distance weights)
  "Validate options and return DISTANCE and normalized red, green, blue weights."
  (unless (and (realp distance) (<= 0 distance 1))
    (error "Distance must be a real number in the range 0 through 1."))
  (unless (and (typep weights 'sequence) (>= (length weights) 3)
               (every #'realp (subseq weights 0 3)))
    (error "Weights must be a sequence with at least three real values."))
  (let* ((values (map 'list #'float (subseq weights 0 3)))
         (sum (reduce #'+ values)))
    (unless (and (every (lambda (weight) (>= weight 0)) values) (> sum 0))
      (error "Weights must be nonnegative and have a positive sum."))
    (values (float distance) (mapcar (lambda (weight) (/ weight sum)) values))))
(defun %color-distance (first second weights)
  "Pygame's normalized, weighted RGB Euclidean distance; alpha is ignored."
  (let ((a (px.color:to-list first)) (b (px.color:to-list second)))
    (/ (sqrt (loop for weight in weights
                   for left in a for right in b
                   sum (* weight (expt (- left right) 2))))
       255.0)))
(defun %matches-color-p (surface packed color distance weights)
  (if (zerop distance)
      (= packed color)
      (<= (%color-distance (px.surface:unmap-rgb surface packed)
                           (px.surface:unmap-rgb surface color) weights)
          distance)))
(defun make-surface (pixels)
  "Copy PIXELS into owned storage, preserving its per-pixel alpha capability.
Decode native colors so imported layouts and transposed/sliced inputs stay correct."
  (let* ((surface (%validate-pixel-array pixels))
         (dimensions (px.buffer:dimensions pixels))
         (result (px.surface:make-surface dimensions :alpha (px.surface:alpha-p surface))))
    (handler-case
        (destructuring-bind (width height) dimensions
          (dotimes (x width)
            (dotimes (y height)
              (px.surface:set-at result (list x y)
                                 (px.surface:unmap-rgb surface (ref pixels x y)))))
          result)
      (error (condition) (px:dispose result) (error condition)))))
(defun replace (pixels old-color new-color &key (distance 0) (weights '(0.299 0.587 0.114)))
  "Replace matching pixels in place and return PIXELS.

At distance zero, native packed pixels must match exactly, including alpha.
For positive distance, matching uses normalized weighted RGB distance and
ignores alpha, as in pygame 2.6.1. Both colors and all options are validated
before the first write."
  (let* ((surface (%validate-pixel-array pixels))
         (old-packed (%packed-color surface old-color))
         (new-packed (%packed-color surface new-color)))
    (multiple-value-bind (distance weights) (%normalized-options distance weights)
      (destructuring-bind (width height) (px.buffer:dimensions pixels)
        (dotimes (x width)
          (dotimes (y height)
            (let ((pixel (ref pixels x y)))
              (when (%matches-color-p surface pixel old-packed distance weights)
                (setf (ref pixels x y) new-packed)))))))
  pixels))
(defun extract (pixels color &key (distance 0) (weights '(0.299 0.587 0.114)))
  "Return a specialized bit array, with 1 for pixels matching COLOR.

Exact matching includes alpha; positive-distance RGB matching ignores alpha."
  (let* ((surface (%validate-pixel-array pixels))
         (packed-color (%packed-color surface color)))
    (multiple-value-bind (distance weights) (%normalized-options distance weights)
      (destructuring-bind (width height) (px.buffer:dimensions pixels)
        (let ((result (make-array (list width height) :element-type 'bit)))
          (dotimes (x width result)
            (dotimes (y height)
              (setf (aref result x y)
                    (if (%matches-color-p surface (ref pixels x y) packed-color distance weights)
                        1 0)))))))))
(defun compare (first second &key (distance 0) (weights '(0.299 0.587 0.114)))
  "Return a specialized bit array, with 1 where decoded colors match.

At distance zero, RGBA components are compared exactly. Positive distance
uses weighted RGB distance and ignores alpha. Surface layouts may differ."
  (let* ((first-surface (%validate-pixel-array first))
         (second-surface (%validate-pixel-array second)))
    (unless (equal (px.buffer:dimensions first) (px.buffer:dimensions second))
      (error "Pixel array dimensions differ."))
    (multiple-value-bind (distance weights) (%normalized-options distance weights)
      (destructuring-bind (width height) (px.buffer:dimensions first)
        (let ((result (make-array (list width height) :element-type 'bit)))
          (dotimes (x width result)
            (dotimes (y height)
              (let ((left (px.surface:unmap-rgb first-surface (ref first x y)))
                    (right (px.surface:unmap-rgb second-surface (ref second x y))))
                (setf (aref result x y)
                      (if (if (zerop distance)
                              (equal (px.color:to-list left) (px.color:to-list right))
                              (<= (%color-distance left right weights) distance))
                          1 0))))))))))
(defun transpose (pixels)
  "Return a writable dependent view with the two pixel axes swapped."
  (%validate-pixel-array pixels)
  (let ((dimensions (px.buffer:dimensions pixels))
        (strides (px.buffer:strides pixels)))
    (px.buffer:make-view
     :owner pixels :dimensions (reverse dimensions) :strides (reverse strides)
     :byte-offset (px.buffer:byte-offset pixels)
     :element-type (px.buffer:element-type pixels)
     :reader (lambda (x y) (ref pixels y x))
     :writer (lambda (value x y) (setf (ref pixels y x) value)))))
