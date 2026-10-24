(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defun %repeat-test-native-key (type &key (keycode 97) (scancode 4) (repeat 0))
  "Decode a small real SDL key event without depending on physical input."
  (sdl2:with-sdl-event (native type)
    (setf (native :key :keysym :sym) keycode
          (native :key :keysym :scancode) scancode
          (native :key :keysym :mod) 0
          (native :key :repeat) repeat)
    (px.event::%decode-native native)))

(defun %repeat-test-push-native-key (type &key (keycode 97) (scancode 4) (repeat 0))
  "Push a key transition through SDL's real event queue."
  (sdl2:with-sdl-event (native type)
    (setf (native :key :keysym :sym) keycode
          (native :key :keysym :scancode) scancode
          (native :key :keysym :mod) 0
          (native :key :repeat) repeat)
    (sdl2:push-event native)))

(defun %repeat-test-accept (event now)
  (when (px.key::%handle-native-key-repeat event now)
    (px.event:post event)))

(defun %repeat-test-queued ()
  (bt:with-lock-held (px.event::*queue-lock*)
    (copy-list px.event::*queue*)))

(test key-repeat-requires-video-and-owner-thread
  (let ((pixelisp.internal:*initialized* nil)
        (pixelisp.internal:*video-thread* nil))
    (signals px:initialization-error (px.key:set-repeat 10 5))
    (signals px:initialization-error (px.key:get-repeat)))
  (let ((pixelisp.internal:*initialized* t)
        (pixelisp.internal:*video-thread* (gensym "NON-OWNER-THREAD")))
    (signals px:initialization-error (px.key:set-repeat 10 5))
    (signals px:initialization-error (px.key:get-repeat))))

(test key-repeat-disabled-suppresses-sdl-repeat-but-keeps-initial-down
  (let ((px.key::*repeat-delay* 0)
        (px.key::*repeat-interval* 0)
        (px.key::*repeat-press* nil)
        (px.key::*repeat-next* nil)
        (px.event::*queue* nil))
    (%repeat-test-accept (%repeat-test-native-key :keydown) 100)
    (%repeat-test-accept (%repeat-test-native-key :keydown :repeat 1) 150)
    (is (= 1 (length (%repeat-test-queued))))
    (is (null (px.event:attribute (first (%repeat-test-queued)) :repeat)))))

(test native-repeat-key-events-use-the-production-pump
  (px:with-init ()
    (unwind-protect
         (progn
           (px.event:clear)
           (px.key:set-repeat 100000 10)
           (%repeat-test-push-native-key :keydown)
           (%repeat-test-push-native-key :keydown :repeat 1)
           (px.event:pump)
           (let* ((events (px.event:get :types :key-down))
                  (matching (remove-if-not
                             (lambda (event) (eql 97 (px.event:attribute event :keycode)))
                             events)))
             (is (= 1 (length matching)))
             (is (null (px.event:attribute (first matching) :repeat))))
           (is (= 97 (px.event:attribute px.key::*repeat-press* :keycode)))
           (is (integerp px.key::*repeat-next*)))
      (px.key:set-repeat)
      (px.event:clear))))

(test key-repeat-ignores-worker-posted-synthetic-keydowns
  (px:with-init ()
    (unwind-protect
         (let ((px.key::*repeat-press* nil)
               (px.key::*repeat-next* nil)
               (px.event::*queue* nil))
           (px.key:set-repeat 10 2)
           (px.event:post (px.event:make-event :key-down :key :A :keycode 97))
           (px.key::%update-key-repeat 100)
           (is (= 1 (length (%repeat-test-queued))))
           (is (null px.key::*repeat-press*)))
      (px.event:clear)
      (px.key:set-repeat))))

