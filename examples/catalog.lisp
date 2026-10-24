;;;; The registry is deliberately data plus a small dispatcher. New examples
;;;; stay ordinary functions that are equally usable from a REPL or the CLI.
(in-package #:pixelisp.examples)

(defparameter *example-catalog*
  '(("star-collector" :interactive "Collect stars with arrows/WASD; Escape quits.")
    ("sprite-lab" :interactive "Move with arrows/WASD; click to launch additive particles.")
    ("mask-lab" :interactive "Move with arrows/WASD; pink pixels show mask overlap.")
    ("image-lab" :interactive "Compare edges; G grayscale, T threshold, C color.")
    ("ui-lab" :interactive "B filters motion; G/K toggle mouse/keyboard grab; Escape quits.")
    ("pixel-lab" :interactive "Left/Right change tolerance; Space weights; T transpose; R reset.")
    ("pixels" :surface "Generate a gradient through a shared RGB pixel view.")
    ("effects" :surface "Compare alpha, additive, tinted, and premultiplied images.")
    ("palette" :surface "Export named colors with grayscale strips and labels.")
    ("rounded-ui" :surface "Export Color arithmetic and independent corner styles.")
    ("pixel-match" :surface "Export weighted color replacement and native format details.")
    ("memory-image" :surface "Decode an embedded PNG from encoded octets.")
    ("sound" :audio "Generate and play a short sine-wave chime.")
    ("sound-events" :audio "Queue two chimes and process their completion events.")
    ("mask-info" :values "Return an overlap position and collision area.")
    ("display-info" :values "Inspect the video driver, displays, and enumerated modes.")))

(defun list-examples ()
  "Return fresh plists with :NAME, :KIND, and :DESCRIPTION for all examples."
  (loop for (name kind description) in *example-catalog*
        collect (list :name (copy-seq name) :kind kind :description (copy-seq description))))

(defun run-example (name &key frames (fps 60) output (audio t))
  "Run a named example. FRAMES bounds interactive runs; NIL runs until quit.
Surface examples return an owned surface, or save/dispose it when OUTPUT is
provided. FPS controls the labs; Star Collector uses its own 60 FPS clock.
AUDIO controls Star Collector and the standalone sound example."
  (check-type frames (or null (integer 0 *)))
  (check-type fps (integer 1 *))
  (let* ((name (string-downcase (string name)))
         (entry (assoc name *example-catalog* :test #'string=)))
    (unless entry (error "Unknown example ~S. Use LIST-EXAMPLES to see available names." name))
    (when (and output (not (eq (second entry) :surface)))
      (error "OUTPUT is supported by surface examples only."))
    (cond ((string= name "star-collector") (play :frames frames :audio audio))
          ((string= name "sprite-lab") (sprite-lab :frames frames :fps fps))
          ((string= name "mask-lab") (mask-lab :frames frames :fps fps))
          ((string= name "image-lab") (image-lab :frames frames :fps fps))
          ((string= name "ui-lab") (ui-lab :frames frames :fps fps))
          ((string= name "pixel-lab") (pixel-lab :frames frames :fps fps))
          ((string= name "sound") (when audio (sound-demo)))
          ((string= name "sound-events") (when audio (audio-events-demo)))
          ((string= name "mask-info") (mask-demo))
          ((string= name "display-info") (display-report))
          ((eq (second entry) :surface)
           (let ((image (cond ((string= name "pixels") (pixel-demo))
                              ((string= name "palette") (palette-demo))
                              ((string= name "rounded-ui") (ui-demo))
                              ((string= name "pixel-match") (pixel-match-demo))
                              ((string= name "memory-image") (image-memory-demo))
                              (t (effects-demo)))))
             (if output
                 (unwind-protect (progn (px.image:save image output) output)
                   (px:dispose image))
                 image))))))
