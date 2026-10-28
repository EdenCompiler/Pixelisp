;;;; Focused tests for palette-aware averages and the smoothscale diagnostic API.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defmacro with-transform-surfaces (bindings &body body)
  (if bindings
      `(pixelisp:with-resource ,(first bindings)
         (with-transform-surfaces ,(rest bindings) ,@body))
      `(progn ,@body)))

(test average-surfaces-matches-channel-averages-across-native-depths
  (dolist (depth '(8 16 24 32))
    (with-transform-surfaces
        ((first (px.surface:make-surface '(1 1) :depth depth :alpha (= depth 32)))
         (second (px.surface:make-surface '(1 1) :depth depth :alpha (= depth 32))))
      (px.surface:set-at first '(0 0) '(20 40 60 10))
      (px.surface:set-at second '(0 0) '(100 120 140 250))
      (let* ((first-color (multiple-value-list
                           (pixelisp.internal:rgba (px.surface:get-at first '(0 0)))))
             (second-color (multiple-value-list
                            (pixelisp.internal:rgba (px.surface:get-at second '(0 0)))))
             (expected (mapcar (lambda (a b) (floor (+ a b 1) 2))
                               (subseq first-color 0 3) (subseq second-color 0 3))))
        (with-transform-surfaces ((result (px.transform:average-surfaces (list first second))))
          (let* ((actual (multiple-value-list (pixelisp.internal:rgba (px.surface:get-at result '(0 0)))))
                 (expected-pixel (px.surface:map-rgb result expected)))
            (is (= expected-pixel (px.surface:get-at-mapped result '(0 0))))
            ;; Pygame's algorithm averages RGB only; mapped output is opaque.
            (is (= 255 (fourth actual)))
            (is (= depth (px.surface:get-bitsize result)))))))))

(test average-surfaces-index-and-palette-color-modes
  (with-transform-surfaces
      ((first (px.surface:make-surface '(1 1) :depth 8))
       (second (px.surface:make-surface '(1 1) :depth 8))
       (index-result (px.surface:make-surface '(1 1) :depth 8))
       (color-result (px.surface:make-surface '(1 1) :depth 8)))
    (dolist (surface (list first second index-result color-result))
      (px.surface:set-palette-at surface 1 '(255 0 0))
      (px.surface:set-palette-at surface 3 '(0 0 255))
      (px.surface:set-palette-at surface 7 '(128 0 128)))
    (px.surface:set-at-mapped first '(0 0) 1)
    (px.surface:set-at-mapped second '(0 0) 3)
    (px.transform:average-surfaces (list first second) index-result :palette-colors nil)
    (px.transform:average-surfaces (list first second) color-result)
    (is (= 2 (px.surface:get-at-mapped index-result '(0 0))))
    ;; The first surface's independent palette is used to map the mean color.
    (is (= 7 (px.surface:get-at-mapped color-result '(0 0))))))

(test average-surfaces-destination-validation-clipping-and-alias-snapshot
  (with-transform-surfaces
      ((first (px.surface:make-surface '(2 1) :depth 32))
       (second (px.surface:make-surface '(2 1) :depth 32))
       (wrong-size (px.surface:make-surface '(1 1) :depth 32))
       (wrong-format (px.surface:make-surface '(2 1) :depth 16)))
    (px.surface:set-at first '(0 0) '(10 20 30))
    (px.surface:set-at first '(1 0) '(100 110 120))
    (px.surface:set-at second '(0 0) '(30 40 50))
    (px.surface:set-at second '(1 0) '(120 130 140))
    (px.surface:set-clip first '(0 0 0 0))
    (px.transform:average-surfaces (list first second) first)
    (is (equal '(20 30 40 255)
               (multiple-value-list (pixelisp.internal:rgba (px.surface:get-at first '(0 0))))))
    (is (equal '(110 120 130 255)
               (multiple-value-list (pixelisp.internal:rgba (px.surface:get-at first '(1 0))))))
    (with-transform-surfaces ((mixed (px.transform:average-surfaces (list first wrong-format))))
      (is (= 32 (px.surface:get-bitsize mixed))))
    (signals error (px.transform:average-surfaces (list first second) wrong-size))
    (signals error (px.transform:average-surfaces (list first second) wrong-format))
    (signals error (px.transform:average-surfaces (list first wrong-size)))
    (signals type-error (px.transform:average-surfaces nil))
    (signals type-error (px.transform:average-surfaces (list first) nil :palette-colors 1))))

(test smoothscale-backend-is-generic-and-rejects-unavailable-simd
  (is (eq :generic (px.transform:get-smoothscale-backend)))
  (is (eq :generic (px.transform:set-smoothscale-backend :generic)))
  (is (eq :generic (px.transform:set-smoothscale-backend "gEnErIc")))
  (signals pixelisp:unsupported-feature (px.transform:set-smoothscale-backend "MMX"))
  (signals pixelisp:unsupported-feature (px.transform:set-smoothscale-backend :sse))
  (signals error (px.transform:set-smoothscale-backend "unknown")))
