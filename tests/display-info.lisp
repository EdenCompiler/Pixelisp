(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test display-queries-require-initialized-video
  (let ((pixelisp.internal:*initialized* t)
        (pixelisp.internal:*video-thread* nil))
    (signals px:initialization-error (px.display:get-driver))
    (signals px:initialization-error (px.display:get-num-displays))
    (signals px:initialization-error (px.display:list-modes))
    (signals px:initialization-error (px.display:get-display-info))))

(test display-queries-validate-index-and-thread
  (px:with-init (:video t)
    (is (plusp (px.display:get-num-displays)))
    (signals type-error (px.display:list-modes :display -1))
    (signals simple-error
      (px.display:list-modes :display (px.display:get-num-displays)))
    (signals simple-error
      (px.display:get-display-info (px.display:get-num-displays)))
    (let ((failure nil))
      (let ((thread (bt:make-thread
                     (lambda ()
                       (setf failure
                             (handler-case (progn (px.display:get-num-displays) nil)
                               (px:initialization-error (condition) condition)))))))
        (bt:join-thread thread))
      (is (typep failure 'px:initialization-error)))))

(test display-modes-and-info-are-copied
  (px:with-init (:video t)
    (is (stringp (px.display:get-driver)))
    (let* ((modes (px.display:list-modes))
           (again (px.display:list-modes))
           (info (px.display:get-display-info))
           (info-again (px.display:get-display-info)))
      ;; Some SDL video backends report no enumerated modes; NIL is a valid
      ;; result. When present, SDL's native ordering and size pairs are kept.
      (is (listp modes))
      (is (equal modes again))
      (is (equal (remove-duplicates modes :test #'equal :from-end t) modes))
      (is (every (lambda (size)
                   (and (= 2 (length size))
                        (every (lambda (dimension) (and (integerp dimension) (plusp dimension))) size)))
                 modes))
      (is (equal (getf info :desktop-size) (getf info-again :desktop-size)))
      (is (equal (getf info :current-size) (getf info-again :current-size)))
      (is (integerp (getf info :pixel-format)))
      (is (integerp (getf info :pixel-depth)))
      (is (integerp (getf info :refresh-rate)))
      (setf (first (getf info :desktop-size)) -1)
      (is (plusp (first (getf info-again :desktop-size))))
      (when modes
        (setf (first modes) '(1 1))
        (is (not (equal modes again)))))))
