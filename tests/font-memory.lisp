(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defun %font-fixture-bytes ()
  (let* ((path (asdf:system-relative-pathname "pixelisp" "assets/fonts/DejaVuSans.ttf"))
         (bytes (make-array (with-open-file (stream path :direction :input
                                                        :element-type '(unsigned-byte 8))
                              (file-length stream))
                            :element-type '(unsigned-byte 8))))
    (with-open-file (stream path :direction :input :element-type '(unsigned-byte 8))
      (read-sequence bytes stream))
    bytes))

(test font-from-octets-renders-and-retains-private-copy
  (let* ((bytes (%font-fixture-bytes))
         (font (px.font:load-font-bytes bytes 24))
         (width (px.font:size font "Pixelisp"))
         (height (px.font:get-height font))
         (surface nil))
    (unwind-protect
         (progn
           (is (plusp width))
           (is (plusp height))
           ;; A later glyph lookup still works after changing caller storage.
           (fill bytes 0)
           (setf surface (px.font:render font "Memory" t '(255 255 255)))
           (is (plusp (px.surface:width surface)))
           (is (plusp (px.surface:height surface)))
           (is (= 5 (length (first (px.font:metrics font "A"))))))
      (when surface (px:dispose surface))
      (px.font:close font))))

(test font-from-binary-stream-keeps-caller-open-and-independent
  (let* ((bytes (%font-fixture-bytes))
         (path (merge-pathnames (format nil "pixelisp-font-~A.ttf" (gensym))
                                (uiop:temporary-directory)))
         (font nil))
    (unwind-protect
         (progn
           (with-open-file (output path :direction :output
                                        :element-type '(unsigned-byte 8)
                                        :if-exists :supersede)
             (write-sequence bytes output))
           (with-open-file (stream path :direction :input :element-type '(unsigned-byte 8))
             (setf font (px.font:make-font stream 18))
             (is (open-stream-p stream))
             (is (plusp (px.font:size font "stream")))
             (close stream)
             (is (not (open-stream-p stream)))
             ;; The font's retained native copy is valid after stream closure.
             (is (plusp (px.font:size font "still live")))))
      (when font (px.font:close font))
      (when (probe-file path) (delete-file path)))))

(test font-from-stream-reads-from-current-position
  (let* ((bytes (%font-fixture-bytes))
         (path (merge-pathnames (format nil "pixelisp-font-offset-~A.ttf" (gensym))
                                (uiop:temporary-directory)))
         (font nil))
    (unwind-protect
         (progn
           (with-open-file (output path :direction :output
                                        :element-type '(unsigned-byte 8)
                                        :if-exists :supersede)
             (write-sequence #(0 0 0 0) output)
             (write-sequence bytes output))
           (with-open-file (stream path :direction :input :element-type '(unsigned-byte 8))
             (file-position stream 4)
             (setf font (px.font:make-font stream 18))
             (is (plusp (px.font:size font "offset")))))
      (when font (px.font:close font))
      (when (probe-file path) (delete-file path)))))

(test font-memory-disposal-is-repeatable-and-type-checked
  (let ((before (length pixelisp.internal:*resources*)))
    (let ((font (px.font:load-font-bytes (%font-fixture-bytes) 16)))
      (is (= (1+ before) (length pixelisp.internal:*resources*)))
      (px.font:close font)
      (px.font:close font)
      (is (= before (length pixelisp.internal:*resources*)))
      (signals px:disposed-resource (px.font:size font "closed"))
      (signals type-error (px.font:size :not-a-font "invalid")))))

(test font-quit-closes-live-memory-fonts-and-can-repeat
  (let* ((font-a (px.font:load-font-bytes (%font-fixture-bytes) 16))
         (font-b (px.font:load-font-bytes (%font-fixture-bytes) 17)))
    (unwind-protect
         (progn
           (px.font:quit)
           (px.font:quit)
           (signals px:disposed-resource (px.font:size font-a "closed"))
           (signals px:disposed-resource (px.font:size font-b "closed"))
           ;; Constructors initialize SDL_ttf again after QUIT.
           (let ((font-c (px.font:load-font-bytes (%font-fixture-bytes) 18)))
             (unwind-protect (is (plusp (px.font:size font-c "reopen")))
               (px.font:close font-c))))
      (px.font:quit))))

(test font-registration-failure-releases-native-ownership
  (let* ((before (length pixelisp.internal:*resources*))
         (register-symbol 'pixelisp.internal:register-resource)
         (rw-close-symbol 'pixelisp.image::%rw-close)
         (font-close-symbol 'sdl2-ttf:close-font)
         (real-register (symbol-function register-symbol))
         (real-rw-close (symbol-function rw-close-symbol))
         (real-font-close (symbol-function font-close-symbol))
         (rw-close-count 0) (font-close-count 0))
    (unwind-protect
         (progn
           (setf (symbol-function register-symbol)
                 (lambda (&rest arguments)
                   (declare (ignore arguments))
                   (error "Injected registration failure.")))
           (setf (symbol-function rw-close-symbol)
                 (lambda (rwops) (incf rw-close-count) (funcall real-rw-close rwops)))
           (setf (symbol-function font-close-symbol)
                 (lambda (font) (incf font-close-count) (funcall real-font-close font)))
           (signals error (px.font:load-font-bytes (%font-fixture-bytes) 16))
           (is (= before (length pixelisp.internal:*resources*)))
           (is (= 1 rw-close-count))
           (is (= 1 font-close-count)))
      (setf (symbol-function register-symbol) real-register
            (symbol-function rw-close-symbol) real-rw-close
            (symbol-function font-close-symbol) real-font-close))))

(test font-memory-errors-release-resources-before-allocating
  (let ((before (length pixelisp.internal:*resources*)))
    (signals type-error (px.font:load-font-bytes #(1 2 3) 16))
    (signals type-error (px.font:make-font (make-string-input-stream "not binary") 16))
    (signals px:error
      (px.font:load-font-bytes (make-array 0 :element-type '(unsigned-byte 8)) 16))
    (signals px:error
      (px.font:load-font-bytes (make-array 4 :element-type '(unsigned-byte 8)
                                           :initial-contents '(1 2 3 4)) 16))
    (signals px:error (px.font:make-font nil #x80000000))
    (is (= before (length pixelisp.internal:*resources*)))))
