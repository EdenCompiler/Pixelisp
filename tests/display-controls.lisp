(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test display-controls-require-initialized-video
  (let ((pixelisp.internal:*initialized* nil)
        (pixelisp.internal:*video-thread* nil)
        (px.display::*window* nil))
    (signals px:initialization-error (px.display:iconify))
    (signals px:initialization-error (px.display:get-allow-screensaver))
    (signals px:initialization-error (px.display:set-allow-screensaver t))))

(test display-controls-require-video-owner-thread
  (px:with-init (:video t)
    (px.display:set-mode '(32 24))
    (let ((failures nil))
      (let ((thread
              (bt:make-thread
               (lambda ()
                 (dolist (operation
                           (list (lambda () (px.display:iconify))
                                 (lambda () (px.display:get-allow-screensaver))
                                 (lambda () (px.display:set-allow-screensaver t))))
                   (push (handler-case (funcall operation)
                           (px:initialization-error (condition) condition))
                         failures))))))
        (bt:join-thread thread))
      (is (= 3 (length failures)))
      (is (every (lambda (failure) (typep failure 'px:initialization-error)) failures))
      (px.display:quit))))

(test iconify-needs-a-current-window-and-returns-request-status
  (px:with-init (:video t)
    (signals px:initialization-error (px.display:iconify))
    (px.display:set-mode '(32 24))
    ;; SDL_MinimizeWindow is void. A true result means the request was issued
    ;; for the current live window; a window manager may process it later.
    (is (eq t (px.display:iconify)))
    (px.display:quit)
    (signals px:initialization-error (px.display:iconify))))

(test screensaver-controls-roundtrip-and-restore-host-state
  (px:with-init (:video t)
    ;; SDL's screensaver setting belongs to the host session, so preserve and
    ;; restore its initial value even if an assertion or native call fails.
    (let ((initial (px.display:get-allow-screensaver)))
      (unwind-protect
           (progn
             (is (eq nil (px.display:set-allow-screensaver nil)))
             (is (not (px.display:get-allow-screensaver)))
             (is (eq t (px.display:set-allow-screensaver t)))
             (is (px.display:get-allow-screensaver))
             (signals type-error (px.display:set-allow-screensaver :yes)))
        (px.display:set-allow-screensaver initial)))))

(test screensaver-control-does-not-require-an-open-window
  (px:with-init (:video t)
    (let ((initial (px.display:get-allow-screensaver)))
      (unwind-protect
           (progn
             (px.display:set-mode '(32 24))
             (px.display:quit)
             (is (member (px.display:get-allow-screensaver) '(t nil)))
             (is (eq nil (px.display:set-allow-screensaver nil)))
             (is (not (px.display:get-allow-screensaver))))
        (px.display:set-allow-screensaver initial)))))
