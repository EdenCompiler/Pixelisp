(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defun %mixer-init-spec ()
  (multiple-value-list (px.mixer:get-init)))

(test mixer-init-selects-enumerated-device
  (let ((devices (px.sdl2.audio:devices)))
    (is (consp devices))
    (let ((device (first devices)))
      (unwind-protect
           (progn
             (is (stringp device))
             (is (px.mixer:init :device-name device :frequency 22050 :size -16
                                :channels 2 :buffer 256 :allowed-changes 5))
             (is (equal '(22050 -16 2) (%mixer-init-spec))))
        (px.mixer:quit)))))

(test mixer-allowed-change-flags-and-validation
  (is (= 0 (px.mixer::%allowed-changes nil))) ; Empty flag list means strict.
  (unwind-protect
       (progn
         (is (px.mixer:init :frequency 22050 :size -16 :channels 2 :allowed-changes 5))
         (is (equal '(22050 -16 2) (%mixer-init-spec)))
         ;; Reinitializing an open mixer remains an identity operation.
         (is (px.mixer:init :frequency 32000 :size 32 :channels 1 :allowed-changes 0))
         (is (equal '(22050 -16 2) (%mixer-init-spec)))
         (px.mixer:quit)
         (is (px.mixer:init :frequency 22050 :size -16 :channels 2
                            :allowed-changes '(:frequency :channels)))
         (is (equal '(22050 -16 2) (%mixer-init-spec)))
         (px.mixer:quit)
         (is (px.mixer:init :frequency 22050 :size -16 :channels 2 :allowed-changes 0))
         (is (equal '(22050 -16 2) (%mixer-init-spec)))
         (px.mixer:quit)
         (signals px:error (px.mixer:init :allowed-changes '(:unknown)))
         (signals px:error (px.mixer:init :allowed-changes 16))
         (signals px:error (px.mixer:init :allowed-changes "frequency"))
         (signals px:error (px.mixer:init :allowed-changes '(:frequency . :channels)))
         (let ((circular-flags (list :frequency)))
           (setf (cdr circular-flags) circular-flags)
           (signals px:error (px.mixer:init :allowed-changes circular-flags)))
         (signals type-error (px.mixer:init :frequency #x80000000))
         (signals type-error (px.mixer:init :buffer #x80000000))
         (signals type-error (px.mixer:init :buffer 1.5))
         (signals type-error (px.mixer:init :device-name 17))
         (signals px:error
           (px.mixer:init :device-name (concatenate 'string "bad" (string #\Null) "name")))
         (is (null (px.mixer:get-init))))
    (px.mixer:quit)))

(test mixer-pre-init-zero-defaults-and-restoration
  (let ((px.mixer::*settings* (copy-list px.mixer::*settings*)))
    (unwind-protect
         (progn
           (px.mixer:pre-init :frequency 32000 :size 32 :channels 1 :buffer 256
                              :allowed-changes '(:frequency :channels))
           (is (= 256 (fourth px.mixer::*settings*)))
           ;; Pygame rounds non-power-of-two chunks upward before SDL receives them.
           (px.mixer:pre-init :buffer 300)
           (is (= 512 (fourth px.mixer::*settings*)))
           (px.mixer:pre-init :frequency 32000 :size 32 :channels 1 :buffer 256
                              :allowed-changes '(:frequency :channels))
           ;; Pygame-compatible zero arguments select the pre-init values;
           ;; -1 for flags selects the pre-init allowed-change mask.
           (is (px.mixer:init :frequency 0 :size 0 :channels 0 :buffer 0
                              :allowed-changes -1))
           (is (equal '(32000 32 1) (%mixer-init-spec)))
           (px.mixer:quit)
           ;; A failed device open must leave the mixer uninitialized and usable.
           (signals px:initialization-error
             (px.mixer:init :device-name "pixelisp-device-that-does-not-exist"))
           (is (null (px.mixer:get-init)))
           (is (px.mixer:init :frequency 22050 :size -16 :channels 1))
           (is (equal '(22050 -16 1) (%mixer-init-spec))))
      (px.mixer:quit))))

(test mixer-buffer-minimum-and-power-of-two-rounding
  (let ((px.mixer::*settings* (copy-list px.mixer::*settings*)))
    (unwind-protect
         (progn
           (px.mixer:pre-init :buffer 1)
           (is (= 256 (fourth px.mixer::*settings*)))
           (px.mixer:pre-init :buffer 513)
           (is (= 1024 (fourth px.mixer::*settings*))))
      (px.mixer:quit))))

(test mixer-query-reports-float32
  (unwind-protect
       (progn
         (is (px.mixer:init :frequency 22050 :size 32 :channels 1 :allowed-changes 0))
         (is (equal '(22050 32 1) (%mixer-init-spec))))
    (px.mixer:quit)))
