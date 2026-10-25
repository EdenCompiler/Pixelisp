(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defun %post-selection-events (types)
  (dolist (type types)
    (px.event:post (px.event:make-event type))))

(test event-get-include-exclude-limit-and-order
  (px:with-init (:video nil)
    (let ((pixelisp.event::*queue* nil))
      (%post-selection-events '(:first :skip :second :skip :third))
      (is (equal '(:first :second)
                 (mapcar #'px.event:type (px.event:get :exclude :skip :limit 2 :pump nil))))
      (is (equal '(:skip :skip :third)
                 (mapcar #'px.event:type (px.event:get :pump nil))))
      (%post-selection-events '(:first :skip :second))
      (is (equal '(:first)
                 (mapcar #'px.event:type (px.event:get :types '(:first :second) :limit 1 :pump nil))))
      (is (equal '(:skip :second)
                 (mapcar #'px.event:type (px.event:get :pump nil)))))))

(test event-get-validates-before-pumping-or-consuming
  (px:with-init (:video nil)
    (let ((pixelisp.event::*queue* nil)
          (pixelisp.time::*timers* nil))
      (%post-selection-events '(:keep :other))
      (px.time:set-timer :deferred-selection 1 :loops 1)
      (px.time:delay 5)
      (signals error (px.event:get :types :keep :exclude :other))
      (signals error (px.event:get :types :keep :limit -1))
      (signals error (px.event:get :types :keep :pump :sometimes))
      ;; Validation failures neither remove existing events nor pump due timers.
      (is (equal '(:keep :other)
                 (mapcar #'px.event:type (px.event:get :pump nil))))
      (is (null (px.event:get :types :deferred-selection :pump nil)))
      (is (= 1 (length (px.event:get :types :deferred-selection)))))))

(test event-no-pump-clear-peek-and-hook-behavior
  (px:with-init (:video nil)
    (let ((pixelisp.event::*queue* nil)
          (pixelisp.internal:*pump-hooks*
            (cons (lambda () (px.event:post (px.event:make-event :from-pump)))
                  pixelisp.internal:*pump-hooks*)))
      (%post-selection-events '(:first :second))
      ;; Existing positional calls continue to work, and :PUMP requires a NIL
      ;; placeholder for the optional type argument.
      (is (px.event:peek :first))
      (is (px.event:peek nil :pump nil))
      (is (not (px.event:peek :missing :pump nil)))
      (px.event:clear :first :pump nil)
      (is (equal '(:second :from-pump)
                 (mapcar #'px.event:type (px.event:get :pump nil))))
      ;; A pumping call runs the hook; a no-pump call did not.
      (is (equal '(:from-pump)
                 (mapcar #'px.event:type (px.event:get)))))))

(test event-no-pump-selection-is-video-thread-guarded
  (px:with-init ()
    ;; Use the shared queue here: worker threads do not inherit LET bindings of
    ;; special variables from this thread.
    (px.event:clear nil :pump nil)
    (progn
      (let ((worker (bt:make-thread
                      (lambda ()
                        (handler-case (px.event:get :pump nil)
                          (px:initialization-error () :guarded))))))
        (is (eq :guarded (bt:join-thread worker))))
      (let ((worker (bt:make-thread
                      (lambda ()
                        (px.event:post (px.event:make-event :worker-selection))))))
        (bt:join-thread worker))
      (is (equal '(:worker-selection)
                 (mapcar #'px.event:type (px.event:get :types :worker-selection :pump nil)))))))
