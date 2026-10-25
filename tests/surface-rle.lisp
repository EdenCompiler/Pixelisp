;;;; RLE surface hints follow pygame's source-blit acceleration contract.
;;;; SDL documents RLE surfaces as requiring lock-aware pixel access; see
;;;; https://wiki.libsdl.org/SDL2/SDL_SetSurfaceRLE and SDL2/SDL_MUSTLOCK.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test surface-rle-requested-hint-and-pixel-operations
  (px.surface:with-surface (source '(2 1) :alpha t)
    (px.surface:set-at source '(0 0) '(10 20 30 255))
    (px.surface:set-at source '(1 0) '(90 80 70 128))
    (px.surface:set-colorkey source '(10 20 30) :rle t)
    (is (px.surface:rle-enabled-p source))
    (is (not (px.surface:get-locked source)))
    (let ((target (px.surface:make-surface '(2 1) :alpha t)))
      (unwind-protect
           (progn
             (px.surface:blit target source '(0 0))
             ;; This mixed alpha/key case follows pygame 2.6.1's SDL RLE path:
             ;; keying is bypassed and the output alpha is opaque. The optional
             ;; differential suite verifies this native behavior separately.
             (is (equal '(10 20 30 255)
                        (px.color:to-list (px.surface:get-at target '(0 0)))))
             (is (equal '(45 40 35 255)
                        (px.color:to-list (px.surface:get-at target '(1 0)))))
             ;; Repeated lock-mediated reads and writes remain safe after a blit.
             (px.surface:set-at source '(0 0) '(1 2 3 255))
             (is (equal '(1 2 3 255)
                        (px.color:to-list (px.surface:get-at source '(0 0)))))
             (px.surface:set-alpha source 128)
             (is (px.surface:rle-enabled-p source))
             (let ((copy (px.surface:copy source)))
               (unwind-protect
                    (is (px.surface:rle-enabled-p copy))
                 (px:dispose copy)))
             (let ((view (px.surface:get-view source)))
               (unwind-protect
                    (progn
                      (is (px.surface:get-locked source))
                      (signals px:resource-in-use (px.surface:set-alpha source 80 :rle nil))
                      (is (typep (px.surface:must-lock-p source) 'boolean)))
                 (px.buffer:close view)))
             (px.surface:blit target source '(0 0))
             (is (px.surface:rle-enabled-p source)))
        (px:dispose target)))))

(test surface-rle-supplied-p-validation-is-atomic
  (px.surface:with-surface (surface '(1 1) :alpha t)
    (px.surface:set-colorkey surface '(4 5 6) :rle t)
    (signals type-error (px.surface:set-alpha surface 100 :rle :yes))
    (is (px.surface:rle-enabled-p surface))
    (is (= 255 (px.surface:get-alpha surface)))
    (signals type-error (px.surface:set-colorkey surface '(1 2 3) :rle 1))
    (is (equal '(4 5 6)
               (subseq (px.color:to-list (px.surface:get-colorkey surface)) 0 3)))
    (px.surface:set-alpha surface 100 :rle nil)
    (is (not (px.surface:rle-enabled-p surface)))))

(test surface-rle-rejects-live-borrowers-and-views
  (px.surface:with-surface (parent '(3 2) :alpha t)
    (let ((child (px.surface:subsurface parent '(0 0 2 2))))
      (unwind-protect
           (progn
             (signals px:resource-in-use (px.surface:set-rle parent t))
             (is (not (px.surface:rle-enabled-p parent))))
        (px:dispose child)))
    (let ((view (px.surface:get-view parent)))
      (unwind-protect
           (signals px:resource-in-use (px.surface:set-rle parent t))
        (px.buffer:close view)))
    (px.surface:set-rle parent t)
    (signals px:unsupported-feature (px.surface:subsurface parent '(0 0 1 1)))
    (let ((view (px.surface:get-view parent)))
      (unwind-protect
           (signals px:resource-in-use (px.surface:set-rle parent nil))
        (px.buffer:close view)))
    (px.surface:set-rle parent nil)
    (px:with-resource (child (px.surface:subsurface parent '(0 0 1 1)))
      (is (equal '(0 0) (px.surface:get-offset child))))))

(test surface-rle-refuses-preallocated-buffer-storage
  (cffi:with-foreign-object (storage :uint8 4)
    (dotimes (index 4) (setf (cffi:mem-aref storage :uint8 index) 0))
    (px:with-resource (surface (px.image:from-buffer storage '(1 1) :bgra :byte-count 4))
      (signals px:unsupported-feature (px.surface:set-rle surface t))
      (is (not (px.surface:rle-enabled-p surface)))
      (let ((view (px.surface:get-view surface)))
        (unwind-protect
             (progn
               (signals px:resource-in-use (px.surface:set-alpha surface 90 :rle t))
               (is (not (px.surface:rle-enabled-p surface))))
          (px.buffer:close view))))))

(test surface-rle-closed-surface-checks-liveness
  (signals type-error (px.surface:must-lock-p nil))
  (signals type-error (px.surface:set-rle "surface" t))
  (let ((surface (px.surface:make-surface '(1 1))))
    (px:dispose surface)
    (signals px:disposed-resource (px.surface:rle-enabled-p surface))
    (signals px:disposed-resource (px.surface:must-lock-p surface))
    (signals px:disposed-resource (px.surface:get-locked surface))))
