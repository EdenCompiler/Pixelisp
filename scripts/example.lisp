;;;; sbcl --script scripts/example.lisp prism-breaker [--frames 120] [--no-audio]
(load (merge-pathnames "bootstrap.lisp" *load-truename*))
(ql:quickload "pixelisp/examples" :silent t)

(defun example-usage ()
  (format t "Usage: example.lisp NAME [--frames N] [--fps N] [--seed N] [--no-audio] [--screenshot FILE]~%")
  (format t "       example.lisp --list~%~%")
  (dolist (entry (px.examples:list-examples))
    (format t "  ~16A ~A~%" (getf entry :name) (getf entry :description))))

(defun example-main (arguments)
  (let ((name (pop arguments)) (frames nil) (fps 60) (audio t) (seed 1) screenshot)
    (when (or (null name) (member name '("--list" "--help" "-h") :test #'string=))
      (return-from example-main (example-usage)))
    (loop while arguments for option = (pop arguments) do
      (cond ((string= option "--no-audio") (setf audio nil))
            ((member option '("--frames" "--fps" "--seed" "--screenshot") :test #'string=)
             (unless arguments (error "~A needs a value." option))
             (let ((value (pop arguments)))
               (cond ((string= option "--frames") (setf frames (parse-integer value)))
                     ((string= option "--fps") (setf fps (parse-integer value)))
                     ((string= option "--seed") (setf seed (parse-integer value)))
                     (t (setf screenshot value)))))
            (t (error "Unknown option ~S." option))))
    (let ((snapshot (px.examples:run-example name :frames frames :fps fps :audio audio
                                                 :seed seed :screenshot screenshot)))
      (format t "~A: ~A, score ~D~%" name (getf snapshot :status) (getf snapshot :score))
      (when screenshot (format t "Saved ~A~%" screenshot)))))

(handler-case (example-main (uiop:command-line-arguments))
  (error (condition)
    (format *error-output* "Game failed: ~A~%" condition)
    (uiop:quit 1)))
