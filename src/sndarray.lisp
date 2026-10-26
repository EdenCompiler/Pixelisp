;;;; Sound arrays deliberately distinguish copies from live views.
;;;; The mixer owns native sample memory. A live view keeps its Sound alive and
;;;; checks ownership on every access; explicit Sound disposal invalidates it.
(defpackage #:pixelisp.sndarray
  (:use #:cl) (:nicknames #:px.sndarray) (:shadow #:array)
  (:export #:array #:samples #:make-sound #:get-arraytype #:get-arraytypes #:use-arraytype))
(in-package #:pixelisp.sndarray)

(defun %dimensions (sound)
  (let ((frames (px.mixer:sound-frame-count sound)) (channels (px.mixer:sound-channels sound)))
    (if (= channels 1) (list frames) (list frames channels))))

(defun array (sound)
  "Copy SOUND samples using its mixer element type (including SINGLE-FLOAT for :SIZE 32)."
  (let ((result (make-array (%dimensions sound) :element-type (px.mixer:sound-element-type sound))))
    (dotimes (frame (px.mixer:sound-frame-count sound) result)
      (dotimes (channel (px.mixer:sound-channels sound))
        (setf (row-major-aref result (+ (* frame (px.mixer:sound-channels sound)) channel))
              (px.mixer:sound-sample-ref sound frame channel))))))

(defun samples (sound)
  "Return a live mutable view with native sample strides; float32 samples use four-byte steps.
Changes affect subsequent playback; SINGLE-FLOAT values outside [-1, 1] are preserved."
  (let* ((channels (px.mixer:sound-channels sound))
         (bytes (/ (abs (px.mixer:sample-format sound)) 8)))
    (px.buffer:make-view
     :owner sound :dimensions (%dimensions sound) :element-type (px.mixer:sound-element-type sound)
     :strides (if (= channels 1) (list bytes) (list (* channels bytes) bytes))
     :reader (lambda (frame &optional (channel 0)) (px.mixer:sound-sample-ref sound frame channel))
     :writer (lambda (value frame &optional (channel 0)) (px.mixer:sound-sample-set sound value frame channel)))))

(defun make-sound (array)
  "Create an independent playable Sound from an array matching the mixer format."
  (px.mixer:make-sound nil :array array))
(defun get-arraytype () :common-lisp)
(defun get-arraytypes () '(:common-lisp))
(defun use-arraytype (type)
  (unless (member type '(:common-lisp :lisp))
    (error 'pixelisp:unsupported-feature :operation 'use-arraytype :message "This native library uses Common Lisp arrays"))
  :common-lisp)
