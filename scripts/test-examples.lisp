;;;; SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy sbcl --script scripts/test-examples.lisp
(load (merge-pathnames "bootstrap.lisp" *load-truename*))
(ql:quickload "pixelisp/examples/tests" :silent t)
(asdf:test-system "pixelisp/examples")
