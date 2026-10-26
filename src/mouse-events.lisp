;;;; SDL mouse event fields added across SDL2 releases.
(in-package #:pixelisp.event)

;; Keep this SDL_MouseWheelEvent prefix local because older cl-sdl2 bindings may
;; not expose the SDL 2.0.18 precise fields in their generated struct metadata.
(cffi:defcstruct %sdl-mouse-wheel-event
  (type :uint32) (timestamp :uint32) (window-id :uint32) (which :uint32)
  (x :int) (y :int) (direction :uint32) (precise-x :float) (precise-y :float))

(defun %native-touch-mouse-p (which)
  "SDL uses the all-bits-set mouse ID for touch-generated mouse events."
  (= which #xffffffff))

(defun %sdl-version-at-least-p (major minor patch)
  (multiple-value-bind (native-major native-minor native-patch) (sdl2:version)
    (or (> native-major major)
        (and (= native-major major)
             (or (> native-minor minor)
                 (and (= native-minor minor) (>= native-patch patch)))))))

(defun %native-wheel-precise (native &optional (has-precise-fields (%sdl-version-at-least-p 2 0 18)))
  "Read SDL 2.0.18+ precise wheel floats, with integer fallback for older SDL.

The cl-sdl2 binding may have been generated from SDL headers that predate the
preciseX/preciseY fields. Use SDL's public event layout directly rather than
depending on those generated field names."
  (if has-precise-fields
      (let ((event-pointer (pixelisp.internal:%ptr native)))
        (list (cffi:foreign-slot-value event-pointer '(:struct %sdl-mouse-wheel-event) 'precise-x)
              (cffi:foreign-slot-value event-pointer '(:struct %sdl-mouse-wheel-event) 'precise-y)))
      (list (float (%field native :wheel :x) 1.0)
            (float (%field native :wheel :y) 1.0))))
