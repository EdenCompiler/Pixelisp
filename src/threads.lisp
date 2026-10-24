;;;; Thread helpers preserve values and propagate worker failures at JOIN.
(defpackage #:pixelisp.threads
  (:nicknames #:px.threads) (:use #:cl)
  (:export #:worker #:spawn #:join #:alive-p #:current-thread #:make-lock #:with-lock #:parallel-map))
(in-package #:pixelisp.threads)
(defclass worker () ((thread :accessor %thread) (values :initform nil :accessor %values) (failure :initform nil :accessor %failure)))
(defun spawn (function &key (name "pixelisp worker"))
  (check-type function function)
  (let ((worker (make-instance 'worker)))
    (setf (%thread worker)
          (bordeaux-threads:make-thread
           (lambda () (handler-case (setf (%values worker) (multiple-value-list (funcall function)))
                        (error (e) (setf (%failure worker) e)))) :name name)) worker))
(defun join (worker)
  (bordeaux-threads:join-thread (%thread worker))
  (when (%failure worker) (error (%failure worker)))
  (values-list (%values worker)))
(defun alive-p (worker) (bordeaux-threads:thread-alive-p (%thread worker)))
(defun current-thread () (bordeaux-threads:current-thread))
(defun make-lock (&optional (name "pixelisp lock")) (bordeaux-threads:make-lock name))
(defmacro with-lock ((lock) &body body) `(bordeaux-threads:with-lock-held (,lock) ,@body))
(defun parallel-map (function sequence &key (workers 4))
  "Map with a bounded worker pool; retain input order and re-signal failures."
  (check-type workers (integer 1 *))
  (let* ((input (coerce sequence 'vector)) (output (make-array (length input)))
         (next 0) (lock (make-lock "parallel-map"))
         (pool (loop repeat (min workers (length input)) collect
                 (spawn (lambda ()
                          (loop for index = (with-lock (lock) (when (< next (length input)) (prog1 next (incf next))))
                                while index do (setf (aref output index) (funcall function (aref input index)))))))))
    ;; Join every worker even when another failed; none outlive this operation.
    (let ((failure nil))
      (dolist (worker pool) (handler-case (join worker) (error (e) (unless failure (setf failure e)))))
      (when failure (error failure)))
    (if (listp sequence) (coerce output 'list) output)))

(defpackage #:pixelisp.fastevent
  (:nicknames #:px.fastevent) (:use #:cl) (:shadow #:get)
  (:export #:init #:get-init #:quit #:pump #:get #:post #:poll #:wait))
(in-package #:pixelisp.fastevent)
(defvar *initialized* nil)
(defun init () (setf *initialized* t))
(defun get-init () *initialized*)
(defun quit () (setf *initialized* nil))
(defun pump () (px.event:pump))
(defun get () (px.event:get))
(defun post (event) (px.event:post event))
(defun poll ()
  "Return the next queued event, or NIL if the queue is empty."
  (px.event:poll))
(defun wait (&optional timeout)
  "Wait for an event, returning NIL after TIMEOUT milliseconds when supplied."
  (px.event:wait timeout))
