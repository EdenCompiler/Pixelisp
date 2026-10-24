# Working on Pixelisp

Start by running `make test`, then run `make demo` and read
`examples/examples.lisp`. The example follows the same explicit loop as pygame:
process events, update game state, draw, and present.

## Code map

| Area | Start here | Responsibility |
| --- | --- | --- |
| Systems and public foundations | `pixelisp.asd`, `src/packages.lisp` | Load order, optional dependencies, shared exports |
| Portable values | `src/core.lisp`, `src/colors.lisp`, `src/math.lisp` | Conditions, resource protocol, colors/conversions, rectangles, vectors |
| Collection geometry | `src/rect-tools.lisp` | In-place geometry, scaling, and collision queries over Lisp collections |
| Named colors | `src/color-names.lisp` | Bundled color-name facts and defensive palette copies |
| Pixel ownership | `src/surface.lisp`, `src/buffer.lisp` | SDL surfaces, borrowed parents, locks, disposal, scoped views |
| Default window and loop | `src/runtime.lisp` | Initialization, display, event decoding, keyboard/mouse, clocks/timers |
| Pure image algorithms | `src/graphics.lisp` | Rasterization, transforms, bit masks |
| Mask painting | `src/mask-surface.lisp` | Destination clips, optional color planes, alias-safe snapshots |
| Game objects | `src/sprite.lisp` | CLOS sprites, groups, layers, collisions |
| Array interfaces | `src/arrays.lisp`, `src/sndarray.lisp` | Copying versus sharing pixel/sample data |
| Media adapters | `src/media.lisp`, `src/freetype.lisp` | Image codecs, fonts, sound chunks/channels, streamed music |
| Native devices | `src/devices.lisp`, `src/midi.lisp`, `src/camera.lisp` | Input, clipboard, PortMidi, V4L2 |
| Explicit SDL APIs | `src/sdl2-ext.lisp`, `native/pixelisp-native.c` | Renderer ownership trees, queued audio, capture bridge |
| Worker helpers | `src/threads.lisp` | Ordered parallel mapping and exception propagation |
| Runnable examples | `examples/*-lab.lisp`, `examples/catalog.lisp` | Small interactive loops and a shared CLI/REPL registry |

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

`make test-examples` runs the examples' separate ASDF/FiveAM suite with bounded
frames. It posts synthetic mouse clicks and mode-switch keys through the event
queue, and checks cleanup after both successful runs and callback failures.
Add new examples to `examples/catalog.lisp` and `docs/EXAMPLES.md`; cache static
art and share immutable images instead of allocating them on every frame or
for every particle. Keep helper names prefixed with the example's name, since
all examples share the `px.examples` package.

The UI lab combines independent corner radii and Color arithmetic with queue
filters and native grabs. Keep static art cached, use `with-init` to clear
queue state on exit, and let window destruction release native grabs. Filter
changes and worker posting use the same queue lock; avoid recursively calling
a public locking function while already holding that lock.

The pixel lab demonstrates packed views, weighted selection and transposition.
Close dependent views before their parents, then draw only after surface locks
are released. PixelArray color operations must decode the owner's native
format, including for sliced views; compare layouts with different channel
orders in tests. Keyboard-repeat tests drive the production SDL pump as well
as deterministic timer boundaries, without physical input or long sleeps.

The system recipes decode an embedded PNG and inspect video capabilities.
Encoded image data belongs in `load`/`load-bytes`; raw pixel bytes belong in
`from-bytes`. Native decoders retain the RW stream and backing memory until
decoding finishes. Once `wrap-surface` accepts an owned native image, it must
release that allocation even if normalization fails. Keep regression tests for
allocation, conversion and copy failures alongside normal image round-trips.

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
