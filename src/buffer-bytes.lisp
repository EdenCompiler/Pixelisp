;;;; BufferProxy-style copies and writes without exposing foreign addresses.
;;;; The core buffer keeps ownership and index callbacks. This native adapter
;;;; supplies byte encodings, including C float encodings, for contiguous views.
(in-package #:pixelisp.buffer)

(defun %check-byte-view (view)
  (check-type view buffer-view)
  (pixelisp.internal:ensure-live view)
  view)

(defun parent (view)
  "Return VIEW's immediate exporting owner after checking its lifetime."
  (%check-byte-view view)
  (owner view))

(defun %byte-element-layout (view)
  "Return the element byte count and its integer or floating-point encoding."
  (let ((type (element-type view)))
    (cond ((eq type 'single-float) (values 4 :float))
          ((eq type 'double-float) (values 8 :double))
          ((and (listp type) (= (length type) 2)
                (member (first type) '(signed-byte unsigned-byte))
                (typep (second type) '(integer 1 *))
                (zerop (mod (second type) 8)))
           (values (/ (second type) 8) (first type)))
          (t (error 'pixelisp:unsupported-feature :operation 'raw
                    :message "Byte access requires whole-byte integer, single-float, or double-float elements.")))))

(defun byte-length (view)
  "Return the number of logical bytes in VIEW, excluding gaps between elements."
  (%check-byte-view view)
  (* (%byte-element-layout view) (reduce #'* (dimensions view) :initial-value 1)))

(defun %contiguous-order-p (dimensions strides bytes axes)
  ;; Singleton axes impose no stride constraint. Negative or gapped strides
  ;; on larger axes cannot describe a forward contiguous byte block.
  (let ((expected bytes))
    (dolist (axis axes t)
      (let ((dimension (nth axis dimensions)))
        (when (> dimension 1)
          (unless (= expected (nth axis strides)) (return nil))
          (setf expected (* expected dimension)))))))

(defun %byte-order (view bytes)
  "Return :C or :F for contiguous storage, or NIL for a strided byte layout."
  (let* ((dimensions (dimensions view)) (strides (strides view))
         (axes (loop for axis below (length dimensions) collect axis)))
    (cond ((or (member 0 dimensions) (null dimensions)) :c)
          ;; A callback-only view without strides uses Lisp row-major order.
          ((null strides) :c)
          ((%contiguous-order-p dimensions strides bytes (reverse axes)) :c)
          ((%contiguous-order-p dimensions strides bytes axes) :f))))

(defun contiguous-p (view)
  "Whether VIEW has forward C- or Fortran-contiguous byte storage."
  (%check-byte-view view)
  (not (null (%byte-order view (%byte-element-layout view)))))

(defun %require-byte-order (view bytes operation)
  (or (%byte-order view bytes)
      (error 'pixelisp:unsupported-feature :operation operation
             :message "Raw byte access requires a contiguous view; copy strided data with TO-ARRAY.")))

(defun %physical-indices (dimensions linear order)
  "Translate a physical element position into the view's logical coordinates."
  (let* ((indices (make-array (length dimensions) :initial-element 0))
         (axes (loop for axis below (length dimensions) collect axis)))
    (dolist (axis (if (eq order :f) axes (reverse axes)))
      (multiple-value-bind (rest index) (floor linear (nth axis dimensions))
        (setf linear rest (aref indices axis) index)))
    (coerce indices 'list)))

(defun %little-endian-p ()
  (cffi:with-foreign-object (word :uint16)
    (setf (cffi:mem-ref word :uint16) 1)
    (= 1 (cffi:mem-ref word :uint8))))

(defun %encode-element (value type kind count output offset little-endian)
  "Copy VALUE into OUTPUT using native byte order, without numeric conversion."
  (unless (typep value type)
    (error 'type-error :datum value :expected-type type))
  (if (member kind '(:float :double))
      (pixelisp.internal:with-native-context
        (cffi:with-foreign-object (storage :double)
          (setf (cffi:mem-ref storage kind) value)
          (dotimes (byte count)
            (setf (aref output (+ offset byte)) (cffi:mem-aref storage :uint8 byte)))))
      (dotimes (byte count)
        (setf (aref output (+ offset byte))
              (ldb (byte 8 (* 8 (if little-endian byte (- count byte 1)))) value)))))

(defun %decode-element (input offset kind count little-endian)
  "Decode one native element; signed integers use two's-complement bits."
  (if (member kind '(:float :double))
      (pixelisp.internal:with-native-context
        (cffi:with-foreign-object (storage :double)
          (dotimes (byte count)
            (setf (cffi:mem-aref storage :uint8 byte) (aref input (+ offset byte))))
          (cffi:mem-ref storage kind)))
      (let* ((bits (* count 8))
             (value (loop for byte below count sum
                      (ash (aref input (+ offset byte))
                           (* 8 (if little-endian byte (- count byte 1)))))))
        (if (and (eq kind 'signed-byte) (logbitp (1- bits) value))
            (- value (ash 1 bits)) value))))

(defun raw (view)
  "Return an independent specialized octet vector in physical memory order.
Both C and Fortran layouts are supported. Gapped/reversed views are rejected."
  (%check-byte-view view)
  (multiple-value-bind (bytes kind) (%byte-element-layout view)
    (let* ((order (%require-byte-order view bytes 'raw))
           (dimensions (dimensions view))
           (count (reduce #'* dimensions :initial-value 1))
           (result (make-array (* bytes count) :element-type '(unsigned-byte 8)))
           (little-endian (%little-endian-p)))
      (dotimes (index count result)
        (%encode-element (apply #'view-ref view (%physical-indices dimensions index order))
                         (element-type view) kind bytes result (* index bytes) little-endian)))))

(defun %source-octets (source)
  "Snapshot and validate input before a write, including overlapping source views."
  (when (typep source 'buffer-view) (return-from %source-octets (raw source)))
  (unless (and (typep source 'sequence) (not (stringp source)))
    (error 'type-error :datum source :expected-type '(or list vector buffer-view)))
  (let ((result (make-array (length source) :element-type '(unsigned-byte 8))))
    (loop for value across (coerce source 'vector) for index from 0
          do (check-type value (unsigned-byte 8)) (setf (aref result index) value))
    result))

(defun write-bytes (view source &key (offset 0))
  "Overwrite a contiguous view with octets at byte OFFSET; return VIEW.
Partial-element writes preserve untouched bytes. All bounds, input octets and
decoding are checked before the first callback write; source views are copied."
  (%check-byte-view view)
  (unless (view-writer view)
    (error 'pixelisp:unsupported-feature :operation 'write-bytes :message "This view is read-only."))
  (check-type offset (integer 0 *))
  (multiple-value-bind (bytes kind) (%byte-element-layout view)
    (let* ((order (%require-byte-order view bytes 'write-bytes))
           (total-bytes (byte-length view))
           (input (%source-octets source))
           (end (+ offset (length input)))
           (little-endian (%little-endian-p)))
      (unless (<= offset end total-bytes)
        (error "Byte write [~D, ~D) is outside a buffer of ~D bytes." offset end total-bytes))
      (when (= offset end) (return-from write-bytes view))
      (let* ((first (floor offset bytes)) (last (ceiling end bytes))
             (dimensions (dimensions view))
             (patch (make-array (* (- last first) bytes) :element-type '(unsigned-byte 8)))
             (updates (make-array (- last first))))
        ;; Snapshot whole affected elements, then decode every replacement.
        ;; A decoding error or failing reader cannot leave half a patch.
        (loop for index from first below last for base from 0 by bytes do
          (%encode-element (apply #'view-ref view (%physical-indices dimensions index order))
                           (element-type view) kind bytes patch base little-endian))
        (replace patch input :start1 (- offset (* first bytes)))
        (loop for index below (length updates) for base from 0 by bytes do
          (setf (aref updates index) (%decode-element patch base kind bytes little-endian)))
        (loop for value across updates for index from first do
          (setf (apply #'view-ref view (%physical-indices dimensions index order)) value)))))
  view)

(defun write (view source &key (offset 0))
  "BufferProxy spelling of WRITE-BYTES; return the destination view."
  (write-bytes view source :offset offset))
