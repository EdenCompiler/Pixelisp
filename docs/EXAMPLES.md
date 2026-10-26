# Games

The `pixelisp/examples` system contains four playable mini-games built on the
shared 900×620 runner. From the repository, `make demo` starts Prism Breaker;
`make examples` lists the catalog. Use `make play-breaker`, `make play-orbit`,
`make play-crater`, or `make play-echo` to start a specific game.

All games respond to Escape to quit, P to pause or resume, R to restart, and
F11 to toggle desktop fullscreen.
The runner owns the window and game resources, forwards input to the game,
updates only while active, and draws a common pause or end-state overlay.

| Game | Goal and controls | Gameplay mechanics |
| --- | --- | --- |
| **Prism Breaker** | Clear all 60 prisms. Move the paddle with the mouse or Left/Right; press Space to serve. Three missed balls end the run. | Rect collisions and vector reflection drive wall, paddle, and brick bounces. Combos increase the score; generated tones mark serves, impacts, and lost balls. Cached surfaces keep brick and ball rendering on native blits. |
| **Orbit Patrol** | Turn with Left/Right or A/D, thrust with Up/W, and fire with Space. Destroy 12 targets while avoiding contact. | A rotating ship moves under vector-based thrust and inertia. Projectiles, target collisions, lives, and short invulnerability windows create the arcade challenge; sound gives feedback for shots and hits. |
| **Crater Command** | Aim with Left/Right or horizontal scrolling, adjust shell power with Up/Down or vertical scrolling, and fire with Space. Destroy three reactors before running out of shells. | Shells follow a ballistic arc over a deformable landscape. Fractional trackpad deltas allow fine aim and power changes. Impacts remove terrain pixels and collision-mask bits together, so craters affect later shots. Generated impact tones reinforce hits. |
| **Echo Grove** | Watch and listen to a four-pad sequence, then repeat it with keys 1–4, the arrow keys, or mouse clicks. Reach six rounds before losing three mistake lives. | The sequence grows one note at a time. Each pad has an always-visible color cue and an optional generated tone, so the game remains playable with audio disabled. |

The games demonstrate library features through their mechanics: Prism Breaker
uses rectangles, vectors, native surface blits, and generated sound; Orbit
Patrol uses cached rotations with RLE source blits, vectors, and pixel-mask collisions; Crater Command
joins rendered terrain to a mutable mask; Echo Grove combines event input,
cached text, pad sprites sampling dim/lit frames from a shared image atlas,
and optional audio. The atlas uses indexed 8-bit pixels; changing a shared
highlight palette entry warns when one mistake life remains, and restores the
normal highlight on restart without rebuilding pixels. Its melody cues are
generated WAV assets decoded from memory and cached for replay; other games
construct sounds directly from sample arrays. Game state and update
helpers are ordinary Lisp data and functions, which makes the rules testable
without a native window.

Orbit Patrol unpacks its thrust velocity with `px.math:swizzle`. Crater Command
erases terrain alpha through `px.surface:get-view` while updating the collision
mask, so the shared view directly changes the next shot's path.
Crater Command reads precise wheel deltas and accounts for flipped scrolling;
integer-only mouse wheels use the same controls. Every game shares encoded
font data across its cached text sizes, loading each font from memory rather
than reopening its asset path for each size.

## Command line

The launcher accepts a game name and optional frame, rate, audio, random seed,
and screenshot settings:

```sh
sbcl --script scripts/example.lisp --list
sbcl --script scripts/example.lisp prism-breaker --frames 120 --fps 60
sbcl --script scripts/example.lisp orbit-patrol --seed 7 --no-audio
sbcl --script scripts/example.lisp crater-command --frames 120 --seed 7
sbcl --script scripts/example.lisp echo-grove --screenshot /tmp/echo.png
sbcl --script scripts/example.lisp echo-grove --screenshot /tmp/echo.tga
sbcl --script scripts/example.lisp orbit-patrol --backend renderer
```

`--frames N` bounds a run for smoke tests; without it, play continues until
quit. `--fps N` sets the frame cap. `--seed N` makes randomized game setup
repeatable. `--screenshot FILE` saves the rendered frame. `--no-audio` disables
audio while preserving visual feedback. The REPL runner also accepts `:fixed-dt` (positive seconds, at most 0.05)
for a stable update interval when a reproducible simulation is needed.

`--backend renderer` uses a resizable SDL renderer window. The game still draws
to its 900×620 CPU canvas, then `update-texture` uploads it to a streaming
texture for presentation. Logical sizing preserves game coordinates and scales
native mouse input when the window changes size. Hardware acceleration is tried
first, with a software fallback for environments such as the dummy driver.
The streaming texture is retained by a reusable `px.sdl2.video:image` wrapper,
which draws the frame through the same API used for cropped texture atlases.
The runner presents this image with `px.sdl2.video:blit`, so the convenience
operation is exercised by the games and their screenshot tests.
The default is `--backend surface`. Renderer screenshots read the completed
backbuffer before presenting it, and reflect the window's actual pixel size.
SDL clips the read to its physical viewport, leaving transparent letterbox
margins. Fullscreen requests require a window manager to apply the requested
geometry; bare Xvfb can acknowledge fullscreen without resizing the X11 window.
This provides a small, readable path from the surface-based games to the
separate renderer API; it does not move their CPU drawing onto the GPU.

Set SDL's dummy drivers for bounded headless runs:

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  sbcl --script scripts/example.lisp prism-breaker --frames 10 --no-audio
```

From the REPL:

```lisp
(ql:quickload "pixelisp/examples")
(px.examples:list-examples)
(px.examples:run-example "prism-breaker" :frames 120 :seed 7 :fixed-dt 0.0167
                         :audio nil :backend :renderer)
```

The REPL runner also accepts a binary output stream for `:screenshot`. It
writes a complete TGA image at the stream's current position and leaves it
open. This allows storing the actual game frame directly in an archive or
other caller-managed output without an intermediate screenshot file.

The bounded game suite is available through `make test-examples` or
`(asdf:test-system "pixelisp/examples")`. It checks native runner integration,
synthetic input, gameplay outcomes, and resource cleanup.
