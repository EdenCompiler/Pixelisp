;;;; Bounded games use the production loop and event queue, with dummy devices.
(defpackage #:pixelisp.examples.tests (:use #:cl #:fiveam))
(in-package #:pixelisp.examples.tests)
(def-suite examples :description "Mini-game rules, input, rendering, and cleanup")
(in-suite examples)

(defun %clean-run-p ()
  (and (not (px:get-init)) (null pixelisp.internal:*resources*) (not (px.mixer:get-init))))

(test game-catalog-and-validation
  (let ((entries (px.examples:list-examples)))
    (is (= 4 (length entries)))
    (is (every (lambda (entry) (eq :game (getf entry :kind))) entries))
    (setf (char (getf (first entries) :name) 0) #\X)
    (is (string= "prism-breaker" (getf (first (px.examples:list-examples)) :name))))
  (signals error (px.examples:run-example "unknown"))
  (signals type-error (px.examples:run-example "prism-breaker" :frames -1))
  (signals type-error (px.examples:run-example "prism-breaker" :seed -1))
  (signals type-error (px.examples:run-example "prism-breaker" :fixed-dt 1))
  (is (%clean-run-p)))

(test all-games-render-without-audio-and-release-their-assets
  (dolist (entry (px.examples:list-examples))
    (let ((snapshot (px.examples:run-example (getf entry :name) :frames 2 :fps 0
                                            :fixed-dt 0.02d0 :audio nil)))
      (is (eq :playing (getf snapshot :status)))
      (is (= 2 (getf snapshot :frames)))
      (is (= 0 (getf snapshot :score)))
      (is (not (getf snapshot :audio)))
      (is (%clean-run-p)))))

(test synthesized-melody-plays-with-dummy-audio
  (let ((snapshot (px.examples:run-example "echo-grove" :frames 20 :fps 0
                                          :fixed-dt 0.05d0 :audio t)))
    (is (getf snapshot :audio))
    (is (member (getf snapshot :phase) '(:lit :input)))
    (is (%clean-run-p))))

(test runner-pause-resume-and-quit-use-the-event-queue
  (let ((frame 0))
    (let ((pixelisp.internal:*pump-hooks*
            (cons (lambda ()
                    (case (incf frame)
                      (1 (px.event:post (px.event:make-event :key-down :key :up)))
                      (2 (px.event:post (px.event:make-event :key-down :key :p)))
                      (3 (px.event:post (px.event:make-event :key-up :key :p))
                         (px.event:post (px.event:make-event :key-down :key :p)))
                      (4 (px.event:post (px.event:make-event :quit)))))
                  pixelisp.internal:*pump-hooks*)))
      (let ((snapshot (px.examples:run-example "orbit-patrol" :frames 20 :fps 0
                                              :fixed-dt 0.02d0 :audio nil)))
        (is (= 4 (getf snapshot :frames)))
        (is (< (abs (- 0.04d0 (getf snapshot :elapsed))) 1d-8))
        (is (not (getf snapshot :paused))))))
  (is (%clean-run-p)))

(test restart-reuses-art-for-every-game
  (dolist (entry (px.examples:list-examples))
    (let ((counts nil) (frame 0))
      (let ((pixelisp.internal:*pump-hooks*
              (cons (lambda ()
                      (push (length pixelisp.internal:*resources*) counts)
                      (incf frame)
                      (px.event:post (px.event:make-event :key-up :key :r))
                      (px.event:post (px.event:make-event :key-down :key :r)))
                    pixelisp.internal:*pump-hooks*)))
        (let ((snapshot (px.examples:run-example (getf entry :name) :frames 3 :fps 0
                                                :fixed-dt 0.02d0 :audio nil)))
          (is (= 0 (getf snapshot :score)))
          (is (eq :playing (getf snapshot :status)))
          (is (= 3 frame))
          (is (apply #'= counts)))))
    (is (%clean-run-p))))

(test runner-callback-failure-cleans-up
  (let ((pixelisp.internal:*pump-hooks*
          (cons (lambda () (error "Injected event callback failure"))
                pixelisp.internal:*pump-hooks*)))
    (signals simple-error (px.examples:run-example "prism-breaker" :frames 1 :audio nil)))
  (is (%clean-run-p)))

(test input-tracking-releases-keys-on-focus-loss
  (let ((session (px.examples::make-game-session)))
    (px.examples::%track-input session (px.event:make-event :key-down :key :up))
    (is (px.examples::%held-p session :up))
    (px.examples::%track-input session (px.event:make-event :window-event :event 13))
    (is (not (px.examples::%held-p session :up)))
    (px.examples::%track-input session (px.event:make-event :mouse-motion :pos #(123 234)))
    (is (equal '(123 234) (px.examples::session-mouse-pos session)))))

(test screenshot-is-a-rendered-game-frame
  (let ((path (merge-pathnames (format nil "pixelisp-game-~A.png" (gensym))
                              (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (px.examples:play :frames 0 :audio nil :screenshot path)
           (is (not (null (probe-file path))))
           (px:with-init (:video nil)
             (px:with-resource (image (px.image:load path))
               (is (equal '(900 620) (px.surface:size image)))
               ;; A brick's center is game art, not the background or an export sheet.
               (is (> (px:color-r (px.surface:get-at image '(80 154))) 200)))))
      (when (probe-file path) (delete-file path))))
  (is (%clean-run-p)))
