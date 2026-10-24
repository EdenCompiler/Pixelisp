;;;; sbcl --script scripts/play.lisp [frame-count]
(load (merge-pathnames "bootstrap.lisp" *load-truename*))
(ql:quickload "pixelisp/examples" :silent t)
(let ((argument (first (uiop:command-line-arguments))))
  (px.examples:play :frames (when argument (parse-integer argument :junk-allowed nil))))
