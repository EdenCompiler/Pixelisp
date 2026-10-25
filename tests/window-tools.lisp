(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test window-controls-validate-resources-and-round-trip-basic-state
  (px:with-init (:video t)
    (px.sdl2.video:with-window (window :size '(40 30) :hidden t :resizable t)
      (is (plusp (px.sdl2.video:window-id window)))
      (is (typep (px.sdl2.video:window-display-index window) '(integer 0 *)))
      ;; SDL's dummy video driver accepts these void setter calls but does not
      ;; necessarily update its reported flags. Check accepted return values
      ;; here; the opt-in X11 test below checks state where SDL tracks it.
      (is (eq nil (setf (px.sdl2.video:window-resizable-p window) nil)))
      (is (member (px.sdl2.video:window-resizable-p window) '(t nil)))
      (is (eq t (setf (px.sdl2.video:window-resizable-p window) t)))
      (is (eq t (setf (px.sdl2.video:window-borderless-p window) t)))
      (is (member (px.sdl2.video:window-borderless-p window) '(t nil)))
      (is (eq nil (setf (px.sdl2.video:window-borderless-p window) nil)))
      (is (null (px.sdl2.video:window-fullscreen-mode window)))
      ;; Check that SDL accepts the request; window managers may apply it
      ;; asynchronously, so this does not assert the resulting flag state.
      (is (eq window (px.sdl2.video:set-fullscreen window :desktop t)))
      (is (eq window (px.sdl2.video:set-windowed window)))
      (is (eq window (px.sdl2.video:restore-window window)))
      (is (eq window (px.sdl2.video:focus-window window)))
      ;; A grab request need not become active on a hidden window. Preserve the
      ;; original setting and check only that the query remains boolean.
      (let ((initial (px.sdl2.video:window-grab-p window)))
        (unwind-protect
             (progn
               (setf (px.sdl2.video:window-grab-p window) t)
               (is (member (px.sdl2.video:window-grab-p window) '(t nil))))
          (setf (px.sdl2.video:window-grab-p window) initial)))
      (signals type-error (setf (px.sdl2.video:window-resizable-p window) :yes))
      (signals type-error (setf (px.sdl2.video:window-borderless-p window) 1))
      (signals type-error (setf (px.sdl2.video:window-grab-p window) :on)))))

(test opt-in-x11-window-flags-and-fullscreen-round-trip
  (if (not (equal "1" (uiop:getenv "PIXELISP_TEST_X11")))
      (skip "Set PIXELISP_TEST_X11=1 under Xvfb to check window flag state transitions.")
      (px:with-init (:video t)
        (px.sdl2.video:with-window (window :size '(64 48) :resizable t)
          (unwind-protect
               (progn
                 (is (px.sdl2.video:window-resizable-p window))
                 (setf (px.sdl2.video:window-resizable-p window) nil)
                 (is (not (px.sdl2.video:window-resizable-p window)))
                 (setf (px.sdl2.video:window-resizable-p window) t)
                 (is (px.sdl2.video:window-resizable-p window))
                 (setf (px.sdl2.video:window-borderless-p window) t)
                 (is (px.sdl2.video:window-borderless-p window))
                 (setf (px.sdl2.video:window-borderless-p window) nil)
                 (is (not (px.sdl2.video:window-borderless-p window)))
                 (px.sdl2.video:set-fullscreen window :desktop t)
                 (is (eq :desktop (px.sdl2.video:window-fullscreen-mode window)))
                 (px.sdl2.video:set-windowed window)
                 (is (null (px.sdl2.video:window-fullscreen-mode window))))
            (ignore-errors (px.sdl2.video:set-windowed window)))))))

(test window-controls-reject-non-window-resources-before-native-calls
  (px:with-init (:video t)
    (px.sdl2.video:with-window (window :hidden t)
      (px.sdl2.video:with-renderer (renderer window)
        (let ((texture (px.sdl2.video:make-texture renderer '(2 2)))
              (icon (px.surface:make-surface '(2 2) :alpha t)))
          (unwind-protect
               (dolist (bad (list renderer texture))
                 (dolist (operation
                           (list (lambda () (px.sdl2.video:window-id bad))
                                 (lambda () (px.sdl2.video:window-display-index bad))
                                 (lambda () (px.sdl2.video:window-resizable-p bad))
                                 (lambda () (setf (px.sdl2.video:window-resizable-p bad) t))
                                 (lambda () (px.sdl2.video:window-borderless-p bad))
                                 (lambda () (setf (px.sdl2.video:window-borderless-p bad) t))
                                 (lambda () (px.sdl2.video:window-opacity bad))
                                 (lambda () (setf (px.sdl2.video:window-opacity bad) 0.5))
                                 (lambda () (px.sdl2.video:window-fullscreen-mode bad))
                                 (lambda () (px.sdl2.video:set-fullscreen bad))
                                 (lambda () (px.sdl2.video:set-windowed bad))
                                 (lambda () (px.sdl2.video:maximize-window bad))
                                 (lambda () (px.sdl2.video:minimize-window bad))
                                 (lambda () (px.sdl2.video:restore-window bad))
                                 (lambda () (px.sdl2.video:focus-window bad))
                                 (lambda () (px.sdl2.video:window-grab-p bad))
                                 (lambda () (setf (px.sdl2.video:window-grab-p bad) t))
                                 (lambda () (px.sdl2.video:set-window-icon bad icon))))
                   (signals type-error (funcall operation))))
            (px.surface:dispose icon)
            (px.sdl2.video:close texture)))))))

(test window-controls-enforce-resource-lifecycle-and-video-thread
  (px:with-init (:video t)
    (let ((window (px.sdl2.video:make-window :hidden t)))
      (unwind-protect
           (let ((failure nil))
             (let ((thread (bt:make-thread
                            (lambda ()
                              (setf failure
                                    (handler-case (px.sdl2.video:window-id window)
                                      (px:initialization-error (condition) condition)))))))
               (bt:join-thread thread))
             (is (typep failure 'px:initialization-error)))
        (px.sdl2.video:close window))
      (signals px:disposed-resource (px.sdl2.video:window-id window)))))

(test window-icon-and-opacity-support-follow-native-capabilities
  (px:with-init (:video t)
    (px.sdl2.video:with-window (window :hidden t)
      (let ((icon (px.surface:make-surface '(8 8) :alpha t)))
        (unwind-protect
             (is (eq window (px.sdl2.video:set-window-icon window icon)))
          (px.surface:dispose icon)))
      (signals type-error (px.sdl2.video:set-window-icon window nil))
      (let ((locked (px.surface:make-surface '(2 2) :alpha t)))
        (unwind-protect
             (progn
               (px.surface:lock locked)
               (unwind-protect
                    (signals px:resource-in-use (px.sdl2.video:set-window-icon window locked))
                 (px.surface:unlock locked)))
          (px.surface:dispose locked)))
      ;; Some SDL video backends reject opacity. On those backends the API
      ;; reports a Pixelisp error; on capable backends verify a safe roundtrip.
      (handler-case
          (let ((initial (px.sdl2.video:window-opacity window)))
            (unwind-protect
                 (progn
                   (setf (px.sdl2.video:window-opacity window) 0.75)
                   (is (< (abs (- 0.75 (px.sdl2.video:window-opacity window))) 0.02)))
              (setf (px.sdl2.video:window-opacity window) initial)))
        (px:error (condition)
          (is (eq 'px.sdl2.video:window-opacity (px:operation condition))))
        (error () (fail "Opacity failed with an unclassified condition.")))
      (signals type-error (setf (px.sdl2.video:window-opacity window) 1.1)))))
