(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test display-automatic-size-and-monitor-selection
  (px:with-init ()
    (let ((desktop (getf (px.display:get-display-info) :desktop-size)))
      (is (equal desktop (px.surface:size (px.display:set-mode))))
      (is (equal (list (first desktop) 13)
                 (px.surface:size (px.display:set-mode '(0 13) :display 0))))
      (is (equal (list 17 (second desktop))
                 (px.surface:size (px.display:set-mode #(17 0) :display 0))))
      (is (= 0 (cffi:foreign-funcall "SDL_GetWindowDisplayIndex"
                                    :pointer (pixelisp.internal:%ptr (px.display:get-window)) :int))))))

(test rejected-display-requests-preserve-the-current-framebuffer
  (px:with-init ()
    (let ((screen (px.display:set-mode '(32 24))))
      (px.surface:fill screen '(20 40 60))
      (signals type-error (px.display:set-mode '(-1 24)))
      (signals type-error (px.display:set-mode '(1/2 24)))
      (signals error (px.display:set-mode '(32 24) :display (px.display:get-num-displays)))
      (is (eq screen (px.display:get-surface)))
      (is (equal '(20 40 60 255) (px.color:to-list (px.surface:get-at screen '(1 1))))))))

(test display-mode-query-does-not-create-or-replace-a-window
  (px:with-init ()
    (let* ((desktop (getf (px.display:get-display-info) :desktop-size))
           (screen nil))
      (is (null (px.display:get-surface)))
      (is (integerp (px.display:mode-ok '(32 24))))
      (is (= 0 (px.display:mode-ok '(32 24) :depth 7)))
      (is (plusp (px.display:mode-ok desktop :fullscreen t)))
      (is (= (ldb (byte 8 8) (getf (px.display:get-display-info) :pixel-format))
             (px.display:mode-ok desktop :fullscreen t)))
      (is (= 0 (px.display:mode-ok '(30000 30000) :fullscreen t)))
      (is (null (px.display:get-surface)))
      (setf screen (px.display:set-mode '(32 24)))
      (px.display:mode-ok desktop :flags '(:fullscreen))
      (is (eq screen (px.display:get-surface)))
      (signals type-error (px.display:mode-ok '(-1 24)))
      (signals type-error (px.display:mode-ok '(32 24) :depth 1/2))
      (signals error (px.display:mode-ok '(32 24) :display (px.display:get-num-displays))))))

(test display-mode-queries-and-active-state-check-owner-thread
  (is-false (px.display:get-active))
  (signals px:initialization-error (px.display:mode-ok '(32 24)))
  (px:with-init ()
    (px.display:set-mode '(32 24))
    (let ((failures nil))
      (bt:join-thread
       (bt:make-thread
        (lambda ()
          (dolist (operation (list (lambda () (px.display:mode-ok '(32 24)))
                                  (lambda () (px.display:get-active))))
            (push (handler-case (funcall operation)
                    (px:initialization-error (condition) condition)) failures)))))
      (is (= 2 (length failures)))
      (is (every (lambda (condition) (typep condition 'px:initialization-error)) failures)))))

(test display-active-state-follows-native-visibility
  (px:with-init ()
    (px.display:set-mode '(32 24) :flags '(:hidden))
    (is-false (px.display:get-active))
    (sdl2:show-window (px.display:get-window))
    (is (px.display:get-active))
    (sdl2:hide-window (px.display:get-window))
    (is-false (px.display:get-active))
    (px.display:quit)
    (is-false (px.display:get-active))))
