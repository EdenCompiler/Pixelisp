;;;; sbcl --script scripts/example.lisp --list
;;;; sbcl --script scripts/example.lisp sprite-lab --frames 120 --fps 60
(load (merge-pathnames "bootstrap.lisp" *load-truename*))
(ql:quickload "pixelisp/examples" :silent t)

(defun example-usage ()
  (format t "Usage: example.lisp NAME [--frames N] [--fps N] [--no-audio] [--output FILE]~%")
  (format t "       example.lisp --list~%~%")
  (dolist (entry (px.examples:list-examples))
    (format t "  ~16A ~A~%" (getf entry :name) (getf entry :description))))

(defun example-main (arguments)
  (let ((name (pop arguments)) (frames nil) (fps 60) (audio t) (output nil))
    (when (or (null name) (member name '("--list" "--help" "-h") :test #'string=))
      (return-from example-main (example-usage)))
    (loop while arguments for option = (pop arguments) do
      (cond ((string= option "--no-audio") (setf audio nil))
            ((member option '("--frames" "--fps" "--output") :test #'string=)
             (unless arguments (error "~A needs a value." option))
             (let ((value (pop arguments)))
               (cond ((string= option "--frames") (setf frames (parse-integer value)))
                     ((string= option "--fps") (setf fps (parse-integer value)))
                     (t (setf output value)))))
            (t (error "Unknown option ~S." option))))
    (let ((entry (find name (px.examples:list-examples) :key (lambda (item) (getf item :name))
                       :test #'string-equal)))
      ;; A CLI invocation cannot retain a returned surface, so save generated
      ;; pictures by default. The REPL dispatcher still returns owned surfaces.
      (when (and entry (eq (getf entry :kind) :surface) (null output))
        (setf output (format nil "~A.png" (getf entry :name))))
      (let ((values (multiple-value-list (px.examples:run-example name :frames frames :fps fps
                                                                 :audio audio :output output))))
        (if output (format t "Saved ~A~%" output)
            (when (and entry (eq (getf entry :kind) :values))
              (format t "~{~S~^ ~}~%" values)))))))

(handler-case (example-main (uiop:command-line-arguments))
  (error (condition)
    (format *error-output* "Example failed: ~A~%" condition)
    (uiop:quit 1)))
