;;;; Literal color fixtures cover public spelling, packing, and mutation rules.
(in-package #:pixelisp.tests)
(in-suite pixelisp)

(test named-and-hexadecimal-colors
  (dolist (fixture '(("red" (255 0 0 255))
                     ("green" (0 255 0 255))
                     (" Dark Slate Gray " (47 79 79 255))
                     ("grey42" (107 107 107 255))
                     ("#102030" (16 32 48 255))
                     ("#10203040" (16 32 48 64))
                     ("0xAaBbCcDD" (170 187 204 221))))
    (is (equal (second fixture) (px.color:to-list (px:make-color (first fixture))))))
  (is (equal '(1 2 3 4) (px.color:to-list (px:make-color #x01020304))))
  (is (equal '(1 2 3 255) (px.color:to-list (px:make-color #(1 2 3)))))
  (is (= #x01020304 (px.color:to-integer (px:make-color 1 2 3 4))))
  (dolist (invalid '("#abc" "#001122zz" "#00112233extra" "not-a-color" "0X112233" -1 4294967296))
    (signals error (px:make-color invalid))))

(test named-color-tables-and-copies-are-independent
  (let* ((table (px.colordict:the-colors))
         (names (px.colordict:color-names))
         (original (px:make-color 1 2 3 4))
         (copy (px:make-color original)))
    (is (= 665 (hash-table-count table)))
    (is (equal '(240 248 255 255) (gethash "aliceblue" table)))
    (setf (first (gethash "aliceblue" table)) 0
          (char (first names) 0) #\X
          (px:color-r copy) 99)
    (is (equal '(240 248 255 255) (px.colordict:lookup "Alice Blue")))
    (is (string= "aliceblue" (first (px.colordict:color-names))))
    (is (= 1 (px:color-r original)))
    (is (null (px.colordict:lookup "no-such-color")))))

(test color-update-and-per-color-effects
  (let ((color (px:make-color 10 20 30 40)))
    (is (eq color (px.color:update-color color 1 2 3)))
    (is (equal '(1 2 3 40) (px.color:to-list color)))
    (px.color:update-color color '(4 5 6))
    (is (equal '(4 5 6 255) (px.color:to-list color)))
    (px.color:update-color color "#10203040")
    (signals type-error (px.color:update-color color 1 2 999))
    (is (equal '(16 32 48 64) (px.color:to-list color))))
  (is (equal '(103 103 103 128)
             (px.color:to-list (px.color:grayscale '(200 50 128 128)))))
  (is (equal '(255 255 255 255) (px.color:to-list (px.color:grayscale "white"))))
  (is (equal '(100 25 64 128)
             (px.color:to-list (px.color:premul-alpha '(200 50 128 128)))))
  (is (equal '(0 0 0 0) (px.color:to-list (px.color:premul-alpha '(200 50 128 0))))))

(test named-colors-at-drawing-boundaries
  (px.surface:with-surface (image '(5 5) :alpha t)
    (px.surface:fill image "#10203040")
    (is (equal '(16 32 48 64) (px.color:to-list (px.surface:get-at image '(0 0)))))
    (px.draw:circle image "gold" '(2 2) 1)
    (is (equal '(255 215 0 255) (px.color:to-list (px.surface:get-at image '(2 2)))))
    (signals error (px.surface:fill image "#102030XX"))
    (is (equal '(16 32 48 64) (px.color:to-list (px.surface:get-at image '(0 0)))))))
