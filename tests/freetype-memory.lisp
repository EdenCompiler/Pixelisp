;;;; Memory-backed FreeType faces: source ownership, collections and cleanup.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defun %freetype-fixture-bytes ()
  "Read the bundled TTF into a fresh specialized octet vector."
  (let* ((path (asdf:system-relative-pathname "pixelisp" "assets/fonts/DejaVuSans.ttf"))
         (bytes (make-array (with-open-file (stream path :direction :input
                                                        :element-type '(unsigned-byte 8))
                              (file-length stream))
                            :element-type '(unsigned-byte 8))))
    (with-open-file (stream path :direction :input :element-type '(unsigned-byte 8))
      (read-sequence bytes stream))
    bytes))

(defun %freetype-put-u32be (bytes offset value)
  (dotimes (index 4)
    (setf (aref bytes (+ offset index))
          (ldb (byte 8 (* 8 (- 3 index))) value)))
  bytes)

(defun %freetype-u16be (bytes offset)
  (+ (ash (aref bytes offset) 8) (aref bytes (1+ offset))))

(defun %freetype-u32be (bytes offset)
  (loop for index below 4
        for value = (aref bytes (+ offset index)) then (+ (ash value 8) (aref bytes (+ offset index)))
        finally (return value)))

(defun %freetype-two-face-collection ()
  "Wrap the bundled TTF in a TTC with two faces sharing one SFNT directory."
  (let* ((ttf (%freetype-fixture-bytes))
         (ttc (make-array (+ 20 (length ttf)) :element-type '(unsigned-byte 8)
                                              :initial-element 0)))
    (setf (aref ttc 0) (char-code #\t)
          (aref ttc 1) (char-code #\t)
          (aref ttc 2) (char-code #\c)
          (aref ttc 3) (char-code #\f))
    (%freetype-put-u32be ttc 4 #x00010000)
    (%freetype-put-u32be ttc 8 2)
    (%freetype-put-u32be ttc 12 20)
    (%freetype-put-u32be ttc 16 20)
    (replace ttc ttf :start1 20 :end1 (+ 20 (length ttf)) :start2 0)
    ;; TTC table offsets are absolute file positions. Shift the original
    ;; standalone TTF's table locations by the 20-byte collection header.
    (let ((table-count (%freetype-u16be ttc 24)))
      (dotimes (index table-count)
        (let* ((record (+ 32 (* index 16)))
               (offset-field (+ record 8)))
          (%freetype-put-u32be ttc offset-field
                               (+ 20 (%freetype-u32be ttc offset-field))))))
    ttc))

(defun %freetype-write-octets (bytes path)
  (with-open-file (stream path :direction :output :if-exists :supersede
                               :element-type '(unsigned-byte 8))
    (write-sequence bytes stream))
  path)

(test freetype-memory-and-path-sources-render-the-same
  (let* ((path (asdf:system-relative-pathname "pixelisp" "assets/fonts/DejaVuSans.ttf"))
         (path-font (px.freetype:make-font path 21))
         (bytes-font (px.freetype:load-font-bytes (%freetype-fixture-bytes) 21))
         (string-font (px.freetype:make-font (namestring path) 21))
         (font-alias (px.freetype:font (%freetype-fixture-bytes) 21)))
    (unwind-protect
         (progn
           (multiple-value-bind (path-mask path-dimensions)
               (px.freetype:render-raw path-font "Pixelisp")
             (multiple-value-bind (memory-mask memory-dimensions)
                 (px.freetype:render-raw bytes-font "Pixelisp")
               (is (equal path-dimensions memory-dimensions))
               (is (equalp path-mask memory-mask)))
             (multiple-value-bind (string-mask string-dimensions)
                 (px.freetype:render-raw string-font "Pixelisp")
               (is (equal path-dimensions string-dimensions))
               (is (equalp path-mask string-mask)))
             (multiple-value-bind (alias-mask alias-dimensions)
                 (px.freetype:render-raw font-alias "Pixelisp")
               (is (equal path-dimensions alias-dimensions))
               (is (equalp path-mask alias-mask))))
           (is (stringp (px.freetype:path path-font)))
           (is (null (px.freetype:path bytes-font)))
           ;; PATH returns fresh mutable storage rather than the font's slot.
           (let ((returned (px.freetype:path path-font)))
             (setf (char returned 0) #\X)
             (is (not (char= #\X (char (px.freetype:path path-font) 0))))))
      (px.freetype:close path-font)
      (px.freetype:close bytes-font)
      (px.freetype:close string-font)
      (px.freetype:close font-alias))))

(test freetype-memory-source-retains-private-copy-after-caller-mutation
  (let* ((bytes (%freetype-fixture-bytes))
         (font (px.freetype:make-font bytes 20)))
    (unwind-protect
         (progn
           (fill bytes 0)
           (is (not (null (px.freetype:get-metrics font "memory"))))
           (is (plusp (length (px.freetype:render-raw font "A")))))
      (px.freetype:close font))))

(test freetype-memory-stream-reads-from-position-and-leaves-stream-open
  (let* ((bytes (%freetype-fixture-bytes))
         (path (merge-pathnames (format nil "pixelisp-ft-stream-~A.ttf" (gensym))
                                (uiop:temporary-directory)))
         (font nil))
    (unwind-protect
         (progn
           (%freetype-write-octets (concatenate '(vector (unsigned-byte 8)) #(0 0 0 0) bytes) path)
           (with-open-file (stream path :direction :input :element-type '(unsigned-byte 8))
             (file-position stream 4)
             (setf font (px.freetype:make-font stream 18))
             (is (open-stream-p stream))
             (is (not (null (px.freetype:get-metrics font "offset"))))
             (close stream)
             (is (not (open-stream-p stream)))
             (is (not (null (px.freetype:get-metrics font "after close"))))))
      (when font (px.freetype:close font))
      (when (probe-file path) (delete-file path)))))

(test freetype-memory-collection-index-and-native-face-count
  (let ((collection (%freetype-two-face-collection))
        (font nil))
    (unwind-protect
         (progn
           (setf font (px.freetype:load-font-bytes collection 19 :font-index 1))
           (is (= 1 (px.freetype:font-index font)))
           (is (= 2 (px.freetype:num-faces font)))
           (is (plusp (length (px.freetype:render-raw font "face one"))))
           (signals px:error (px.freetype:load-font-bytes collection 19 :font-index 2)))
      (when font (px.freetype:close font)))))

(test freetype-memory-input-errors-do-not-register-resources
  (let ((before (length pixelisp.internal:*resources*)))
    (signals type-error (px.freetype:make-font 42 16))
    (signals type-error
      (px.freetype:make-font (make-string-input-stream "not binary") 16))
    (signals type-error (px.freetype:load-font-bytes #(1 2 3) 16))
    (signals px:error
      (px.freetype:load-font-bytes (make-array 0 :element-type '(unsigned-byte 8)) 16))
    (signals px:error
      (px.freetype:load-font-bytes (make-array 4 :element-type '(unsigned-byte 8)
                                               :initial-contents '(1 2 3 4)) 16))
    (signals type-error (px.freetype:make-font nil 16 :font-index -1))
    (signals type-error (px.freetype:make-font nil 16 :font-index 1.5))
    (signals type-error
      (px.freetype:make-font nil 16 :font-index
                             (ash 1 (1- (* 8 (cffi:foreign-type-size :long))))))
    (signals px:error (px.freetype:load-font-bytes (%freetype-fixture-bytes) 16 :font-index 1))
    ;; High FT_Long bits may be ignored by native FreeType. The collection API
    ;; still rejects an unavailable face rather than silently opening zero.
    (when (> (cffi:foreign-type-size :long) 4)
      (signals px:error (px.freetype:make-font nil 16 :font-index (ash 1 32))))
    (is (= before (length pixelisp.internal:*resources*)))))

(test freetype-collection-path-and-ftfont-facade-select-the-same-face
  (let* ((collection (%freetype-two-face-collection))
         (path (merge-pathnames (format nil "pixelisp-collection-~A.ttc" (gensym))
                                (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (%freetype-write-octets collection path)
           (px:with-resource (path-font (px.freetype:make-font path 18 :font-index 1))
             (px:with-resource (facade (px.ftfont:make-font collection 18 :font-index 1))
               (px:with-resource (alias (px.ftfont:font collection 18 :font-index 1))
                 (dolist (font (list path-font facade alias))
                   (is (= 1 (px.freetype:font-index font)))
                   (is (= 2 (px.freetype:num-faces font))))
                 (px:with-resource (label (px.ftfont:render facade "Collection" t '(255 255 255)))
                   (is (plusp (px.surface:width label))))))))
      (when (probe-file path) (delete-file path)))))

(test freetype-source-readers-check-kind-and-lifetime-before-native-access
  (let ((font (px.freetype:make-font nil 16)))
    (px.freetype:close font)
    (dolist (reader '(px.freetype:path px.freetype:font-index px.freetype:num-faces))
      (signals px:disposed-resource (funcall reader font))
      (px.surface:with-surface (surface '(1 1))
        (signals type-error (funcall reader surface))))))

(test freetype-memory-face-registration-failure-closes-before-freeing-bytes
  (let* ((before (length pixelisp.internal:*resources*))
         (register-symbol 'pixelisp.internal:register-resource)
         (release-symbol 'pixelisp.freetype::%release-face)
         ;; Observe the font's native-storage adapter. CFFI can inline its
         ;; allocator, so replacing CFFI:FOREIGN-FREE would miss actual frees.
         (free-symbol 'pixelisp.freetype::%release-font-memory)
         (real-register (symbol-function register-symbol))
         (real-release (symbol-function release-symbol))
         (real-free (symbol-function free-symbol))
         (events nil) (registration-calls 0))
    (unwind-protect
         (progn
           (setf (symbol-function register-symbol)
                 (lambda (&rest arguments)
                   (declare (ignore arguments))
                   (incf registration-calls)
                   (error "Injected registration failure.")))
           (setf (symbol-function release-symbol)
                 (lambda (face)
                   (push :face-close events)
                   (funcall real-release face)))
           (setf (symbol-function free-symbol)
                 (lambda (&rest arguments)
                   (push :bytes-free events)
                   (apply real-free arguments)))
           ;; Sizing a bitmap-only face can fail after opening it but before
           ;; registration. That path needs the same face-before-bytes cleanup.
           (let ((bitmap (with-open-file
                            (stream (asdf:system-relative-pathname "pixelisp/tests" "tests/fixtures/tiny-mono.bdf")
                                    :element-type '(unsigned-byte 8))
                          (px.font::%font-source-octets stream))))
             (signals error (px.freetype:make-font bitmap 100))
             (is (= 0 registration-calls))
             (is (equal '(:bytes-free :face-close) events)))
           (setf events nil)
           (signals error
             (px.freetype:load-font-bytes (%freetype-fixture-bytes) 16))
           (is (= 1 registration-calls))
           (is (= before (length pixelisp.internal:*resources*)))
           (is (equal '(:bytes-free :face-close) events)))
      (setf (symbol-function register-symbol) real-register
            (symbol-function release-symbol) real-release
            (symbol-function free-symbol) real-free))))

(test freetype-memory-disposal-and-quit-can-repeat
  (let* ((before (length pixelisp.internal:*resources*))
         (font-a (px.freetype:load-font-bytes (%freetype-fixture-bytes) 16))
         (font-b (px.freetype:make-font (%freetype-fixture-bytes) 17)))
    (unwind-protect
         (progn
           (px.freetype:close font-a)
           (px.freetype:close font-a)
           (px.freetype:quit)
           (px.freetype:quit)
           (is (= before (length pixelisp.internal:*resources*)))
           (signals px:disposed-resource (px.freetype:size font-a))
           (signals px:disposed-resource (px.freetype:size font-b))
           (let ((font-c (px.freetype:load-font-bytes (%freetype-fixture-bytes) 18)))
             (unwind-protect (is (not (null (px.freetype:get-metrics font-c "again"))))
               (px.freetype:close font-c))))
      (px.freetype:quit))))
