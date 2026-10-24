;;;; Shared launcher bootstrap. This file resolves paths relative to itself, so
;;;; examples and tests can run from any working directory without editing HOME.
(require :asdf)
(unless (find-package :ql)
  (let ((setup (or (probe-file (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))
                   (probe-file (merge-pathnames ".quicklisp/setup.lisp" (user-homedir-pathname))))))
    (unless setup (error "Install Quicklisp first; see README.md."))
    (load setup)))
(defparameter *pixelisp-root*
  (uiop:pathname-parent-directory-pathname (uiop:pathname-directory-pathname *load-truename*)))
(asdf:load-asd (merge-pathnames "pixelisp.asd" *pixelisp-root*))
