;;;; These SDL1 interfaces are retired in pygame 2 as well. Keep availability
;;;; explicit instead of pretending that an implementation can access devices.
(defpackage #:pixelisp.cdrom
  (:use #:cl) (:nicknames #:px.cdrom)
  (:export #:init #:quit #:get-init #:get-count))
(in-package #:pixelisp.cdrom)
(defun init ()
  "Signal that SDL2 does not provide the retired CD-ROM subsystem."
  (error 'pixelisp:unsupported-feature :operation 'cdrom-init
         :message "CD-ROM support was removed with SDL2; this legacy pygame interface is unavailable."))
(defun quit () nil)
(defun get-init () nil)
(defun get-count () 0)
(in-package #:pixelisp)
(defun make-overlay (&rest arguments)
  "Signal that the SDL1 Overlay interface has been retired."
  (declare (ignore arguments))
  (cl:error 'unsupported-feature :operation 'make-overlay
            :message "SDL1 overlays are unavailable; use px.sdl2.video textures instead."))
(export 'make-overlay)
