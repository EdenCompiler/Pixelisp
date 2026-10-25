# Pixelisp

A pygame-style game and multimedia library for Common Lisp. Pixelisp uses SDL2
for native surfaces, windows, events, input, audio, and text. It also includes
CPU drawing, transforms, collision masks, vectors, sprites, native pixel views,
MIDI, Linux cameras, and optional SDL renderer/audio APIs.

The API follows pygame's concepts with Lisp spelling and explicit receiver
arguments. It targets **equivalent capabilities**, not source compatibility or
pixel-identical results for every pygame operation. The reference catalog is
pygame 2.6.1. See [coverage and differences](docs/COVERAGE.md).

## Install and load

The tested setup is Linux with SBCL and Quicklisp. On Debian/Ubuntu, the native
development packages can be installed with:

```sh
sudo apt install sbcl build-essential pkg-config libffi-dev libsdl2-dev libsdl2-image-dev \
  libsdl2-ttf-dev libsdl2-mixer-dev libfreetype-dev libportmidi0 libv4l-0
```

With Quicklisp installed, start a Lisp in this directory and register the local
ASDF file. Pixelisp is not yet published in the Quicklisp distribution:

```lisp
(require :asdf)
(asdf:load-asd (truename "pixelisp.asd"))
(ql:quickload "pixelisp")
```

Available systems:

| System | Contents |
| --- | --- |
| `pixelisp/core` | Colors, rectangles, vectors, resource/view protocols, sprite bookkeeping; no SDL dependency |
| `pixelisp` | SDL2 game toolkit, arrays, text/audio, input, threads, renderer and raw-audio extensions |
| `pixelisp/freetype` | Direct FreeType rendering, independent size axes, rotation/vertical layout, synthetic styles, coverage arrays, and face/strike metrics |
| `pixelisp/midi` | PortMidi streams and MIDI utilities |
| `pixelisp/camera` | Linux V4L2 capture and colorspace utilities |
| `pixelisp/all` | All of the above; loading does not open devices |
| `pixelisp/examples` | Four playable mini-games and a shared runner/CLI |
| `pixelisp/examples/tests` | Bounded game runs and synthetic-input tests |
| `pixelisp/tests` | FiveAM tests, including optional hardware checks |

Camera capture, post-mix capture, and PNG/JPEG/BMP encoding into memory build
a small C adapter lazily in ASDF's output cache. Other toolkit features do not
require that build. Missing libraries and
initialization failures signal Lisp conditions with operation details.

## First game loop

```lisp
(px:with-init ()
  (let ((screen (px.display:set-mode '(640 480) :title "Hello, Pixelisp"))
        (clock (px.time:make-clock))
        (running t))
    (loop while running do
      (dolist (event (px.event:get))
        (when (eq (px.event:type event) :quit)
          (setf running nil)))
      (px.surface:fill screen '(20 25 40))
      (px.draw:circle screen '(90 200 240) '(320 240) 45)
      (px.display:flip)
      (px.time:tick clock 60))))
```

`px` is a nickname for `pixelisp`; every module has a matching nickname, such as
`px.surface` for `pixelisp.surface`. Use lists or vectors for positions and
colors. Constructors use `make-*`, object operations take the receiver first,
and writable properties use `setf`. Common event types are `:quit`, `:key-down`,
`:key-up`, `:mouse-motion`, and `:text-input`; key attributes use keywords such
as `:escape` or `:left`.

## Run the examples

```sh
make demo             # Start Prism Breaker, the default game.
make examples         # List the four games.
make play-breaker     # Prism Breaker.
make play-orbit       # Orbit Patrol.
make play-crater      # Crater Command.
make play-echo        # Echo Grove.
```

