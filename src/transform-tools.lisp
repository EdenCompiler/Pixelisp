;;;; Pixelisp-specific transform helpers.
;;;;
;;;; The average implementation uses explicit snapshots so aliases are safe and
;;;; output writes remain independent of the destination's drawing clip.
(in-package #:pixelisp.transform)

(defvar *smoothscale-backend* :generic)

(defun get-smoothscale-backend ()
  "Return the implementation selected for smoothscale (always :GENERIC)."
  *smoothscale-backend*)

(defun set-smoothscale-backend (backend)
  "Select the generic smoothscale implementation; SIMD backends are unavailable."
  (let ((normalized
          (cond ((and (stringp backend) (string-equal backend "GENERIC")) :generic)
                ((eq backend :generic) :generic)
                ((or (and (stringp backend)
                          (member (string-upcase backend) '("MMX" "SSE" "AVX") :test #'string=))
                     (member backend '(:mmx :sse :avx) :test #'eq))
                 (error 'pixelisp:unsupported-feature
                        :operation 'set-smoothscale-backend
                        :message "This build provides only the generic smoothscale backend."))
                (t (error "Backend must be :GENERIC or the string \"GENERIC\".")))))
    (setf *smoothscale-backend* normalized)))

(defun %validate-average-surfaces (surfaces destination)
  (unless (and (typep surfaces 'sequence) (not (stringp surfaces)))
    (error 'type-error :datum surfaces :expected-type '(or list vector)))
  (let ((sources (coerce surfaces 'list)))
    (unless sources (error 'type-error :datum surfaces :expected-type '(cons * *)))
    ;; Check owner/type for all inputs before any native format query.
    (dolist (surface sources) (px.surface::check-surface surface))
    (let ((first (first sources)))
      (dolist (surface (rest sources))
        (unless (equal (px.surface:size surface) (px.surface:size first))
          (error "All averaged surfaces must have the same dimensions.")))
      (when destination
        (px.surface::check-surface destination)
        (unless (equal (px.surface:size destination) (px.surface:size first))
          (error "The average-surfaces destination has the wrong dimensions."))
        (unless (%same-format-p first destination)
          (error "The average-surfaces destination has a different pixel format.")))
      (values sources first))))

(defun %average-surface-snapshot (surface indices-only)
  "Capture each source pixel before writes, preserving palette-index mode."
  (let* ((width (px.surface:width surface))
         (height (px.surface:height surface))
         (pixels (make-array (list height width))))
    (px.surface:lock surface)
    (unwind-protect
         (dotimes (y height)
           (dotimes (x width)
             (setf (aref pixels y x)
                   (if indices-only
                       (px.surface::%read-packed-pixel surface x y)
                       (multiple-value-list
                        (pixelisp.internal:rgba (px.surface:get-at surface (list x y))))))))
      (px.surface:unlock surface))
    pixels))

(defun %average-octet (sum count)
  ;; Pygame rounds positive half values upward before mapping the channels.
  (floor (+ sum (/ count 2)) count))

(defun average-surfaces (surfaces &optional destination &key (palette-colors t))
  "Average matching surfaces, using palette colors or raw 8-bit indices.

When DESTINATION is supplied it must match the input dimensions and pixel
format. Pixel values are snapshotted before output, and output ignores clipping."
  (check-type palette-colors boolean)
  (multiple-value-bind (sources first) (%validate-average-surfaces surfaces destination)
    (let* ((width (px.surface:width first))
           (height (px.surface:height first))
           ;; Index mode only applies when every input is indexed. With mixed
           ;; formats all sources are decoded to RGB, even if the option is NIL.
           (indices-only (and (not palette-colors)
                              (every (lambda (surface) (= 8 (px.surface:get-bitsize surface)))
                                     sources)))
           (snapshots (mapcar (lambda (surface)
                                (%average-surface-snapshot surface indices-only))
                              sources))
           (result (or destination (%new-like first width height)))
           (created-p (null destination))
           (complete-p nil))
      (unwind-protect
           (progn
             (px.surface:lock result)
             (unwind-protect
                  (dotimes (y height)
                    (dotimes (x width)
                      (let ((samples (mapcar (lambda (image) (aref image y x)) snapshots)))
                        (if (integerp (first samples))
                            (px.surface::%write-packed-pixel
                             result x y (%average-octet (reduce #'+ samples) (length samples)))
                            (let* ((count (length samples))
                                   (red (%average-octet (reduce #'+ samples :key #'first) count))
                                   (green (%average-octet (reduce #'+ samples :key #'second) count))
                                   (blue (%average-octet (reduce #'+ samples :key #'third) count))
                                   (mapped (px.surface:map-rgb result (pixelisp:make-color red green blue 255))))
                              (px.surface::%write-packed-pixel result x y mapped))))))
                (px.surface:unlock result))
             (setf complete-p t)
             result)
        (when (and created-p (not complete-p)) (px:dispose result))))))
