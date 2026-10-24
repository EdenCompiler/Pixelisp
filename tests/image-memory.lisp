(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defun %read-octets (path)
  (with-open-file (stream path :direction :input :element-type '(unsigned-byte 8))
    (let ((bytes (make-array (file-length stream) :element-type '(unsigned-byte 8))))
      (read-sequence bytes stream)
      bytes)))

(test image-load-encoded-png-and-bmp-bytes
  (dolist (extension '("png" "bmp"))
    (let* ((path (merge-pathnames (format nil "pixelisp-memory-~A.~A" (gensym) extension)
                                  (uiop:temporary-directory)))
           (surface (px.surface:make-surface '(2 2) :alpha t)))
      (unwind-protect
           (progn
             (px.surface:fill surface '(31 82 143 197))
             (px.image:save surface path)
             (let ((loaded (px.image:load-bytes (%read-octets path)
                                                 :namehint (if (string= extension "png")
                                                               :png
                                                               (format nil "memory.~A" extension)))))
               (unwind-protect
                    (progn
                      (is (equal '(2 2) (px.surface:size loaded)))
                      (destructuring-bind (r g b a)
                          (px.color:to-list (px.surface:get-at loaded '(1 1)))
                        (is (= 31 r)) (is (= 82 g)) (is (= 143 b))
                        (when (string= extension "png") (is (= 197 a)))))
                 (px:dispose loaded))))
        (px:dispose surface)
        (when (probe-file path) (delete-file path))))))

(test image-load-binary-stream-keeps-caller-open
  (let* ((path (merge-pathnames (format nil "pixelisp-memory-~A.png" (gensym))
                                (uiop:temporary-directory)))
         (surface (px.surface:make-surface '(1 1) :alpha t)))
    (unwind-protect
         (progn
           (px.surface:fill surface '(9 18 27 255))
           (px.image:save surface path)
           (with-open-file (stream path :direction :input :element-type '(unsigned-byte 8))
             (let ((loaded (px.image:load stream :namehint "PNG")))
               (unwind-protect
                    (progn
                      (is (open-stream-p stream))
                      (is (= 18 (px:color-g (px.surface:get-at loaded '(0 0))))))
                 (px:dispose loaded)))))
      (px:dispose surface)
      (when (probe-file path) (delete-file path)))))

(test image-load-rejects-empty-malformed-and-non-octet-vectors
  (signals type-error (px.image:load #(1 2 3)))
  (let ((before (length pixelisp.internal:*resources*)))
    (signals px:error (px.image:load (make-array 0 :element-type '(unsigned-byte 8))))
    (signals px:error (px.image:load (make-array 12 :element-type '(unsigned-byte 8)
                                               :initial-element 0)))
    (is (= before (length pixelisp.internal:*resources*)))))

(test image-load-rejects-invalid-namehint-before-registering-resources
  (let ((before (length pixelisp.internal:*resources*)))
    (signals px:error (px.image:load (make-array 4 :element-type '(unsigned-byte 8)
                                               :initial-element 0)
                                     :namehint "not-an-image.invalid"))
    (is (= before (length pixelisp.internal:*resources*)))))

(test wrap-surface-failure-frees-owned-native-input
  ;; These failures occur at separate stages after WRAP-SURFACE has accepted
  ;; ownership. Keep a real SDL allocation so the free counter observes the
  ;; actual pointer and protect against a regression that frees it twice.
  (dolist (injection (list (cons 'px.surface:make-surface "destination creation")
                           (cons 'sdl2:convert-surface-format "format conversion")
                           (cons 'px.surface:set-at "pixel copy")))
    (let* ((native (sdl2:create-rgb-surface 1 1 32 :r-mask #xff :g-mask #xff00
                                            :b-mask #xff0000 :a-mask #xff000000))
           (raw (pixelisp.internal:%ptr native))
           (before (length pixelisp.internal:*resources*))
           (free-symbol 'pixelisp.internal::%free-surface)
           (injected-symbol (car injection))
           (real-free (symbol-function free-symbol))
           (real-injected (symbol-function injected-symbol))
           (free-count 0))
      ;; WRAP-SURFACE now owns RAW; suppress the SDL binding's finalizer.
      (trivial-garbage:cancel-finalization native)
      (unwind-protect
           (progn
             (setf (symbol-function free-symbol)
                   (lambda (pointer)
                     (if (cffi:pointer-eq pointer raw)
                         (progn
                           (incf free-count)
                           ;; Count accidental repeated frees without passing a
                           ;; dangling pointer back to SDL a second time.
                           (when (= free-count 1) (funcall real-free pointer)))
                         (funcall real-free pointer))))
             (setf (symbol-function injected-symbol)
                   (lambda (&rest arguments)
                     (declare (ignore arguments))
                     (error "Injected ~A failure." (cdr injection))))
             (signals error
               (pixelisp.internal:wrap-surface raw :owned t :alpha t))
             (is (= 1 free-count))
             (is (= before (length pixelisp.internal:*resources*))))
        (setf (symbol-function injected-symbol) real-injected
              (symbol-function free-symbol) real-free)
        ;; If the implementation under test failed to release ownership, avoid
        ;; leaving the native fixture allocated after recording the assertion.
        (when (zerop free-count) (funcall real-free raw))))))
