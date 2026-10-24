;;;; Small recipes for packaged image bytes and display capability inspection.
(in-package #:pixelisp.examples)

(defun image-memory-demo ()
  "Decode an embedded 2x2 PNG, then return an owned 128x128 nearest-neighbor preview."
  ;; In a game, these encoded bytes could come from an archive or network.
  ;; The four pixels are red, green, blue, and half-transparent yellow.
  (let ((png (make-array 81 :element-type '(unsigned-byte 8)
                         :initial-contents
                         '(137 80 78 71 13 10 26 10 0 0 0 13 73 72 68 82 0 0 0 2
                           0 0 0 2 8 6 0 0 0 114 182 13 36 0 0 0 24 73 68 65 84
                           8 153 5 193 129 1 0 0 4 192 160 248 220 229 83 34 105 71
                           226 30 63 110 6 127 136 97 48 18 0 0 0 0 73 69 78 68 174 66 96 130))))
    (px:with-resource (decoded (px.image:load-bytes png :namehint "icon.png"))
      (px.transform:scale decoded '(128 128)))))

(defun display-report ()
  "Initialize video without opening a window and return copied display information."
  (px:with-init ()
    (list :driver (px.display:get-driver)
          :display-count (px.display:get-num-displays)
          :modes (px.display:list-modes)
          :info (px.display:get-display-info))))
