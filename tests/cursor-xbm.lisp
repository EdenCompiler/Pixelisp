(in-package #:pixelisp.tests)
(in-suite pixelisp)

(defparameter *cursor-xbm-fixture*
  (format nil "#define cursor_width 16~%#define cursor_height 2~%#define cursor_x_hot 3~%#define cursor_y_hot 1~%static unsigned char cursor_bits[] = {~%  0x01, 0x80,~%  0x02, 0x00~%};~%"))

(defparameter *cursor-xbm-mask-fixture*
  (format nil "#define mask_width 16~%#define mask_height 2~%static char mask_bits[] = {~%  0xff, 0x80, 0x00, 0x01~%};~%"))

(test xbm-decodes-pygame-order-and-default-mask
  (multiple-value-bind (size hotspot data mask)
      (px.cursors:load-xbm (make-string-input-stream *cursor-xbm-fixture*))
    (is (equal '(16 2) size))
    (is (equal '(3 1) hotspot))
    (is (equalp #(128 1 64 0) data))
    (is (equalp #(255 255 255 255) mask))
    (is (typep data '(vector (unsigned-byte 8))))
    (is (typep mask '(vector (unsigned-byte 8))))))

(test xbm-parses-separate-mask-and-default-hotspot
  (multiple-value-bind (size hotspot data mask)
      (px.cursors:load-xbm (make-string-input-stream *cursor-xbm-fixture*)
                           (make-string-input-stream *cursor-xbm-mask-fixture*))
    (is (equal '(16 2) size))
    (is (equal '(3 1) hotspot))
    (is (equalp #(128 1 64 0) data))
    (is (equalp #(255 1 0 128) mask)))
  (let ((no-hotspot (format nil "#define x_width 8~%#define x_height 1~%static char x_bits[] = {0x81};~%")))
    (multiple-value-bind (size hotspot data mask)
        (px.cursors:load-xbm (make-string-input-stream no-hotspot))
      (is (equal '(8 1) size))
      (is (equal '(0 0) hotspot))
      (is (equalp #(129) data))
      (is (equalp #(255) mask)))))

(test xbm-path-and-borrowed-stream-input
  (let ((path (merge-pathnames (format nil "pixelisp-xbm-~A.xbm" (gensym))
                               (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (with-open-file (out path :direction :output :if-exists :supersede)
             (write-string *cursor-xbm-fixture* out))
           (multiple-value-bind (size hotspot data mask) (px.cursors:load-xbm path)
             (is (equal '(16 2) size))
             (is (equal '(3 1) hotspot))
             (is (equalp #(128 1 64 0) data))
             (is (equalp #(255 255 255 255) mask))))
      (when (probe-file path) (delete-file path))))
  (let* ((preamble (format nil "ignored preamble~%"))
         (input (concatenate 'string preamble *cursor-xbm-fixture*))
         (stream (make-string-input-stream input)))
    (file-position stream (length preamble))
    (px.cursors:load-xbm stream)
    (is (open-stream-p stream))))

(test xbm-validates-full-assets-before-returning-cursor-data
  (dolist (invalid
           (list (format nil "#define x_width 7~%#define x_height 1~%static char x_bits[] = {0xff};~%")
                 (format nil "#define x_width 8~%#define x_height 1~%static char x_bits[] = {0x01,0x02};~%")
                 (format nil "#define x_width 8UU~%#define x_height 1~%static char x_bits[] = {0x01};~%")
                 (format nil "#define x_width 8~%#define x_height 1~%#define x_x_hot 8~%#define x_y_hot 0~%static char x_bits[] = {0x01};~%")))
    (signals pixelisp:error (px.cursors:load-xbm (make-string-input-stream invalid))))
  (signals pixelisp:error
    (px.cursors:load-xbm (make-string-input-stream
                          (format nil "#define x_width 8~%#define x_height 1~%/* no end~%static char x_bits[] = {0x01};~%"))))
  (signals pixelisp:error
    (px.cursors:load-xbm (make-string-input-stream *cursor-xbm-fixture*)
                         (make-string-input-stream
                          (format nil "#define m_width 8~%#define m_height 2~%static char m_bits[] = {0,0};~%")))))
