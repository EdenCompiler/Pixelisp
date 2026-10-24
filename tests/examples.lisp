;;;; Bounded runs exercise the real example loops. Synthetic events go through
;;;; the production queue; no physical keyboard, mouse, or audio device is used.
(defpackage #:pixelisp.examples.tests (:use #:cl #:fiveam))
(in-package #:pixelisp.examples.tests)
(def-suite examples :description "Runnable example smoke and interaction checks")
(in-suite examples)

(test example-catalog-and-validation
  (let ((entries (px.examples:list-examples)))
    (is (= 16 (length entries)))
    (setf (char (getf (first entries) :name) 0) #\X)
    (is (string= "star-collector" (getf (first (px.examples:list-examples)) :name))))
  (signals error (px.examples:run-example "unknown"))
  (signals type-error (px.examples:run-example "sprite-lab" :frames -1))
  (signals error (px.examples:run-example "mask-lab" :output "unexpected.png"))
  (is (not (px:get-init))))

(test generated-example-surfaces-and-values
  (px:with-resource (pixels (px.examples:run-example "pixels"))
    (is (equal '(128 128) (px.surface:size pixels))))
  (px:with-resource (effects (px.examples:run-example "effects"))
    (is (equal '(512 144) (px.surface:size effects))))
  (px:with-resource (palette (px.examples:run-example "palette"))
    (is (equal '(384 192) (px.surface:size palette)))
    (is (equal '(255 99 71 255) (px.color:to-list (px.surface:get-at palette '(20 20))))))
  (px:with-resource (card (px.examples:run-example "rounded-ui"))
    (is (equal '(720 360) (px.surface:size card)))
    (is (equal '(70 130 180 255) (px.color:to-list (px.surface:get-at card '(130 146)))))
    (is (equal '(29 40 57 255) (px.color:to-list (px.surface:get-at card '(40 118))))))
  (px:with-resource (card (px.examples:run-example "pixel-match"))
    (is (equal '(620 380) (px.surface:size card)))
    (is (equal '(255 99 71 255) (px.color:to-list (px.surface:get-at card '(112 172)))))
    (is (equal '(255 215 0 255) (px.color:to-list (px.surface:get-at card '(412 172))))))
  (is (equal '((6 6) 4) (multiple-value-list (px.examples:run-example "mask-info"))))
  (is (null pixelisp.internal:*resources*)))

(test image-memory-and-display-query-recipes
  (px:with-resource (preview (px.examples:run-example "memory-image"))
    (is (equal '(128 128) (px.surface:size preview)))
    (is (equal '(255 0 0 255) (px.color:to-list (px.surface:get-at preview '(10 10)))))
    (is (equal '(255 255 0 128) (px.color:to-list (px.surface:get-at preview '(100 100))))))
  (let ((report (px.examples:run-example "display-info")))
    (is (stringp (getf report :driver)))
    (is (plusp (getf report :display-count)))
    (is (listp (getf report :modes))))
  (is (not (px:get-init)))
  (is (null pixelisp.internal:*resources*)))

(test sprite-lab-launches-a-shared-image-particle
  (let ((posted nil))
    (let ((pixelisp.internal:*pump-hooks*
            (cons (lambda ()
                    (unless posted
                      (setf posted t)
                      (px.event:post (px.event:make-event :mouse-button-down :pos '(480 260) :button 1))))
                  pixelisp.internal:*pump-hooks*)))
      (is (= 1 (px.examples:run-example "sprite-lab" :frames 2 :fps 1000)))))
  (is (not (px:get-init)))
  (is (null pixelisp.internal:*resources*)))

(test image-lab-switches-cached-previews
  (let ((keys '(:g :t :c :escape)))
    (let ((pixelisp.internal:*pump-hooks*
            (cons (lambda ()
                    (when keys
                      (px.event:post (px.event:make-event :key-down :key (pop keys)))))
                  pixelisp.internal:*pump-hooks*)))
      (px.examples:run-example "image-lab" :frames 4 :fps 1000)
      (is (null keys))))
  (is (not (px:get-init)))
  (is (null pixelisp.internal:*resources*)))

(test mask-lab-and-star-collector-bounded-loops
  (is (typep (px.examples:run-example "mask-lab" :frames 2 :fps 1000) '(integer 0 *)))
  (px.examples:run-example "star-collector" :frames 2 :audio nil)
  (is (not (px:get-init)))
  (is (null pixelisp.internal:*resources*)))

(test example-callback-failure-cleans-up-resources
  (let ((pixelisp.internal:*pump-hooks*
          (cons (lambda () (error "Example callback failed")) pixelisp.internal:*pump-hooks*)))
    (signals simple-error (px.examples:run-example "sprite-lab" :frames 1)))
  (is (not (px:get-init)))
  (is (null pixelisp.internal:*resources*)))

(test completion-event-recipe-is-bounded-and-releases-audio
  (is (= 2 (px.examples:run-example "sound-events")))
  (is (not (px:get-init)))
  (is (null pixelisp.internal:*resources*)))

(test ui-lab-toggles-and-clears-motion-filter
  (px.event:set-allowed :mouse-motion)
  (let ((keys '(:b :b :escape)))
    (let ((pixelisp.internal:*pump-hooks*
            (cons (lambda ()
                    (when keys
                      (px.event:post (px.event:make-event :key-down :key (pop keys)))))
                  pixelisp.internal:*pump-hooks*)))
      (let ((result (px.examples:run-example "ui-lab" :frames 3 :fps 1000)))
        (is (not (getf result :motion-blocked)))
        (is (null keys)))))
  (is (not (px.event:get-blocked :mouse-motion)))
  (is (not (px:get-init)))
  (is (null pixelisp.internal:*resources*)))

(test ui-lab-clears-filter-on-callback-error
  (px.event:set-allowed :mouse-motion)
  (let ((pumps 0))
    (let ((pixelisp.internal:*pump-hooks*
            (cons (lambda ()
                    (if (= 1 (incf pumps))
                        (px.event:post (px.event:make-event :key-down :key :b))
                        (error "UI callback failed")))
                  pixelisp.internal:*pump-hooks*)))
      (signals simple-error (px.examples:run-example "ui-lab" :frames 2 :fps 1000))))
  (is (not (px.event:get-blocked :mouse-motion)))
  (is (not (px:get-init)))
  (is (null pixelisp.internal:*resources*)))

(test pixel-lab-changes-tolerance-and-transposes
  (let ((keys '(:right :t :escape)))
    (let ((pixelisp.internal:*pump-hooks*
            (cons (lambda ()
                    (when keys
                      (px.event:post (px.event:make-event :key-down :key (pop keys)))))
                  pixelisp.internal:*pump-hooks*)))
      (let ((result (px.examples:run-example "pixel-lab" :frames 3 :fps 1000)))
        (is (= 1/5 (getf result :distance)))
        (is (getf result :transposed))
        (is (plusp (getf result :matches)))
        (is (null keys)))))
  (is (not (px:get-init)))
  (is (null pixelisp.internal:*resources*)))

(test pixel-lab-callback-error-releases-views-and-resources
  (let ((pixelisp.internal:*pump-hooks*
          (cons (lambda () (error "Pixel lab callback failed")) pixelisp.internal:*pump-hooks*)))
    (signals simple-error (px.examples:run-example "pixel-lab" :frames 1)))
  (is (not (px:get-init)))
  (is (null pixelisp.internal:*resources*)))
