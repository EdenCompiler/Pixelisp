# Working on Pixelisp

Start by running `make test`, then run `make demo` and read
`examples/common.lisp` and `examples/prism-breaker.lisp`. The shared game runner
follows the familiar event, update, draw, and present loop.

## Code map

| Area | Start here | Responsibility |
| --- | --- | --- |
| Systems and public foundations | `pixelisp.asd`, `src/packages.lisp` | Load order, optional dependencies, shared exports |
| Portable values | `src/core.lisp`, `src/colors.lisp`, `src/math.lisp`, `src/vector-access.lisp` | Conditions, resource protocol, colors/conversions, rectangles, vectors |
| Collection geometry | `src/rect-tools.lisp` | In-place geometry, scaling, and collision queries over Lisp collections |
| Named colors | `src/color-names.lisp` | Bundled color-name facts and defensive palette copies |
| Pixel ownership | `src/surface.lisp`, `src/surface-views.lisp`, `src/buffer.lisp` | SDL surfaces, borrowed parents, locks, disposal, scoped views |
| Default window and loop | `src/runtime.lisp` | Initialization, display, event decoding, keyboard/mouse, clocks/timers |
| Pure image algorithms | `src/graphics.lisp` | Rasterization, transforms, bit masks |
| Mask painting | `src/mask-surface.lisp` | Destination clips, optional color planes, alias-safe snapshots |
| Game objects | `src/sprite.lisp` | CLOS sprites, groups, layers, collisions |
| Array interfaces | `src/arrays.lisp`, `src/sndarray.lisp` | Copying versus sharing pixel/sample data |
| Media adapters | `src/media.lisp`, `src/freetype.lisp` | Image codecs, fonts, sound chunks/channels, streamed music |
| Native devices | `src/devices.lisp`, `src/device-info.lisp`, `src/midi.lisp`, `src/camera.lisp` | Input, clipboard, PortMidi, V4L2 |
| Explicit SDL APIs | `src/sdl2-ext.lisp`, `native/pixelisp-native.c` | Renderer ownership trees, queued audio, capture bridge |
| Worker helpers | `src/threads.lisp` | Ordered parallel mapping and exception propagation |
| Runnable games | `examples/common.lisp`, `examples/*-*.lisp`, `examples/catalog.lisp` | Shared runner, four mini-games, and CLI/REPL registry |

The native-independent `pixelisp/core` system must stay loadable without SDL.
Sprite drawing resolves the surface API when called, so geometry and group
bookkeeping can still be used in tools without a graphics backend.

## How a resource works

Native wrappers inherit `pixelisp.internal:resource`. Construction checks the
native result and calls `register-resource`. The wrapper retains any parent
that owns its memory. `ensure-live` checks disposal before every native access;
derived resources also check their parent chain.

Specialize the primary `dispose` method to release your native allocation.
The shared around method makes disposal idempotent, and the after method marks
the object disposed and removes it from the cleanup registry. Do not free the
same allocation from a GC finalizer and `dispose`: cancel a dependency's
finalizer when transferring ownership.

Window surfaces belong to SDL windows and must never be freed by Pixelisp.
Offscreen surfaces own their pixels; subsurfaces own only their SDL metadata.
Locks on a subsurface pin all ancestors. A live buffer view owns one release
action, and slices prevent premature release of their parent view.

`with-init` cleans registered resources in reverse construction order before
calling subsystem shutdown hooks. A worker must not destroy a window or pump
SDL events; keep video operations on the initializing thread.

## Adding a feature

1. Find the module in `docs/COVERAGE.md` and choose its public Lisp spelling.
2. Keep raw pointers, native error strings, and C layout details in the adapter.
   Return ordinary Lisp values or owned wrappers from the public API.
3. Add a docstring explaining arguments, return values, mutation, ownership,
   and any failure a caller needs to handle. Comment the reason behind native
   lifetime or algorithm choices; avoid comments that merely repeat the code.
4. Add a small deterministic fixture. Test behavior at boundaries, not a copy
   of the implementation. Use explicit tiny pixel matrices for graphics.
5. Add or update a module example and the coverage entry. Run the affected
   tests, followed by the full suite when interfaces or lifecycle code changed.

Use descriptive local names and small helper functions. Prefer a straightforward
algorithm over clever macro expansion. Macros are most useful here for scoped
cleanup or a repeated native layout pattern.

## Test layers

`make test` uses real SDL allocations with dummy drivers. It covers surfaces,
views, graphics, fonts, audio samples, groups, events, renderer ownership, virtual
joysticks, and device-independent MIDI/camera utilities. `make test-x11` adds a
real X11 backend inside Xvfb, including a clipboard round-trip and independently
acquired/released mouse and keyboard grabs on a focused window.

`make test-examples` runs bounded game sessions with synthetic input and checks
cleanup after both successful runs and callback failures. Add a game to
`examples/catalog.lisp` and `docs/EXAMPLES.md`; use a focused factory that
returns the shared mini-game callbacks and pure state helpers for game rules.
Keep helper names prefixed with the game's name, since all games share the
`px.examples` package.

Allocate native surfaces, fonts, and generated tones during game construction
and reuse them during play. Keep update state independent of SDL where
practical, use the shared deterministic random helper, and test meaningful
transitions such as scoring, damage, victory, loss, and reset. Use rectangular
or mask collisions that match the game's mechanics; keep rendering work bounded
and draw through cached native assets.

The four games exercise distinct parts of the library: Prism Breaker uses
rectangle collisions, vector reflection, surface blits, and generated tones;
Orbit Patrol uses turning and thrust, rotated masks, projectiles, and
invulnerability; Crater Command changes both landscape pixels and collision
masks after ballistic impacts; Echo Grove combines sequence state, event
input, ordered pad sprites, and optional audio. The shared runner owns initialization,
input tracking, pause/restart handling, presentation, and resource cleanup.

Mixer completion records are produced and drained by Lisp-side playback/update
operations. Keep native callbacks free of arbitrary Lisp execution. Test rapid
replacement, explicit stops, queued tracks, and configuration changes before a
pump; each completed playback must retain its own captured event configuration.

Hardware tests are opt-in. The variables and bounded operations are documented
in `docs/API-devices.md`; ordinary tests never capture camera frames, record
audio, or send MIDI to a real device. A skipped physical-device check must be
reported as skipped rather than counted as verified support.

For a single FiveAM test from a REPL:

```lisp
(ql:quickload "pixelisp/tests")
(fiveam:run! 'pixelisp.tests::nested-subsurfaces-share-and-check-parents)
```

Keep camera/post-mix native build output in ASDF's cache. Do not check `.so`,
`.o`, or `.fasl` files into the project. Native bridge changes can also be
checked with `cc -Wall -Wextra -Werror` using the same pkg-config flags as the
lazy builder in `src/sdl2-ext.lisp`.
