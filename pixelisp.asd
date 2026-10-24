;;;; Pixelisp — pygame-style multimedia for Common Lisp.
(asdf:defsystem "pixelisp/core"
  :description "Native-independent Pixelisp geometry, mathematics, and resource protocols"
  :version "0.1.0" :license "MIT"
  :depends-on ("bordeaux-threads")
  :serial t
  :components ((:file "src/packages") (:file "src/core") (:file "src/rect-tools")
               (:file "src/color-names") (:file "src/colors") (:file "src/math")
               (:file "src/buffer") (:file "src/sprite")))

(asdf:defsystem "pixelisp"
  :description "A pygame-style game and multimedia library for Common Lisp"
  :version "0.1.0" :license "MIT"
  :depends-on ("pixelisp/core" "sdl2" "sdl2-image" "sdl2-ttf" "sdl2-mixer"
               "cffi" "trivial-garbage")
  :serial t
  :components ((:file "src/surface") (:file "src/runtime") (:file "src/graphics") (:file "src/mask-surface")
               (:file "src/arrays") (:file "src/media") (:file "src/sndarray")
               (:file "src/devices") (:file "src/threads") (:file "src/sdl2-ext")
               (:file "src/legacy") (:static-file "native/pixelisp-native.c")
               (:static-file "examples/assets/DejaVuSans.ttf")
               (:static-file "examples/assets/LICENSE-DejaVu.txt")
               (:static-file "LICENSE"))
  :in-order-to ((asdf:test-op (asdf:test-op "pixelisp/tests"))))

(asdf:defsystem "pixelisp/freetype"
  :depends-on ("pixelisp" "cl-freetype2")
  :components ((:file "src/freetype")))
(asdf:defsystem "pixelisp/midi"
  :depends-on ("pixelisp") :components ((:file "src/midi")))
(asdf:defsystem "pixelisp/camera"
  :depends-on ("pixelisp") :components ((:file "src/camera")))
(asdf:defsystem "pixelisp/all"
  :depends-on ("pixelisp" "pixelisp/freetype" "pixelisp/midi" "pixelisp/camera"))
(asdf:defsystem "pixelisp/examples"
  :depends-on ("pixelisp") :serial t
  :components ((:file "examples/examples") (:file "examples/sprite-lab")
               (:file "examples/mask-lab") (:file "examples/image-lab")
               (:file "examples/api-recipes") (:file "examples/ui-lab") (:file "examples/pixel-lab")
               (:file "examples/system-recipes")
               (:file "examples/catalog"))
  :in-order-to ((asdf:test-op (asdf:test-op "pixelisp/examples/tests"))))
(asdf:defsystem "pixelisp/examples/tests"
  :depends-on ("pixelisp/examples" "fiveam")
  :components ((:file "tests/examples"))
  :perform (asdf:test-op (o c) (declare (ignore o c))
             (unless (uiop:symbol-call :fiveam :run!
                       (find-symbol "EXAMPLES" :pixelisp.examples.tests))
               (error "Pixelisp example tests failed."))))
(asdf:defsystem "pixelisp/tests"
  :depends-on ("pixelisp/all" "fiveam") :serial t
  :components ((:file "tests/suite") (:file "tests/core") (:file "tests/rect-extra") (:file "tests/rect-tools")
               (:file "tests/colors") (:file "tests/color-parsing") (:file "tests/color-arithmetic")
               (:file "tests/math-extra") (:file "tests/vector-api") (:file "tests/value-updates")
               (:file "tests/arrays")
               (:file "tests/pixelarray-extra") (:file "tests/surface-batch")
               (:file "tests/surface-effects") (:file "tests/surface-info") (:file "tests/mask-surface")
               (:file "tests/runtime") (:file "tests/display-info")
               (:file "tests/event-controls") (:file "tests/key-repeat")
               (:file "tests/graphics") (:file "tests/rounded-rect")
               (:file "tests/sprite-extra") (:file "tests/laplacian")
               (:file "tests/media") (:file "tests/image-memory")
               (:file "tests/audio-events") (:file "tests/devices"))
  :perform (asdf:test-op (o c) (declare (ignore o c))
             (unless (uiop:symbol-call :fiveam :run! (find-symbol "PIXELISP" :pixelisp.tests))
               (error "Pixelisp tests failed."))))
