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
sudo apt install sbcl build-essential pkg-config libsdl2-dev libsdl2-image-dev \
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
| `pixelisp/freetype` | Direct FreeType text rendering and metrics |
| `pixelisp/midi` | PortMidi streams and MIDI utilities |
| `pixelisp/camera` | Linux V4L2 capture and colorspace utilities |
| `pixelisp/all` | All of the above; loading does not open devices |
| `pixelisp/examples` | Playable game, interactive labs, and a catalog/CLI |
| `pixelisp/examples/tests` | Bounded example runs and synthetic-input tests |
| `pixelisp/tests` | FiveAM tests, including optional hardware checks |

Camera and post-mix capture build a small C adapter lazily in ASDF's output
cache. The regular toolkit does not require that build. Missing libraries and
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
make demo
# Or: sbcl --script scripts/play.lisp
make examples       # List every example.
make demo-sprites   # Single-player group and additive particles.
make demo-masks     # Move silhouettes and inspect pixel collisions.
make demo-images    # Compare color/grayscale/thresholded Laplacian edges.
make demo-ui        # Color arithmetic, corner styles, event filters and grabs.
make demo-pixels    # Weighted replacement, transposed views and keyboard repeat.
```

Star Collector uses arrows/WASD, rotating images, sprite groups, mask
collisions, UTF-8 text, and a generated chime. Press Escape to exit. Resizing
scales its fixed logical drawing surface to the window.

The [example guide](docs/EXAMPLES.md) describes controls, ownership, and the
pygame capabilities demonstrated by all sixteen examples. The shared launcher
accepts bounded runs and can export generated surfaces:

```sh
sbcl --script scripts/example.lisp sprite-lab --frames 120
sbcl --script scripts/example.lisp effects --output effects.png
sbcl --script scripts/example.lisp palette --output palette.png
sbcl --script scripts/example.lisp sound-events
sbcl --script scripts/example.lisp ui-lab
sbcl --script scripts/example.lisp rounded-ui --output ui.png
sbcl --script scripts/example.lisp pixel-lab
sbcl --script scripts/example.lisp pixel-match --output pixel-match.png
sbcl --script scripts/example.lisp memory-image --output memory-image.png
sbcl --script scripts/example.lisp display-info
```

For a bounded headless smoke test:

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy sbcl --script scripts/play.lisp 10
```

From the REPL:

```lisp
(ql:quickload "pixelisp/examples")
(px.examples:play :audio nil) ; Run without opening an audio device.
(px.examples:mask-demo)      ; Returns an overlap coordinate and area.
(px:with-resource (image (px.examples:pixel-demo))
  (px.image:save image #p"gradient.png"))
(px:with-resource (image (px.examples:effects-demo))
  (px.image:save image #p"effects.png")) ; Alpha, additive, tinted, premultiplied.
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
`python3 scripts/differential.py` runs thirty-six selected reference fixtures,
including every bundled named color. It needs pygame 2.6.1 only as test tooling.

- [Surface, event, timing, and array APIs](docs/API-core.md)
- [Drawing, transforms, masks, vectors, and sprites](docs/API-graphics.md)
- [Images, fonts, FreeType, sounds, music, and sample arrays](docs/API-media.md)
- [Devices, MIDI, cameras, workers, and SDL2 extensions](docs/API-devices.md)
- [Coverage, adaptations, and verification limits](docs/COVERAGE.md)
- [Contributor guide and code map](CONTRIBUTING.md)

Pixelisp's code is MIT licensed. The bundled DejaVu Sans font retains its own
license in `examples/assets/LICENSE-DejaVu.txt`. Native dependencies retain
their respective licenses.
