(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test rectangle-exclusive-edges
  (let ((rect (px:make-rect 10 20 30 40)))
    (is (px.rect:collide-point rect '(10 20)))
    (is (not (px.rect:collide-point rect '(40 20))))
    (is (not (px.rect:collide-rect rect (px:make-rect 40 20 2 2))))
    (is (equal '(25 40) (px.rect:center rect)))
    (setf (px.rect:center rect) '(0 0))
    (is (equal '(-15 -20) (list (px.rect:x rect) (px.rect:y rect))))))

(test clipped-drawing-and-alpha-blits
  (px.surface:with-surface (target '(4 4))
    (px.surface:with-surface (source '(3 3) :alpha t)
      (px.surface:fill target '(0 0 100))
      (px.surface:fill source '(200 0 0 128))
      (let ((damage (px.surface:blit target source '(-1 -1))))
        (is (equal '(2 2) (px.rect:size damage))))
      (let ((color (px.surface:get-at target '(0 0))))
        (is (<= 99 (px:color-r color) 101))
        (is (<= 49 (px:color-b color) 50)))
      (is (= 100 (px:color-b (px.surface:get-at target '(3 3))))))
    (px.surface:set-clip target '(1 1 1 1))
    (px.surface:fill target '(255 255 255))
    (is (= 255 (px:color-r (px.surface:get-at target '(1 1)))))
    (is (= 0 (px:color-r (px.surface:get-at target '(3 3)))))))

(test colorkey-plus-surface-alpha
  ;; Opaque RGB surfaces retain color-key semantics when modulation is enabled.
  (px.surface:with-surface (target '(2 1))
    (px.surface:with-surface (source '(2 1))
      (px.surface:fill target '(0 0 255))
      (px.surface:set-at source '(0 0) '(255 0 255))
      (px.surface:set-at source '(1 0) '(200 0 0))
      (px.surface:set-colorkey source '(255 0 255))
      (px.surface:set-alpha source 128)
      (px.surface:blit target source '(0 0))
      (is (equal '(0 0 255 255) (px.color:to-list (px.surface:get-at target '(0 0)))))
      (is (<= 99 (px:color-r (px.surface:get-at target '(1 0))) 101)))))

(test surface-copy-preserves-hidden-pixels
  (px.surface:with-surface (source '(2 1) :alpha t)
    (px.surface:set-at source '(0 0) '(10 20 30 0))
    (px.surface:set-at source '(1 0) '(40 50 60 128))
    (px.surface:set-alpha source 65)
    (let ((copy (px.surface:copy source)))
      (unwind-protect
           (progn
             (is (equal '(10 20 30 0) (px.color:to-list (px.surface:get-at copy '(0 0)))))
             (is (equal '(40 50 60 128) (px.color:to-list (px.surface:get-at copy '(1 0)))))
             (is (= 65 (px.surface:get-alpha copy))))
        (px:dispose copy)))))

(test bounding-rect-excludes-the-color-key
  (px.surface:with-surface (surface '(5 5))
    (px.surface:fill surface '(255 0 255))
    (px.surface:set-colorkey surface '(255 0 255))
    (px.surface:set-at surface '(2 3) '(10 20 30))
    (let ((bounds (px.surface:get-bounding-rect surface)))
      (is (equal '(2 3 1 1) (list (px.rect:x bounds) (px.rect:y bounds)
                                 (px.rect:width bounds) (px.rect:height bounds)))))))

(test nested-subsurfaces-share-and-check-parents
  (let* ((parent (px.surface:make-surface '(4 4)))
         (child (px.surface:subsurface parent '(1 1 2 2)))
         (nested (px.surface:subsurface child '(1 1 1 1))))
    (unwind-protect
         (progn
           (px.surface:set-at nested '(0 0) '(77 88 99))
           (is (= 77 (px:color-r (px.surface:get-at parent '(2 2)))))
           (px:dispose parent)
           (signals px:disposed-resource (px.surface:get-at child '(0 0))))
      (px:dispose nested) (px:dispose child) (px:dispose parent))))

(test pixel-copies-live-views-and-negative-slices
  (px.surface:with-surface (surface '(3 2) :alpha t)
    (px.surface:set-at surface '(0 0) '(1 2 3 4))
    (let ((copy (px.surfarray:array3d surface)))
      (setf (aref copy 0 0 0) 99)
      (is (= 1 (px:color-r (px.surface:get-at surface '(0 0))))))
    (px.buffer:with-view (view (px.surfarray:pixels3d surface))
      (is (px.surface:locked-p surface))
      (signals px:resource-in-use (px:dispose surface))
      (setf (px.buffer:view-ref view 2 1 0) 56)
      (px.buffer:with-view (slice (px.buffer:slice view '(2 1 0) '(3 1 3) '(-1 1 1)))
        (is (= 56 (px.buffer:view-ref slice 0 0 0)))
        (setf (px.buffer:view-ref slice 2 0 1) 42)))
    (is (not (px.surface:locked-p surface)))
    (is (= 42 (px:color-g (px.surface:get-at surface '(0 1)))))))

(test closed-view-cannot-access-pixels
  (px.surface:with-surface (surface '(1 1))
    (let ((view (px.surfarray:pixels2d surface)))
      (px.buffer:close view)
      (px.buffer:close view)
      (signals px:disposed-resource (px.buffer:view-ref view 0 0)))))

(test subsurface-locks-pin-ancestor-storage
  (px.surface:with-surface (parent '(4 4) :alpha t)
    (let ((child (px.surface:subsurface parent '(1 1 2 2))))
      (unwind-protect
           (progn
             (px.buffer:with-view (pixels (px.surfarray:pixels3d child))
               (is (px.surface:locked-p parent))
               (signals px:resource-in-use (px:dispose parent))
               (setf (px.buffer:view-ref pixels 0 0 0) 123))
             (is (not (px.surface:locked-p parent)))
             (is (= 123 (px:color-r (px.surface:get-at parent '(1 1))))))
        (px:dispose child)))))

(test subsurface-preserves-imported-channel-layout
  ;; BGRA has a different channel order from Pixelisp-created RGBA surfaces.
  (cffi:with-foreign-object (memory :uint8 8)
    (loop for value in '(30 20 10 40 70 60 50 80) for index from 0
          do (setf (cffi:mem-aref memory :uint8 index) value))
    (let* ((parent (px.image:from-buffer memory '(2 1) :bgra :byte-count 8))
           (child (px.surface:subsurface parent '(1 0 1 1))))
      (unwind-protect
           (progn
             (is (equal '(50 60 70 80) (px.color:to-list (px.surface:get-at child '(0 0)))))
             (px.surface:set-at child '(0 0) '(1 2 3 4))
             (is (= 3 (cffi:mem-aref memory :uint8 4))))
        (px:dispose child) (px:dispose parent)))))

(test slices-pin-the-parent-view
  (px.surface:with-surface (surface '(2 2))
    (px.buffer:with-view (parent (px.surfarray:pixels2d surface))
      (px.buffer:with-view (child (px.buffer:slice parent '(0 0) '(1 1)))
        (signals px:resource-in-use (px.buffer:close parent))
        (is (integerp (px.buffer:view-ref child 0 0)))))))

(test event-filtering-and-timer-delivery
  (px:with-init (:video nil)
    (px.event:clear)
    (px.event:post (px.event:make-event :first :value 1))
    (px.event:post (px.event:make-event :second :value 2))
    (is (= 2 (px.event:attribute (first (px.event:get :types :second)) :value)))
    (is (eq :first (px.event:type (px.event:poll))))
    (px.time:set-timer :timer-test 1 :loops 1)
    (px.time:delay 5)
    (is (= 1 (length (px.event:get :types :timer-test))))
    (is (null (px.event:get :types :timer-test)))))

(test worker-posting-and-video-thread-guard
  (px:with-init ()
    (px.event:clear)
    (let ((thread (bt:make-thread (lambda () (px.event:post (px.event:make-event :worker :value 42))))))
      (bt:join-thread thread)
      (is (= 42 (px.event:attribute (first (px.event:get :types :worker)) :value))))
    (let ((thread (bt:make-thread (lambda () (handler-case (px.event:pump)
                                              (px:initialization-error () :guarded))))))
      (is (eq :guarded (bt:join-thread thread))))))

(test native-key-event-is-copied-before-the-next-poll
  (px:with-init (:video nil)
    (px.event:clear)
    (sdl2:with-sdl-event (native :keydown)
      (setf (plus-c:c-ref native sdl2-ffi:sdl-event :key :keysym :sym) 27
            (plus-c:c-ref native sdl2-ffi:sdl-event :key :keysym :scancode) 41
            (plus-c:c-ref native sdl2-ffi:sdl-event :key :keysym :mod) 0
            (plus-c:c-ref native sdl2-ffi:sdl-event :key :repeat) 0)
      (sdl2:push-event native))
    (let ((event (first (px.event:get :types :key-down))))
      (is (not (null event)))
      (is (eq :escape (px.event:attribute event :key)))
      (is (= 41 (px.event:attribute event :scancode))))
    (is (string= "left shift" (px.key:name :left-shift)))))

(test display-presentation-and-reinitialization
  (dotimes (iteration 2)
    (px:with-init ()
      (let ((screen (px.display:set-mode '(24 16) :flags '(:hidden))))
        (px.surface:fill screen '(10 20 30))
        (is (px.display:flip))
        (is (px.display:update '(2 3 5 7)))
        (is (px.display:update '(-100 -100 2 2)))
        (is (equal '(24 16) (px.display:get-window-size)))
        ;; Partial updates safely promote to a full scaled presentation after a
        ;; resize, without invalidating the library-owned logical framebuffer.
        (sdl2:set-window-size (px.display:get-window) 48 32)
        (is (px.display:update '(2 3 5 7)))
        (is (equal '(24 16) (px.surface:size screen)))))
    (is (not (px:get-init)))))

(test exceptional-cleanup-disposes-native-resources
  (let ((surface nil))
    (handler-case
        (px:with-init (:video nil)
          (setf surface (px.surface:make-surface '(2 2)))
          (error "A game callback failed."))
      (simple-error () nil))
    (is (not (px:get-init)))
    (signals px:disposed-resource (px.surface:get-at surface '(0 0)))
    ;; Cleanup itself remains safe to call after the exception has unwound.
    (is (px:quit))))
