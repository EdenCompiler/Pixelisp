(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test weak-sprite-membership-lifecycle
  (let* ((sprite (px.sprite:make-weak-sprite))
         (first (px.sprite:make-group sprite))
         (second (px.sprite:make-group)))
    (is (typep sprite 'px.sprite:weak-sprite))
    (is (equal 1 (length (px.sprite:groups sprite))))
    (is (px.sprite:alive-p sprite))
    (px.sprite:add sprite second)
    (is (equal 2 (length (px.sprite:groups sprite))))
    (is (= 1 (px.sprite:group-size first)))
    (is (= 1 (px.sprite:group-size second)))
    ;; Repeated adds do not duplicate either membership direction.
    (px.sprite:add first sprite)
    (is (= 2 (length (px.sprite:groups sprite))))
    (px.sprite:remove sprite first)
    (is (equal (list second) (px.sprite:groups sprite)))
    (is (px.sprite:alive-p sprite))
    (px.sprite:kill sprite)
    (is (null (px.sprite:groups sprite)))
    (is-false (px.sprite:alive-p sprite))
    (is (zerop (px.sprite:group-size first)))
    (is (zerop (px.sprite:group-size second)))
    ;; A killed sprite remains reusable.
    (px.sprite:add first sprite)
    (is (px.sprite:alive-p sprite))))

(test weak-sprite-reads-copy-groups-and-group-single-replacement
  (let* ((sprite (px.sprite:make-weak-sprite))
         (original (px.sprite:make-group sprite)))
    ;; Repeated reads must keep weak pointers in the sprite's private slot.
    (is (equal (list original) (px.sprite:groups sprite)))
    (is (px.sprite:alive-p sprite))
    (is (equal (list original) (px.sprite:groups sprite)))
    (let ((copy (px.sprite:copy-group original)))
      (is (equal 2 (length (px.sprite:groups sprite))))
      (is (px.sprite:alive-p sprite))
      (is (equal 2 (length (px.sprite:groups sprite))))
      (px.sprite:remove copy sprite)
      (is (equal (list original) (px.sprite:groups sprite)))
      (is (px.sprite:alive-p sprite)))
    (let* ((single (px.sprite:make-group-single))
           (old (px.sprite:make-weak-sprite))
           (new (px.sprite:make-weak-sprite)))
      (px.sprite:add single old)
      (is (equal (list single) (px.sprite:groups old)))
      (is (px.sprite:alive-p old))
      (px.sprite:add single new)
      (is-false (px.sprite:alive-p old))
      (is (equal (list single) (px.sprite:groups new)))
      (is (px.sprite:alive-p new))
      ;; Reads after replacement and removal still see weak pointer records.
      (is (equal (list single) (px.sprite:groups new)))
      (px.sprite:empty single)
      (is-false (px.sprite:alive-p new)))))

(test weak-dirty-sprite-keeps-dirty-rendering-behavior
  (let* ((image (px.surface:make-surface '(2 2) :alpha t))
         (target (px.surface:make-surface '(5 5) :alpha t))
         (background (px.surface:make-surface '(5 5) :alpha t))
         (sprite (px.sprite:make-weak-dirty-sprite :image image))
         (group (px.sprite:make-layered-dirty-group sprite)))
    (unwind-protect
         (progn
           (is (typep sprite 'px.sprite:weak-sprite))
           (is (typep sprite 'px.sprite:dirty-sprite))
           (is (= 1 (px.sprite:dirty sprite)))
           (is (plusp (length (px.sprite:draw group target background))))
           (is (zerop (px.sprite:dirty sprite)))
           (is (null (px.sprite:draw group target)))
           (setf (px.sprite:dirty sprite) 1)
           (is (plusp (length (px.sprite:draw group target)))))
      (px.sprite:kill sprite)
      (px:dispose background)
      (px:dispose target)
      (px:dispose image))))

#+sbcl
(progn
  (defun %ephemeral-weak-group-reference (sprite)
    "Return only a weak reference to a new group containing SPRITE."
    (trivial-garbage:make-weak-pointer (px.sprite:make-group sprite)))
  (defun %ephemeral-group-with-weak-sprite-reference ()
    "Return a strong group and a weak reference to its sole sprite."
    (let* ((sprite (px.sprite:make-weak-sprite))
           (weak-reference (trivial-garbage:make-weak-pointer sprite))
           (group (px.sprite:make-group sprite)))
      (values group weak-reference)))
  (defun %collect-until-weak-dead (weak-reference)
    (loop repeat 12
          until (null (trivial-garbage:weak-pointer-value weak-reference))
          do (sb-ext:gc :full t)
             (sleep 0.01))
    (null (trivial-garbage:weak-pointer-value weak-reference)))

  (test weak-sprite-does-not-keep-group-alive
    (let* ((sprite (px.sprite:make-weak-sprite))
           (group-reference (%ephemeral-weak-group-reference sprite)))
      (is (not (null (trivial-garbage:weak-pointer-value group-reference))))
      (is (%collect-until-weak-dead group-reference))
      ;; Reading membership prunes the dead weak group pointer.
      (is (null (px.sprite:groups sprite)))
      (is-false (px.sprite:alive-p sprite))))

  (test weak-group-still-keeps-member-sprite-alive
    (multiple-value-bind (group sprite-reference)
        (%ephemeral-group-with-weak-sprite-reference)
      ;; Run collection while the group is the only strong route to the sprite.
      (sb-ext:gc :full t)
      (let ((sprite (trivial-garbage:weak-pointer-value sprite-reference)))
        (is (not (null sprite)))
        (is (= 1 (px.sprite:group-size group)))
        (is (px.sprite:alive-p sprite))
        (px.sprite:empty group)
        (is-false (px.sprite:alive-p sprite)))))
  )