(test key-repeat-delay-interval-and-coalescing
  (px:with-init ()
    (unwind-protect
         (let ((px.key::*repeat-press* nil)
               (px.key::*repeat-next* nil)
               (px.event::*queue* nil))
           (px.key:set-repeat 100 20)
           (is (equal '(100 20) (px.key:get-repeat)))
           (%repeat-test-accept (%repeat-test-native-key :keydown) 1000)
           (is (= 1 (length (%repeat-test-queued))))
           ;; The tracked copy must not share attributes with the initial event.
           (setf (px.event:attribute (first (%repeat-test-queued)) :keycode) 999
                 (px.event:attribute (first (%repeat-test-queued)) :key) :X)
           (px.key::%update-key-repeat 1099)
           (is (= 1 (length (%repeat-test-queued))))
           (px.key::%update-key-repeat 1100)
           (is (= 2 (length (%repeat-test-queued))))
           (let ((repeated (second (%repeat-test-queued))))
             (is (eq :key-down (px.event:type repeated)))
             (is (eq :A (px.event:attribute repeated :key)))
             (is (= 97 (px.event:attribute repeated :keycode)))
             (setf (px.event:attribute repeated :keycode) 999)
             (is (px.event:attribute repeated :repeat)))
           (px.key::%update-key-repeat 1120)
           (is (= 97 (px.event:attribute (third (%repeat-test-queued)) :keycode)))
           ;; A long stall produces one event and schedules from the current pump.
           (px.key::%update-key-repeat 10000)
           (is (= 4 (length (%repeat-test-queued))))
           (is (= 10020 px.key::*repeat-next*))
           ;; A provided delay with interval zero repeats at the delay.
           (px.key:set-repeat 45 0)
           (is (equal '(45 45) (px.key:get-repeat)))
           (is (null px.key::*repeat-press*)))
      (px.event:clear)
      (px.key:set-repeat))))

(test key-repeat-keyup-and-focus-loss-cancel-the-held-key
  (px:with-init ()
    (unwind-protect
         (let ((px.key::*repeat-press* nil)
               (px.key::*repeat-next* nil))
           (px.key:set-repeat 10 3)
           (%repeat-test-accept (%repeat-test-native-key :keydown) 50)
           (%repeat-test-accept (%repeat-test-native-key :keyup :keycode 98 :scancode 5) 55)
           (is (typep px.key::*repeat-press* 'px.event:event))
           (%repeat-test-accept (%repeat-test-native-key :keyup) 60)
           (is (null px.key::*repeat-press*))
           (%repeat-test-accept (%repeat-test-native-key :keydown) 70)
           (%repeat-test-accept (px.event:make-event :window-event :event 13) 75)
           (is (null px.key::*repeat-press*))
           (is (null px.key::*repeat-next*)))
      (px.key:set-repeat))))

(test key-repeat-validation-is-atomic-and-setting-clears-pending
  (px:with-init ()
    (unwind-protect
         (progn
           (px.key:set-repeat 80 7)
           (%repeat-test-accept (%repeat-test-native-key :keydown) 100)
           (signals type-error (px.key:set-repeat 20 -1))
           (is (equal '(80 7) (px.key:get-repeat)))
           (is (typep px.key::*repeat-press* 'px.event:event))
           (signals type-error (px.key:set-repeat -1 20))
           (is (equal '(80 7) (px.key:get-repeat)))
           (px.key:set-repeat 0 200)
           (is (equal '(0 200) (px.key:get-repeat)))
           (is (null px.key::*repeat-press*)))
      (px.key:set-repeat))))

(test key-repeat-quit-reinitializes-disabled
  (px:with-init ()
    (px.key:set-repeat 80 7)
    (px.key::%handle-native-key-repeat (%repeat-test-native-key :keydown) 100)
    (px:quit)
    (px:init)
    (is (equal '(0 0) (px.key:get-repeat)))
    (is (null px.key::*repeat-press*))))

(test event-empty-type-vector-selects-no-queued-events
  (let ((px.event::*queue* (list (px.event:make-event :queued-for-empty-filter))))
    (is (null (px.event:get :types #())))
    (is (= 1 (length px.event::*queue*)))))
