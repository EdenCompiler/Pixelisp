# Games

The `pixelisp/examples` system contains four playable mini-games built on the
shared 900×620 runner. From the repository, `make demo` starts Prism Breaker;
`make examples` lists the catalog. Use `make play-breaker`, `make play-orbit`,
`make play-crater`, or `make play-echo` to start a specific game.

All games respond to Escape to quit, P to pause or resume, and R to restart.
The runner owns the window and game resources, forwards input to the game,
updates only while active, and draws a common pause or end-state overlay.

| Game | Goal and controls | Gameplay mechanics |
| --- | --- | --- |
| **Prism Breaker** | Clear all 60 prisms. Move the paddle with the mouse or Left/Right; press Space to serve. Three missed balls end the run. | Rect collisions and vector reflection drive wall, paddle, and brick bounces. Combos increase the score; generated tones mark serves, impacts, and lost balls. Cached surfaces keep brick and ball rendering on native blits. |
| **Orbit Patrol** | Turn with Left/Right or A/D, thrust with Up/W, and fire with Space. Destroy 12 targets while avoiding contact. | A rotating ship moves under vector-based thrust and inertia. Projectiles, target collisions, lives, and short invulnerability windows create the arcade challenge; sound gives feedback for shots and hits. |
| **Crater Command** | Aim with Left/Right, adjust shell power with Up/Down, and fire with Space. Destroy three reactors before running out of shells. | Shells follow a ballistic arc over a deformable landscape. Impacts remove terrain pixels and collision-mask bits together, so craters affect later shots. Generated impact tones reinforce hits. |
| **Echo Grove** | Watch and listen to a four-pad sequence, then repeat it with keys 1–4, the arrow keys, or mouse clicks. Reach six rounds before losing three mistake lives. | The sequence grows one note at a time. Each pad has an always-visible color cue and an optional generated tone, so the game remains playable with audio disabled. |

The games demonstrate library features through their mechanics: Prism Breaker
uses rectangles, vectors, native surface blits, and generated sound; Orbit
Patrol uses cached rotations, vectors, and pixel-mask collisions; Crater Command
joins rendered terrain to a mutable mask; Echo Grove combines event input,
cached text, ordered pad sprites, and optional audio. Game state and update
helpers are ordinary Lisp data and functions, which makes the rules testable
without a native window.

Orbit Patrol unpacks its thrust velocity with `px.math:swizzle`. Crater Command
erases terrain alpha through `px.surface:get-view` while updating the collision
mask, so the shared view directly changes the next shot's path.

## Command line

The launcher accepts a game name and optional frame, rate, audio, random seed,
and screenshot settings:

```sh
sbcl --script scripts/example.lisp --list
sbcl --script scripts/example.lisp prism-breaker --frames 120 --fps 60
sbcl --script scripts/example.lisp orbit-patrol --seed 7 --no-audio
sbcl --script scripts/example.lisp crater-command --frames 120 --seed 7
sbcl --script scripts/example.lisp echo-grove --screenshot /tmp/echo.png
```

`--frames N` bounds a run for smoke tests; without it, play continues until
quit. `--fps N` sets the frame cap. `--seed N` makes randomized game setup
repeatable. `--screenshot FILE` saves the rendered frame. `--no-audio` disables
audio while preserving visual feedback. The REPL runner also accepts `:fixed-dt` (positive seconds, at most 0.05)
for a stable update interval when a reproducible simulation is needed.

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
                         :audio nil)
```

The bounded game suite is available through `make test-examples` or
`(asdf:test-system "pixelisp/examples")`. It checks native runner integration,
synthetic input, gameplay outcomes, and resource cleanup.
