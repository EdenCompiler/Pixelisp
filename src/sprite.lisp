;;;; Native-independent sprite and group bookkeeping.
;;;;
;;;; A Sprite is intentionally a small CLOS object rather than a game engine.
;;;; Applications subclass it and specialize UPDATE. Groups maintain bidirectional
;;;; membership, preserve insertion order, and take snapshots before callbacks so
;;;; that adding/removing sprites during UPDATE is safe. Drawing is resolved only
;;;; at runtime, allowing the core system to load without SDL or a display.

(defpackage #:pixelisp.sprite
  (:nicknames #:px.sprite)
  (:use #:cl)
  (:shadow #:remove #:clear)
  (:export #:sprite #:dirty-sprite #:weak-sprite #:weak-dirty-sprite
           #:group #:group-single #:ordered-group #:layered-group #:layered-dirty-group
           #:make-sprite #:make-dirty-sprite #:make-weak-sprite #:make-weak-dirty-sprite
           #:make-group #:make-group-single #:single-sprite #:make-ordered-group
           #:render-updates-group #:make-render-updates-group #:source-rect
           #:make-layered-group #:make-layered-dirty-group #:image #:rect #:mask
           #:layer #:visible-p #:dirty #:blend-flags #:radius #:groups #:alive-p #:kill
           #:add #:remove #:empty #:sprites #:has-p #:update #:draw #:clear
           #:copy-group #:group-size #:change-layer #:get-layer-of-sprite
           #:get-sprites-from-layer #:remove-sprites-of-layer #:layers
           #:get-top-layer #:get-bottom-layer #:get-top-sprite #:get-bottom-sprite #:move-to-front #:move-to-back
           #:switch-layer #:get-sprites-at #:collide-rect #:collide-rect-ratio
           #:get-sprite #:get-clip #:set-clip #:repaint-rect
           #:collide-circle #:collide-circle-ratio #:collide-mask
           #:sprite-collide #:sprite-collide-any #:group-collide
           #:spritecollide #:spritecollideany #:groupcollide))

(in-package #:pixelisp.sprite)

(defclass sprite ()
  ((image :initarg :image :initform nil :accessor image)
   (rect :initarg :rect :initform (pixelisp:make-rect 0 0 0 0) :accessor rect)
   (mask :initarg :mask :initform nil :accessor mask)
   (radius :initarg :radius :initform nil :accessor radius)
   (groups :initform nil :accessor %groups)
   (layer :initarg :layer :initform 0 :accessor layer)
   (visible :initarg :visible :initform t :accessor visible-p)
   (dirty :initarg :dirty :initform 1 :accessor dirty)
   (blend-flags :initarg :blend-flags :initform nil :accessor blend-flags)
   (%source-rect :initarg :source-rect :initform nil :accessor %source-rect)))
(defclass dirty-sprite (sprite) ())
(defclass weak-sprite (sprite) ())
(defclass weak-dirty-sprite (weak-sprite dirty-sprite) ())
(defclass group ()
  ((sprites :initform nil :accessor %sprites)
   (drawn :initform (make-hash-table :test #'eq) :accessor %drawn)
   (pending :initform nil :accessor %pending)
   (background :initform nil :accessor %background)
   (layers :initform (make-hash-table :test #'eq) :reader %layers)))
(defclass ordered-group (group) ())
(defclass group-single (group) ())
(defclass render-updates-group (group) ())
(defclass layered-group (ordered-group) ())
(defclass layered-dirty-group (layered-group)
  ((last-rects :initform (make-hash-table :test #'eq) :accessor %last-rects)
   (clip :initform nil :accessor %group-clip)
   (refresh-clip :initform nil :accessor %refresh-clip)
   (repaints :initform nil :accessor %repaints)
   (force-redraw :initform nil :accessor %force-redraw)))

(defun %surface-call (name &rest arguments)
  (let ((symbol (find-symbol name :pixelisp.surface)))
    (unless (and symbol (fboundp symbol)) (error "Load pixelisp's surface system before drawing sprites."))
    (apply (symbol-function symbol) arguments)))
(defun %copy-rect (rect)
  (when rect
    (pixelisp:make-rect (pixelisp:rect-x rect) (pixelisp:rect-y rect)
                        (pixelisp:rect-width rect) (pixelisp:rect-height rect))))
(defun %rect-equal-p (first second)
  (or (and (null first) (null second))
      (and first second (= (pixelisp:rect-x first) (pixelisp:rect-x second))
           (= (pixelisp:rect-y first) (pixelisp:rect-y second))
           (= (pixelisp:rect-width first) (pixelisp:rect-width second))
           (= (pixelisp:rect-height first) (pixelisp:rect-height second)))))
(defun source-rect (sprite)
  "Return a defensive copy of SPRITE's optional image crop rectangle."
  (%copy-rect (%source-rect sprite)))
(defun (setf source-rect) (value sprite)
  "Set SPRITE's image crop rectangle, copying and validating VALUE."
  (let ((copy (and value (%copy-rect (pixelisp.internal:as-rect value)))))
    (unless (%rect-equal-p copy (%source-rect sprite))
      (setf (%source-rect sprite) copy
            (dirty sprite) (max 1 (dirty sprite))))
    (source-rect sprite)))
(defun %sprite-destination (sprite)
  "Return the sprite's top-left destination; source crops keep this origin."
  (let ((position (rect sprite)))
    (list (pixelisp:rect-x position) (pixelisp:rect-y position))))
(defun %make-sprite-instance (class &key image rect source-rect (layer 0) (visible t) (dirty 1) mask radius blend-flags)
  "Construct a Sprite. When IMAGE is provided, RECT defaults to its image rectangle."
  (let ((sprite (make-instance class :image image :rect (or rect (if image (%surface-call "GET-RECT" image)
                                                                    (pixelisp:make-rect 0 0 0 0)))
                               :layer layer :visible visible :dirty dirty :mask mask :radius radius
                               :blend-flags blend-flags)))
    (setf (source-rect sprite) source-rect)
    sprite))
(defun make-sprite (&key image rect source-rect (layer 0) (visible t) (dirty 1) mask radius blend-flags)
  "Construct a Sprite. When IMAGE is provided, RECT defaults to its image rectangle."
  (%make-sprite-instance 'sprite :image image :rect rect :source-rect source-rect
                         :layer layer :visible visible :dirty dirty :mask mask
                         :radius radius :blend-flags blend-flags))
(defmethod (setf visible-p) :after (value (sprite sprite))
  (declare (ignore value))
  (setf (dirty sprite) (max 1 (dirty sprite))))
(defmethod (setf image) :after (value (sprite sprite))
  (declare (ignore value))
  (setf (dirty sprite) (max 1 (dirty sprite))))
(defmethod (setf blend-flags) :after (value (sprite sprite))
  (declare (ignore value))
  (setf (dirty sprite) (max 1 (dirty sprite))))
(defun make-dirty-sprite (&rest arguments)
  "Construct a dirty-sprite using the same keyword arguments as MAKE-SPRITE."
  (apply #'%make-sprite-instance 'dirty-sprite arguments))
(defun make-weak-sprite (&rest arguments)
  "Construct a Sprite whose references to member groups are weak."
  (apply #'%make-sprite-instance 'weak-sprite arguments))
(defun make-weak-dirty-sprite (&rest arguments)
  "Construct a weak Sprite with dirty-rendering attributes."
  (apply #'%make-sprite-instance 'weak-dirty-sprite arguments))
(defun %weak-sprite-p (sprite) (typep sprite 'weak-sprite))
(defun %live-groups (sprite)
  "Return live member groups, pruning dead weak references in place."
  (if (%weak-sprite-p sprite)
      (let ((references nil) (groups nil))
        (dolist (reference (%groups sprite))
          (let ((group (trivial-garbage:weak-pointer-value reference)))
            (when group
              ;; Keep weak-pointer objects in the slot. Returning GROUPs is
              ;; only for this read; storing them would make the next call
              ;; mistake strong group objects for weak pointers.
              (push reference references)
              (push group groups))))
        (setf (%groups sprite) (nreverse references))
        (nreverse groups))
      (%groups sprite)))
(defun %record-group (sprite group)
  (if (%weak-sprite-p sprite)
      (unless (member group (%live-groups sprite) :test #'eq)
        (push (trivial-garbage:make-weak-pointer group) (%groups sprite)))
      (pushnew group (%groups sprite) :test #'eq)))
(defun %forget-group (sprite group)
  (if (%weak-sprite-p sprite)
      (setf (%groups sprite)
            (delete-if (lambda (reference)
                         (let ((member-group (trivial-garbage:weak-pointer-value reference)))
                           (or (null member-group) (eq member-group group))))
                       (%groups sprite)))
      (setf (%groups sprite) (delete group (%groups sprite) :test #'eq))))
(defun groups (sprite) (copy-list (%live-groups sprite)))
(defun alive-p (sprite) "Return true when SPRITE belongs to at least one group." (not (null (%live-groups sprite))))
(defgeneric add (group &rest sprites)
  (:documentation "Add sprites to a group, or add a sprite to the supplied groups."))
(defgeneric remove (group &rest sprites)
  (:documentation "Remove group memberships without disposing images or sprites."))
(defgeneric update (object &rest arguments)
  (:documentation "Update a sprite, or forward ARGUMENTS to every current group member."))
(defgeneric draw (group target &optional background)
  (:documentation "Blit visible sprite images onto TARGET and return affected rectangles."))
(defgeneric clear (group target background)
  (:documentation "Restore previously drawn areas using a background Surface or callback."))

(defun %flatten (objects)
  (mapcan (lambda (object)
            (typecase object
              (null nil) (sprite (list object)) (group (sprites object))
              (list (%flatten object))
              (t (error 'type-error :datum object :expected-type '(or sprite group list)))))
          objects))
(defmethod add ((group group) &rest objects)
  (dolist (sprite (%flatten objects))
    (unless (member sprite (%sprites group) :test #'eq)
      (setf (%sprites group) (append (%sprites group) (list sprite)))
      (%record-group sprite group)
      (setf (gethash sprite (%layers group)) (layer sprite)
            (dirty sprite) (max 1 (dirty sprite))))) group)
(defmethod add ((group group-single) &rest objects)
  "Keep only the last sprite in the flattened arguments, as pygame GroupSingle does."
  (let* ((members (%flatten objects))
         (last-sprite (car (last members))))
    (when last-sprite
      (dolist (old (copy-list (%sprites group)))
        (unless (eq old last-sprite) (remove group old)))
      (call-next-method group last-sprite))
    group))
(defmethod remove ((group group) &rest objects)
  (dolist (sprite (%flatten objects))
    (when (member sprite (%sprites group) :test #'eq)
      (let ((old (gethash sprite (%drawn group))))
        (when old (push old (%pending group))))
      (setf (%sprites group) (delete sprite (%sprites group) :test #'eq))
      (%forget-group sprite group)
      (remhash sprite (%drawn group)) (remhash sprite (%layers group)))) group)
(defmethod add ((sprite sprite) &rest groups)
  (dolist (group groups) (add group sprite)) sprite)
(defmethod remove ((sprite sprite) &rest groups)
  (dolist (group groups) (remove group sprite)) sprite)
(defun kill (sprite)
  "Remove SPRITE from every group without destroying its image."
  (dolist (group (groups sprite)) (remove group sprite)) sprite)
(defun empty (group) "Remove every member from GROUP without disposing any sprite resources."
  (apply #'remove group (copy-list (%sprites group))) group)
(defun sprites (group)
  "Return a fresh list of members in draw order."
  (let ((members (copy-list (%sprites group))))
    (if (typep group 'layered-group)
        (stable-sort members #'< :key (lambda (sprite) (gethash sprite (%layers group) 0)))
        members)))
(defun get-sprite (group index)
  "Return the sprite at INDEX in draw order; negative indices count from the end."
  (unless (integerp index) (error 'type-error :datum index :expected-type 'integer))
  (let* ((ordered (sprites group)) (length (cl:length ordered))
         (adjusted (if (minusp index) (+ length index) index)))
    (unless (<= 0 adjusted (1- length))
      (error "Sprite index ~D is outside the group of ~D sprites." index length))
    (nth adjusted ordered)))
(defun has-p (group &rest objects)
  "Return true when GROUP contains every sprite named in OBJECTS. Groups and lists may be nested."
  (every (lambda (sprite) (not (null (member sprite (%sprites group) :test #'eq)))) (%flatten objects)))
(defun group-size (group) "Return the number of sprites in GROUP." (cl:length (%sprites group)))
(defun %construct-group (class objects)
  (let ((group (make-instance class))) (apply #'add group objects) group))
(defun make-group (&rest sprites) "Create a group containing SPRITES in insertion order." (%construct-group 'group sprites))
(defun make-group-single (&rest sprites) "Create a group that keeps only its most recently added sprite." (%construct-group 'group-single sprites))
(defun make-render-updates-group (&rest sprites)
  "Create an insertion-ordered group whose draw result describes changed pixels."
  (%construct-group 'render-updates-group sprites))
(defun single-sprite (group)
  "Return the group's only sprite, or NIL when it is empty."
  (first (%sprites group)))
(defun (setf single-sprite) (sprite group)
  "Replace the group's member, or clear it with NIL."
  (if sprite (add group sprite) (empty group))
  sprite)
(defun make-ordered-group (&rest sprites) "Create an insertion-ordered group." (%construct-group 'ordered-group sprites))
(defun make-layered-group (&rest sprites) "Create a group that draws sprites in ascending layer order." (%construct-group 'layered-group sprites))
(defun make-layered-dirty-group (&rest sprites) "Create a layered group that restores and redraws changed sprite areas." (%construct-group 'layered-dirty-group sprites))
(defun copy-group (group)
  "Create another group of the same class, sharing sprites but keeping independent membership."
  (let ((copy (%construct-group (class-name (class-of group)) (sprites group))))
    (dolist (sprite (sprites group))
      (setf (gethash sprite (%layers copy)) (gethash sprite (%layers group)))) copy))
(defmethod update ((sprite sprite) &rest arguments) (declare (ignore arguments)) sprite)
(defmethod update ((group group) &rest arguments)
  (dolist (sprite (sprites group)) (apply #'update sprite arguments)) group)

(defun %restore (target background rect)
  (cond ((null background) nil)
        ((functionp background) (funcall background target rect))
        (t (%surface-call "BLIT" target background
                          (list (pixelisp:rect-x rect) (pixelisp:rect-y rect)) :area rect))))
(defmethod clear ((group group) target background)
  (setf (%background group) background)
  (maphash (lambda (sprite rect) (declare (ignore sprite)) (%restore target background rect)) (%drawn group))
  (dolist (rect (%pending group)) (%restore target background rect))
  (setf (%pending group) nil) group)
(defmethod clear ((group render-updates-group) target background)
  "Restore drawn and lost areas while retaining lost damage for the next draw."
  (setf (%background group) background)
  (maphash (lambda (sprite rectangle)
             (declare (ignore sprite))
             (%restore target background rectangle))
           (%drawn group))
  (dolist (rectangle (%pending group))
    (%restore target background rectangle))
  group)
(defun get-clip (group)
  "Return a copy of GROUP's draw clip, or NIL when it has no additional clip."
  (%copy-rect (%group-clip group)))
(defun set-clip (group &optional rectangle)
  "Set GROUP's draw clip, copying RECTANGLE; NIL removes the additional clip."
  (let ((copy (and rectangle (%copy-rect (pixelisp.internal:as-rect rectangle)))))
    (unless (%rect-equal-p copy (%group-clip group))
      (setf (%group-clip group) copy (%force-redraw group) t
            (%refresh-clip group) t)))
  (get-clip group))
(defun repaint-rect (group rectangle)
  "Queue RECTANGLE for repainting and return GROUP. RECTANGLE is copied."
  (push (%copy-rect (pixelisp.internal:as-rect rectangle)) (%repaints group))
  (setf (%force-redraw group) t)
  group)
(defun %call-with-group-clip (group target thunk)
  "Run THUNK with GROUP's clip intersected with TARGET's current clip."
  (let* ((saved (%surface-call "GET-CLIP" target))
         (group-clip (%group-clip group)))
    (unwind-protect
         (progn
           (when group-clip
             (%surface-call "SET-CLIP" target (px.rect:clip saved group-clip)))
           (funcall thunk))
      (%surface-call "SET-CLIP" target saved))))
(defun %clipped-damage (rectangle clip)
  (let ((damage (px.rect:clip rectangle clip)))
    (when (and (plusp (pixelisp:rect-width damage))
               (plusp (pixelisp:rect-height damage)))
      damage)))
(defmethod clear ((group layered-dirty-group) target background)
  (%call-with-group-clip
   group target
   (lambda ()
     (setf (%force-redraw group) t)
     (setf (%background group) background)
     (maphash (lambda (sprite old) (declare (ignore sprite)) (%restore target background old)) (%drawn group))
     (dolist (old (%pending group)) (%restore target background old))
     (setf (%pending group) nil)
     group)))
(defmethod draw ((group group) target &optional background)
  (when background (clear group target background))
  (let ((affected nil))
    (dolist (sprite (sprites group))
      (when (and (image sprite) (visible-p sprite))
        (let ((rect (%surface-call "BLIT" target (image sprite)
                                  (%sprite-destination sprite)
                                  :area (source-rect sprite)
                                  :special-flags (blend-flags sprite))))
          (setf (gethash sprite (%drawn group)) (%copy-rect rect))
          (push rect affected))))
    (nreverse affected)))

(defun %rectangles-overlap-p (first second)
  (and (< (pixelisp:rect-x first) (+ (pixelisp:rect-x second) (pixelisp:rect-width second)))
       (< (pixelisp:rect-x second) (+ (pixelisp:rect-x first) (pixelisp:rect-width first)))
       (< (pixelisp:rect-y first) (+ (pixelisp:rect-y second) (pixelisp:rect-height second)))
       (< (pixelisp:rect-y second) (+ (pixelisp:rect-y first) (pixelisp:rect-height first)))))
(defun %render-update-damage (old new)
  "Return the changed rectangles, merging overlapping previous and current bounds."
  (cond ((null old) (list new))
        ((null new) (list (%copy-rect old)))
        ((%rectangles-overlap-p old new) (list (px.rect:union old new)))
        (t (list new (%copy-rect old)))))
(defmethod draw ((group render-updates-group) target &optional background)
  "Draw in insertion order and report old/new changed regions plus removed bounds."
  (let* ((pending (mapcar #'%copy-rect (%pending group)))
         (members (copy-list (%sprites group)))
         (next-drawn (make-hash-table :test #'eq))
         (damage pending)
         (partial-draws nil)
         (completed nil))
    (maphash (lambda (sprite rectangle)
               (setf (gethash sprite next-drawn) (%copy-rect rectangle)))
             (%drawn group))
    (unwind-protect
         (progn
           (when background (clear group target background))
           (dolist (sprite members)
             (let ((old (gethash sprite (%drawn group))))
               (if (and (image sprite) (visible-p sprite))
                   (let ((new (%surface-call "BLIT" target (image sprite)
                                             (%sprite-destination sprite)
                                             :area (source-rect sprite)
                                             :special-flags (blend-flags sprite))))
                     (push (%copy-rect new) partial-draws)
                     (setf (gethash sprite next-drawn) (%copy-rect new))
                     (setf damage (nconc damage (%render-update-damage old new))))
                   (progn
                     ;; Hidden sprites keep no painted bounds; report the old
                     ;; area so the caller can restore it from its background.
                     (when old (setf damage (nconc damage (list (%copy-rect old)))))
                     (remhash sprite next-drawn)))))
           (setf (%drawn group) next-drawn
                 (%pending group) nil
                 completed t)
           damage)
      (unless completed
        ;; A background clear may have run before drawing failed. Retain the
        ;; original lost bounds for retry. Also retain
        ;; every successful partial blit: it may have left pixels on-screen
        ;; even though the rest of this frame did not complete.
        (dolist (rectangle pending)
          (pushnew (%copy-rect rectangle) (%pending group) :test #'%rect-equal-p))
        (dolist (rectangle partial-draws)
          (pushnew (%copy-rect rectangle) (%pending group) :test #'%rect-equal-p))))))
(defun %dirty-group-changed-p (group members)
  (or (%force-redraw group) (%repaints group) (%pending group)
      (some (lambda (sprite)
              (or (not (zerop (dirty sprite)))
                  (not (%rect-equal-p (rect sprite)
                                      (gethash sprite (%last-rects group))))))
            members)))

(defun %draw-dirty-group (group target background)
  "Redraw a changed group; the caller has already installed its effective clip."
  (let* ((background (or background (%background group)))
         (members (sprites group))
         (clip (%surface-call "GET-CLIP" target)))
    (unless (%dirty-group-changed-p group members)
      (return-from %draw-dirty-group nil))
    ;; Full sprite positions detect movement; actual blit rectangles describe
    ;; pixels to restore. Keeping them separate also lets clipped and invisible
    ;; sprites become clean instead of forcing a redraw on every frame.
    (let ((next-drawn (make-hash-table :test #'eq))
          (next-rects (make-hash-table :test #'eq))
          (affected (append (mapcar #'%copy-rect (%repaints group))
                            (mapcar #'%copy-rect (%pending group))))
          (completed nil))
      (unwind-protect
           (progn
             ;; Widening a clip can expose stale pixels from an older frame.
             ;; Refresh the newly permitted area; never touch pixels outside
             ;; the current effective clip while it remains narrowed.
             (when (and (%refresh-clip group) background)
               (push (%copy-rect clip) affected)
               (%restore target background clip))
             ;; Restore first, then redraw the complete group in layer order.
             ;; This preserves overlaps while reporting broader damage than
             ;; pygame's optimized dirty-rectangle renderer.
             (maphash (lambda (sprite old)
                        (declare (ignore sprite))
                        (push (%copy-rect old) affected)
                        (%restore target background old))
                      (%drawn group))
             (dolist (old (%pending group)) (%restore target background old))
             (dolist (area (%repaints group)) (%restore target background area))
             (dolist (sprite members)
               (when (and (image sprite) (visible-p sprite))
                 (let ((drawn (%surface-call "BLIT" target (image sprite)
                                (%sprite-destination sprite)
                                :area (source-rect sprite)
                                :special-flags (blend-flags sprite))))
                   (push drawn affected)
                   (setf (gethash sprite next-drawn) (%copy-rect drawn))))
               (setf (gethash sprite next-rects) (%copy-rect (rect sprite))))
             ;; Commit bookkeeping only after every callback/blit succeeds.
             (setf (%drawn group) next-drawn (%last-rects group) next-rects
                   (%pending group) nil (%repaints group) nil
                   (%force-redraw group) nil (%refresh-clip group) nil
                   (%background group) background)
             (dolist (sprite members)
               (when (= 1 (dirty sprite)) (setf (dirty sprite) 0)))
             (setf completed t)
             (cl:remove nil
                        (mapcar (lambda (area) (%clipped-damage area clip))
                                (nreverse affected))))
        (unless completed
          ;; A failed callback or blit can leave a partly drawn frame. Repaint
          ;; the effective area on retry, including any new sprite positions.
          (pushnew (%copy-rect clip) (%pending group) :test #'%rect-equal-p)
          (setf (%force-redraw group) t))))))

(defmethod draw ((group layered-dirty-group) target &optional background)
  (%call-with-group-clip group target
                        (lambda () (%draw-dirty-group group target background))))

(defmethod remove :before ((group layered-dirty-group) &rest objects)
  (dolist (sprite (%flatten objects))
    (remhash sprite (%last-rects group))))

(defun get-layer-of-sprite (group sprite)
  (multiple-value-bind (layer present) (gethash sprite (%layers group))
    (unless present (error "Sprite is not in this group.")) layer))
(defun change-layer (group sprite layer)
  "Change a sprite's layer in this group only, preserving other groups' layer choices."
  (unless (has-p group sprite) (error "Sprite is not in this group."))
  (check-type layer real)
  (setf (gethash sprite (%layers group)) layer (dirty sprite) (max 1 (dirty sprite))) group)
(defun layers (group) (sort (remove-duplicates (mapcar (lambda (sprite) (get-layer-of-sprite group sprite))
                                                    (%sprites group))) #'<))
(defun get-top-layer (group) (or (car (last (layers group))) 0))
(defun get-bottom-layer (group) (or (first (layers group)) 0))
(defun get-top-sprite (group) "Return the last sprite in the group's draw order, or NIL." (car (last (sprites group))))
(defun get-bottom-sprite (group) "Return the first sprite in the group's draw order, or NIL." (first (sprites group)))
(defun get-sprites-from-layer (group layer)
  (remove-if-not (lambda (sprite) (= layer (get-layer-of-sprite group sprite))) (sprites group)))
(defun remove-sprites-of-layer (group layer)
  (let ((removed (get-sprites-from-layer group layer))) (apply #'remove group removed) removed))
(defun move-to-front (group sprite) (change-layer group sprite (1+ (get-top-layer group))))
(defun move-to-back (group sprite) (change-layer group sprite (1- (get-bottom-layer group))))
(defun switch-layer (group first second)
  (dolist (sprite (%sprites group))
    (let ((old (get-layer-of-sprite group sprite)))
      (cond ((= old first) (change-layer group sprite second))
            ((= old second) (change-layer group sprite first))))) group)
(defun get-sprites-at (group position)
  (multiple-value-bind (x y) (pixelisp.internal:pair position)
    (remove-if-not (lambda (sprite)
                     (let ((rect (rect sprite)))
                       (and (<= (pixelisp:rect-x rect) x)
                            (< x (+ (pixelisp:rect-x rect) (pixelisp:rect-width rect)))
                            (<= (pixelisp:rect-y rect) y)
                            (< y (+ (pixelisp:rect-y rect) (pixelisp:rect-height rect))))))
                   (sprites group))))

(defun %rect-collision (first second)
  (and (plusp (pixelisp:rect-width first)) (plusp (pixelisp:rect-height first))
       (plusp (pixelisp:rect-width second)) (plusp (pixelisp:rect-height second))
       (< (pixelisp:rect-x first) (+ (pixelisp:rect-x second) (pixelisp:rect-width second)))
       (< (pixelisp:rect-x second) (+ (pixelisp:rect-x first) (pixelisp:rect-width first)))
       (< (pixelisp:rect-y first) (+ (pixelisp:rect-y second) (pixelisp:rect-height second)))
       (< (pixelisp:rect-y second) (+ (pixelisp:rect-y first) (pixelisp:rect-height first)))))
(defun collide-rect (first second) "Test whether two sprite rectangles overlap with positive area." (%rect-collision (rect first) (rect second)))
(defun collide-rect-ratio (ratio)
  (unless (plusp ratio) (error "Collision ratio must be positive."))
  (lambda (first second)
    (flet ((scaled (sprite)
             (let* ((rect (rect sprite)) (w (* ratio (pixelisp:rect-width rect)))
                    (h (* ratio (pixelisp:rect-height rect))))
               (pixelisp:make-rect (round (+ (pixelisp:rect-x rect) (/ (- (pixelisp:rect-width rect) w) 2)))
                                  (round (+ (pixelisp:rect-y rect) (/ (- (pixelisp:rect-height rect) h) 2)))
                                  (round w) (round h)))))
      (%rect-collision (scaled first) (scaled second)))))
(defun %circle (sprite)
  (let ((rect (rect sprite)))
    (values (+ (pixelisp:rect-x rect) (/ (pixelisp:rect-width rect) 2))
            (+ (pixelisp:rect-y rect) (/ (pixelisp:rect-height rect) 2))
            (or (radius sprite)
                (/ (sqrt (+ (expt (pixelisp:rect-width rect) 2) (expt (pixelisp:rect-height rect) 2))) 2)))))
(defun collide-circle (first second)
  "Test circle collision using explicit sprite radii or half-diagonal defaults."
  (multiple-value-bind (ax ay ar) (%circle first)
    (multiple-value-bind (bx by br) (%circle second)
      (<= (+ (expt (- ax bx) 2) (expt (- ay by) 2)) (expt (+ ar br) 2)))))
(defun collide-circle-ratio (ratio)
  (unless (plusp ratio) (error "Collision ratio must be positive."))
  (lambda (first second)
    (multiple-value-bind (ax ay ar) (%circle first)
      (multiple-value-bind (bx by br) (%circle second)
        (<= (+ (expt (- ax bx) 2) (expt (- ay by) 2)) (expt (* ratio (+ ar br)) 2))))))
(defun collide-mask (first second)
  (let ((package (find-package :pixelisp.mask)))
    (unless package (error "Load pixelisp's graphics system before mask collision."))
    (flet ((mask-for (sprite)
             (or (mask sprite)
                 (when (image sprite)
                   (funcall (find-symbol "FROM-SURFACE" package) (image sprite))))))
      (let ((a (mask-for first)) (b (mask-for second)))
        (and a b
             (funcall (find-symbol "OVERLAP" package) a b
                      (list (- (pixelisp:rect-x (rect second)) (pixelisp:rect-x (rect first)))
                            (- (pixelisp:rect-y (rect second)) (pixelisp:rect-y (rect first))))))))))
(defun sprite-collide (sprite group &key kill (collide #'collide-rect))
  "Return colliding members of GROUP, optionally killing the matching sprites."
  (let ((hits (remove-if-not (lambda (other) (funcall collide sprite other)) (sprites group))))
    (when kill (dolist (other hits) (kill other))) hits))
(defun sprite-collide-any (sprite group &optional (collide #'collide-rect))
  (find-if (lambda (other) (funcall collide sprite other)) (sprites group)))
(defun group-collide (first second &key kill-first kill-second (collide #'collide-rect))
  "Return an EQ hash table mapping each colliding sprite in FIRST to its hits in SECOND."
  (let ((result (make-hash-table :test #'eq)) (dead nil) (targets (sprites second)))
    (dolist (sprite (sprites first))
      (let ((hits (remove-if-not (lambda (other) (funcall collide sprite other)) targets)))
        (when hits (setf (gethash sprite result) hits)
              (when kill-first (pushnew sprite dead :test #'eq))
              (when kill-second (dolist (other hits) (pushnew other dead :test #'eq))))))
    (dolist (sprite dead) (kill sprite)) result))
(defun spritecollide (sprite group kill &optional (collide #'collide-rect))
  (sprite-collide sprite group :kill kill :collide collide))
(defun spritecollideany (sprite group &optional (collide #'collide-rect))
  (sprite-collide-any sprite group collide))
(defun groupcollide (first second kill-first kill-second &optional (collide #'collide-rect))
  (group-collide first second :kill-first kill-first :kill-second kill-second :collide collide))

(setf (fdefinition 'pixelisp:make-sprite) #'make-sprite
      (fdefinition 'pixelisp:make-group) #'make-group)