The four games share a 900×620 canvas. Press Escape to quit, P to pause or
resume, and R to restart the current game. Prism Breaker uses the mouse or
Left/Right to move and Space to launch the ball. Orbit Patrol uses Left/Right
or A/D to turn, Up/W to thrust, and Space to fire. Crater Command uses
Left/Right to aim, Up/Down to set power, and Space to fire. Echo Grove plays a
four-pad sequence to watch and listen to, then repeat with keys 1–4, the
arrows, or the mouse. It has a six-round goal and three mistake lives; audio
can be disabled while its visual cues remain available.

The [game guide](docs/EXAMPLES.md) explains each objective and the gameplay
mechanics used to demonstrate surfaces, sprites, masks, vectors, audio, and
input. The shared launcher accepts bounded, seeded runs and screenshots:

```sh
sbcl --script scripts/example.lisp prism-breaker --frames 120 --fps 60
sbcl --script scripts/example.lisp orbit-patrol --no-audio --seed 7
sbcl --script scripts/example.lisp crater-command --frames 120 --seed 7
sbcl --script scripts/example.lisp echo-grove --screenshot echo.png
sbcl --script scripts/example.lisp orbit-patrol --backend renderer
```

`--backend renderer` presents the same game through a streaming SDL texture in
a resizable window. It tries hardware acceleration and falls back to software
rendering when unavailable. The default `surface` backend keeps the original
window-surface loop. Both backends support screenshots and bounded runs.
Press F11 to toggle desktop fullscreen in either backend. The renderer backend
uses an `Image` view over its framebuffer texture; cached Orbit Patrol frames
use SDL's RLE source-blit hint.

For a bounded headless smoke test:

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  sbcl --script scripts/example.lisp prism-breaker --frames 10 --no-audio
```

From the REPL, list and run games through the shared API:

```lisp
(ql:quickload "pixelisp/examples")
(px.examples:list-examples)
(px.examples:run-example "prism-breaker" :frames 120 :audio nil :seed 7)
```

## Resource and thread rules

- Dispose native resources explicitly, or use `with-resource`, `with-surface`,
  and `with-view`. `with-init` disposes remaining registered resources on exit.
- A subsurface shares pixels with its parent. Closing a parent makes its child
  unusable. An active pixel view pins the storage and prevents disposal.
- `array*` operations copy to ordinary Lisp arrays. `pixels*` and `samples`
  return explicit live views accessed through `px.buffer:view-ref` and `setf`.
  Close dependent slices before their parent view.
- Create windows, pump events, draw to windows, and present on the initializing
  thread. Worker threads can post ordinary Lisp events. Shared mutable assets
  require application locking.
- Call `px.event:get` each frame. It also delivers timers and advances queued
  sounds/music on the Lisp thread.

SDL signal-handler installation is disabled to preserve the Lisp runtime's
handlers. Scoped native contexts mask graphics-driver floating-point traps on
SBCL and restore the caller's settings afterward.

## Tests and documentation

```sh
make test       # SDL dummy video/audio: no physical devices required.
make test-x11   # Xvfb window, renderer, and clipboard integration.
make test-examples # Bounded examples with generated mouse/key events.
```

After loading dependencies, `(asdf:test-system "pixelisp")` runs the same suite.
The library does not depend on Python. With pygame 2.6.1 installed,
`python3 scripts/differential.py` runs selected reference fixtures,
including every bundled named color. It needs pygame 2.6.1 only as test tooling.

- [Surface, event, timing, and array APIs](docs/API-core.md)
- [Drawing, transforms, masks, vectors, and sprites](docs/API-graphics.md)
- [Images, fonts, FreeType, sounds, music, and sample arrays](docs/API-media.md)
- [Devices, MIDI, cameras, workers, and SDL2 extensions](docs/API-devices.md)
- [Coverage, adaptations, and verification limits](docs/COVERAGE.md)
- [Contributor guide and code map](CONTRIBUTING.md)

Pixelisp's code is MIT licensed. The bundled DejaVu Sans font retains its own
license in `assets/fonts/LICENSE-DejaVu.txt`. Native dependencies retain
their respective licenses.
