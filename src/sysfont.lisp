;;;; Fontconfig-backed system font discovery and family matching.
;;;; Discovery only records paths; it never opens a native font handle.
(in-package #:pixelisp.font)

(defvar *font-inventory* nil)
(defvar *font-aliases* nil)
(defvar *font-inventory-ready-p* nil)

(defparameter *font-alias-groups*
  '(("monospace" "mono" "fixed" "miscfixed" "courier" "couriernew"
     "console" "freemono" "dejavusansmono" "liberationmono"
     "bitstreamverasansmono" "consolas")
    ("sans" "sansserif" "arial" "helvetica" "swiss" "freesans"
     "dejavusans" "liberationsans" "bitstreamverasans" "verdana"
     "tahoma" "calibri" "gillsans" "segoeui" "trebuchetms" "ubuntu")
    ("serif" "times" "timesroman" "timesnewroman" "roman" "dutch"
     "freeserif" "dejavuserif" "liberationserif" "bitstreamveraserif"
     "georgia" "cambria" "constantia")
    ("wingdings" "wingbats")
    ("comicsansms" "comicsans")))

(defun %simple-font-name (name)
  "Return pygame's lowercase alphanumeric font-family key."
  (with-output-to-string (result)
    (loop for character across name
          when (alphanumericp character)
            do (write-char (char-downcase character) result))))

(defun %validate-font-name (name)
  (check-type name string)
  (when (find #\Nul name)
    (error 'pixelisp:error :operation 'match-font
           :message "Font names cannot contain NUL characters."))
  name)

(defun %split-on (string delimiter)
  (loop with start = 0
        for end = (position delimiter string :start start)
        collect (subseq string start end)
        while end
        do (setf start (1+ end))))

(defun %style-flags (style)
  (let ((simple (string-downcase style)))
    (values (or (search "bold" simple) (search "demi" simple))
            (or (search "italic" simple) (search "oblique" simple)))))

(defun %font-entry (inventory family style path)
  (let ((key (%simple-font-name family)))
    (when (plusp (length key))
      (multiple-value-bind (bold italic) (%style-flags style)
        (let ((styles (or (gethash key inventory)
                          (setf (gethash key inventory) (make-hash-table :test 'equal)))))
          ;; Keep the first discovered path for a duplicate family/style.
          ;; Once cached, repeated lookups use this same selected face.
          (unless (gethash (list (not (null bold)) (not (null italic))) styles)
            (setf (gethash (list (not (null bold)) (not (null italic))) styles) path)))))))

(defun %font-path-p (path)
  (member (string-downcase (or (pathname-type path) "")) '("ttf" "ttc" "otf")
          :test #'string=))

(defun %parse-fontconfig-line (line inventory)
  (let ((fields (%split-on line #\Tab)))
    (when (= (length fields) 3)
      (destructuring-bind (path families style) fields
        (when (and (plusp (length path)) (%font-path-p path))
          (dolist (family (%split-on families #\,))
            (let ((family (string-trim '(#\Space #\Tab) family)))
              (when (plusp (length family))
                (%font-entry inventory family style path)))))))))

(defun %alias-fonts (inventory)
  (let ((aliases (make-hash-table :test 'equal)))
    (dolist (group *font-alias-groups* aliases)
      (let ((styles (loop for candidate in group
                          for found = (gethash candidate inventory)
                          when found return found)))
        (when styles
          (dolist (alias group)
            (unless (gethash alias inventory)
              (setf (gethash alias aliases) styles))))))))

(defun %ensure-font-inventory ()
  (unless *font-inventory-ready-p*
    (let ((inventory (make-hash-table :test 'equal))
          (output (%fontconfig "fc-list"
                               (list "-f" "%{file}\\t%{family}\\t%{style}\\n"))))
      (when output
        (dolist (line (%split-on output #\Newline))
          (unless (zerop (length line))
            (%parse-fontconfig-line line inventory))))
      (setf *font-inventory* inventory
            *font-aliases* (%alias-fonts inventory)
            *font-inventory-ready-p* t)))
  *font-inventory*)

(defun %reset-font-inventory ()
  "Clear the private discovery cache (also used by isolated tests)."
  (setf *font-inventory* nil *font-aliases* nil *font-inventory-ready-p* nil))

(defun get-fonts ()
  "Return a fresh sorted list of normalized installed OpenType family names."
  (let ((inventory (%ensure-font-inventory)))
    (sort (loop for name being the hash-keys of inventory collect (copy-seq name)) #'string<)))

(defun %font-styles (name)
  (or (gethash name (%ensure-font-inventory))
      (gethash name *font-aliases*)))

(defun %style-preference (bold italic)
  (let* ((requested (list (not (null bold)) (not (null italic))))
         (single (cond ((and bold italic)
                        (list '(t nil) '(nil t) '(nil nil)))
                       (bold (list '(nil nil) '(nil t) '(t t)))
                       (italic (list '(nil nil) '(t nil) '(t t)))
                       (t (list '(t nil) '(nil t) '(t t))))))
    (cons requested single)))

(defun %select-font-path (styles bold italic)
  (when styles
    (loop for key in (%style-preference bold italic)
          for path = (gethash key styles)
          when path return (values path (first key) (second key)))))

(defun %font-name-candidates (name)
  (cond ((null name) nil)
        ((stringp name) (%split-on (%validate-font-name name) #\,))
        ((and (vectorp name) (not (stringp name))) (coerce name 'list))
        ((listp name) name)
        (t (error 'type-error :datum name :expected-type '(or null string list vector)))))

(defun %match-system-font (name &key bold italic)
  "Return an installed path and the bold/italic flags of its actual face."
  (check-type bold boolean)
  (check-type italic boolean)
  (block found
    (loop for candidate in (%font-name-candidates name)
          do (let* ((family (%simple-font-name (%validate-font-name candidate)))
                    (styles (%font-styles family)))
               (multiple-value-bind (path actual-bold actual-italic)
                   (%select-font-path styles bold italic)
                 (when path
                   (return-from found
                     (values (copy-seq path) actual-bold actual-italic))))))))

(defun match-font (name &key bold italic)
  "Return the path of an installed font matching NAME, or NIL.

NAME may be a family name, comma-separated fallback string, list, vector, or
NIL. Bold and italic variants are preferred, then a close installed style."
  (nth-value 0 (%match-system-font name :bold bold :italic italic)))

(defun sys-font (name point-size &key bold italic)
  "Open a matched system face, synthesizing only unavailable requested styles."
  (check-type bold boolean)
  (check-type italic boolean)
  (multiple-value-bind (path actual-bold actual-italic)
      (%match-system-font name :bold bold :italic italic)
    (let ((font (make-font (or path (get-default-font)) point-size))
          (complete nil))
      (unwind-protect
           (progn
             (when (and bold (not actual-bold)) (set-bold font t))
             (when (and italic (not actual-italic)) (set-italic font t))
             (setf complete t)
             font)
        (unless complete (close font))))))

(setf (fdefinition 'sysfont) #'sys-font)
