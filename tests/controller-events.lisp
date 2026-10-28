(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defun %device-test-button (native controller-p which button state)
  "Write the real binding fields; union member names are compile-time paths."
  (if controller-p
      (setf (px.event::%field native :cbutton :which) which
            (px.event::%field native :cbutton :button) button
            (px.event::%field native :cbutton :state) state)
      (setf (px.event::%field native :jbutton :which) which
            (px.event::%field native :jbutton :button) button
            (px.event::%field native :jbutton :state) state)))

(test device-button-events-use-public-keywords-and-copy-their-payload
  (dolist (spec '((:controllerbuttondown :controller-button-down :cbutton)
                  (:controllerbuttonup :controller-button-up :cbutton)
                  (:joybuttondown :joy-button-down :jbutton)
                  (:joybuttonup :joy-button-up :jbutton)))
    (destructuring-bind (native-type public-type field) spec
      (sdl2:with-sdl-event (native native-type)
        (%device-test-button native (eq field :cbutton) 51 2 1)
        (let ((event (px.event::%decode-native native)))
          ;; Changing the original union must not change the Lisp event.
          (%device-test-button native (eq field :cbutton) 99 0 0)
          (is (eq public-type (px.event:type event)))
          (is (= 51 (px.event:attribute event :which)))
          (is (= 2 (px.event:attribute event :button)))
          (is (= 1 (px.event:attribute event :state))))))))

(test device-hotplug-and-remapping-events-retain-their-identity
  (dolist (spec '((:controllerdeviceadded :controller-device-added :cdevice)
                  (:controllerdeviceremoved :controller-device-removed :cdevice)
                  (:controllerdeviceremapped :controller-device-remapped :cdevice)
                  (:joydeviceadded :joy-device-added :jdevice)
                  (:joydeviceremoved :joy-device-removed :jdevice)))
    (destructuring-bind (native-type public-type field) spec
      (sdl2:with-sdl-event (native native-type)
        (if (eq field :cdevice) (setf (native :cdevice :which) 73)
            (setf (native :jdevice :which) 73))
        (let ((event (px.event::%decode-native native)))
          (if (eq field :cdevice) (setf (native :cdevice :which) 0)
              (setf (native :jdevice :which) 0))
          (is (eq public-type (px.event:type event)))
          (is (= 73 (px.event:attribute event :which))))))))

(test controller-button-queue-selection-uses-the-documented-spelling
  (px:with-init ()
    (unwind-protect
         (progn
           (px.event:clear nil :pump nil)
           (sdl2:with-sdl-event (native :controllerbuttondown)
             (setf (native :cbutton :which) 47 (native :cbutton :button) 0
                   (native :cbutton :state) 1)
             (sdl2:push-event native))
           (let ((events (px.event:get :types :controller-button-down)))
             (is (= 1 (length events)))
             (when events (is (= 47 (px.event:attribute (first events) :which))))))
      (px.event:clear nil :pump nil))))
