;;;; Backend-sensitive SDL window operations: global mouse mode and X11 focus.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test window-extra-relative-mode-validates-window-and-round-trips-global-state
  (px:with-init (:video t)
    (px.sdl2.video:with-window (first :hidden t)
      (px.sdl2.video:with-window (second :hidden t)
        (let ((original (px.sdl2.video:window-relative-mouse-p first)))
          (unwind-protect
               (progn
                 (signals type-error
                   (setf (px.sdl2.video:window-relative-mouse-p first) :yes))
                 ;; SDL relative mode is global: querying through a second
                 ;; window observes the mode set through the first.
                 (handler-case
                     (progn
                       (setf (px.sdl2.video:window-relative-mouse-p first) t)
                       (is (px.sdl2.video:window-relative-mouse-p second))
                       (setf (px.sdl2.video:window-relative-mouse-p second) nil)
                       (is (not (px.sdl2.video:window-relative-mouse-p first))))
                   (px:unsupported-feature ()
                     ;; Some video backends cannot enable relative mode.
                     (is (not (px.sdl2.video:window-relative-mouse-p first)))))
            (ignore-errors (setf (px.sdl2.video:window-relative-mouse-p first) original)))))))))

(test window-extra-focus-input-only-reports-backend-capability
  (px:with-init (:video t)
    (px.sdl2.video:with-window (window :hidden t)
      (is (eq window (px.sdl2.video:focus-window window)))
      (signals type-error (px.sdl2.video:focus-window window :input-only :yes))
      (handler-case
          (is (eq window (px.sdl2.video:focus-window window :input-only t)))
        (px:unsupported-feature () (is-true t))))))

(test window-extra-modal-parent-validates-both-window-kinds-and-identity
  (px:with-init (:video t)
    (px.sdl2.video:with-window (child :hidden t)
      (px.sdl2.video:with-window (parent :hidden t)
        (px.sdl2.video:with-renderer (renderer child)
          (signals type-error (px.sdl2.video:set-modal-for renderer parent))
          (signals type-error (px.sdl2.video:set-modal-for child renderer))
          (signals error (px.sdl2.video:set-modal-for child child))
          (handler-case
              (is (eq child (px.sdl2.video:set-modal-for child parent)))
            (px:unsupported-feature () (is-true t))))))))

(test opt-in-x11-window-modal-and-input-focus
  (if (not (equal "1" (uiop:getenv "PIXELISP_TEST_X11")))
      (skip "Set PIXELISP_TEST_X11=1 under Xvfb to check X11 modal and input-only focus.")
      (px:with-init (:video t)
        (px.sdl2.video:with-window (parent :size '(64 48))
          (px.sdl2.video:with-window (child :size '(32 24))
            (is (eq child (px.sdl2.video:set-modal-for child parent)))
            (is (eq child (px.sdl2.video:focus-window child :input-only t))))))))


(defun %extra-window-operations (window parent)
  ;; Share the same operation list across lifetime and worker-thread checks.
  (list (lambda () (px.sdl2.video:window-relative-mouse-p window))
        (lambda () (setf (px.sdl2.video:window-relative-mouse-p window) nil))
        (lambda () (px.sdl2.video:focus-window window :input-only t))
        (lambda () (px.sdl2.video:set-modal-for window parent))
        (lambda () (px.sdl2.video:set-modal-for parent window))))

(test window-extra-rejects-wrong-kinds-closed-windows-and-workers
  (px:with-init (:video t)
    (px.sdl2.video:with-window (parent :hidden t)
      (px.sdl2.video:with-window (window :hidden t)
        (px.sdl2.video:with-renderer (renderer window)
          (dolist (bad (list nil renderer))
            (dolist (operation (%extra-window-operations bad parent))
              (signals type-error (funcall operation)))))
        ;; Join each bounded worker before inspecting its captured condition.
        ;; No native call should occur on that worker's thread.
        (dolist (operation (%extra-window-operations window parent))
          (let ((failure nil))
            (bt:join-thread
             (bt:make-thread
              (lambda ()
                (setf failure (handler-case (progn (funcall operation) nil)
                                (error (condition) condition))))))
            (is (typep failure 'px:initialization-error)))))
      (let ((closed (px.sdl2.video:make-window :hidden t)))
        (px.sdl2.video:close closed)
        (dolist (operation (%extra-window-operations closed parent))
          (signals px:disposed-resource (funcall operation)))))))
