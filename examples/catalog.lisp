;;;; A small registry keeps the CLI, REPL, and documentation using the same games.
(in-package #:pixelisp.examples)

(defparameter *game-catalog*
  '(("prism-breaker" make-prism-breaker "Clear 60 prisms with a paddle, a ball, and three lives.")
    ("orbit-patrol" make-orbit-patrol "Thrust, turn, and shoot 12 threats in a wrapping starfield.")
    ("crater-command" make-crater-command "Aim ballistic shells through destructible terrain at three reactors.")
    ("echo-grove" make-echo-grove "Repeat six growing melodies using four colored pads.")))

(defun list-examples ()
  "Return fresh catalog plists; callers may edit them without changing the registry."
  (loop for (name factory description) in *game-catalog*
        collect (list :name (copy-seq name) :kind :game :description (copy-seq description))))

(defun run-example (name &key frames (fps 60) (audio t) (seed 1) fixed-dt screenshot
                            (backend :surface))
  "Play a named game and return its final gameplay snapshot.
FRAMES bounds a run; FIXED-DT sets simulation seconds per frame (at most 0.05).
SCREENSHOT saves the final rendered frame before native resources are released."
  (let ((entry (assoc (string-downcase (string name)) *game-catalog* :test #'string=)))
    (unless entry (error "Unknown game ~S. Use LIST-EXAMPLES to see the catalog." name))
    (%run-mini-game (symbol-function (second entry)) :frames frames :fps fps
                    :audio audio :seed seed :fixed-dt fixed-dt :screenshot screenshot :backend backend)))

(defun play (&rest options &key frames (fps 60) (audio t) (seed 1) fixed-dt screenshot (backend :surface))
  "Start Prism Breaker. RUN-EXAMPLE accepts the same options for other games."
  (declare (ignore frames fps audio seed fixed-dt screenshot backend))
  (apply #'run-example "prism-breaker" options))
