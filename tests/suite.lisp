;;;; Tests use actual native buffers but never need physical input/audio devices.
;;;; The shell runner selects SDL dummy drivers; Xvfb exercises a real X11 window.
(defpackage #:pixelisp.tests
  (:use #:cl #:fiveam))
(in-package #:pixelisp.tests)
(def-suite pixelisp :description "Pixelisp deterministic and native integration tests")
(in-suite pixelisp)
