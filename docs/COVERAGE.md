# Coverage and compatibility

Pixelisp uses pygame 2.6.1 as its reference catalog. Each active public module
has implemented capabilities below. This is not a claim that every pygame
function, Python object protocol, or numerical edge case is reproduced.
The exported Lisp symbols and module API guides describe the actual interface.

## Module map

| pygame module or class | Pixelisp equivalent | Implemented capability / adaptation |
| --- | --- | --- |
| `pygame`, `base` | `px` | Init/quit, scoped cleanup, conditions, constructors |
| `locals`, `constants` | `px.locals` | Common event/display keywords; key names are keywords rather than Python integer constants |
| `version` | `px.version` | Library/reference versions and linked SDL version |
| `Color`, `color`, `colordict` | `px.color`, `px.colordict`, `px:make-color` | RGBA/name/hex/integer parsing, 665 named colors, HSV/HSL/CMY/I1I2I3, saturated arithmetic/inversion, gamma, grayscale/premultiplication, updates and interpolation; palette copies are CL hash tables |
| `Rect`, `rect` | `px.rect`, `px:make-rect` | Integer geometry, validated updates, scalar/pair anchors, movement/scaling, aspect fitting, line clipping, in-place unions/clamping, object/hash-table collisions |
| `Surface`, `surface`, `surflock` | `px.surface` | Owned/shared native surfaces, parent coordinates, pixel-format/blend queries, positioned rectangles, batch blits, RGB/RGBA blend effects, premultiplied alpha, RLE source hints, clipping, locks, typed views and bounded raw byte buffers |
| `display` | `px.display` | Default window/framebuffer, presentation, partial updates, resizing, fullscreen, captions/icons, driver/display/mode queries, iconify request, screensaver control |
| `draw`, `draw_py` | `px.draw` | Filled/outlined primitives, independent fitted rectangle corner radii, clipping, antialiased lines, damaged bounds |
| `gfxdraw` | `px.gfxdraw` | Surface-based primitives, antialiasing, textured polygons, Bézier curves |
| `image`, `imageext` | `px.image` | SDL_image loading from paths, encoded octets and binary streams, PNG/JPEG/BMP saving, raw pixel byte conversions and shared 32-bit foreign imports |
| `transform` | `px.transform` | Flip, scaling, smooth scaling, rotation/rotozoom, scale2x, chop, color operations, thresholding, Laplacian edges |
| `event` | `px.event` | Native event copying, filtering/queries/names, independent window mouse/keyboard grabs, Lisp payloads, custom types, thread-safe posting, polling/waiting |
| `key` | `px.key` | Scancode state, keyword names, modifiers, focus, text-input controls and configurable pump-delivered native key repeat |
| `mouse` | `px.mouse` | Position, relative movement, buttons, visibility, focus, relative mode |
| `cursors`, `Cursor` | `px.cursors` | System/color/bitmap cursors and ASCII bitmap compilation |
| `joystick` | `px.joystick` | Enumeration, hardware GUIDs, power-level reports, axes/buttons/hats/balls, lifetime, rumble |
| `_sdl2.controller` | `px.controller`, `px.sdl2.controller` | Gamepad mappings, index names, native event-state controls, normalized axes/buttons, hotplug events, rumble and touchpads |
| `_sdl2.touch` | `px.touch`, `px.sdl2.touch` | Device/finger enumeration and normalized touch events |
| `time` | `px.time` | Clocks, frame caps, elapsed/raw time, FPS, delay, pump-delivered timers |
| `math`, `Vector2`, `Vector3` | `px.math` | Vector arithmetic, indexed components and swizzles with validated writes, updates, length scaling, geometry, scalar/vector interpolation, decimal rounding, bounded movement, degree/radian rotations, scalar clamp and polar/spherical conversion |
| `mask`, `Mask` | `px.mask` | Bit masks, alpha/key/threshold construction, overlap, composition/convolution, components, outlines, colored/source-plane painting |
| `sprite` | `px.sprite` | CLOS sprites, single/ordered/layered/dirty groups, membership/update, blend flags, positive/negative draw-order indexing, group clips/repaint invalidation and collision helpers |
| `font`, `sysfont` | `px.font`, `px.sysfont` | UTF-8 SDL_ttf text, metrics/styles, per-font ISO 15924 shaping script when SDL_ttf 2.20+ has HarfBuzz, fontconfig discovery, bundled fallback font |
| `freetype`, `_freetype` | `px.freetype` | Direct glyph rasterization, kerning, metrics, baseline placement, inverted coverage masks, raw rendering to integer arrays and live byte-plane views |
| `ftfont` | `px.ftfont` | SDL_ttf-shaped facade backed by optional direct FreeType module |
| `mixer`, `mixer_music`, `mixer.music` | `px.mixer`, `px.mixer.music` | Sounds, channels, volume/panning, fades/queues, streamed music, playback controls and pump-delivered completion events |
| `midi`, `pypm` | `px.midi` | PortMidi device streams, timestamps, SysEx, filters, note helpers and event conversion |
| `sndarray` | `px.sndarray` | Copied sample arrays and live views, sound creation from arrays |
| `surfarray` | `px.surfarray` | Packed/RGB/channel copies and views, array-to-surface operations |
| `pixelcopy` | `px.pixelcopy` | Copy into existing arrays and map pixel formats |
| `PixelArray`, `pixelarray` | `px.pixelarray` | Packed shared views, slices/transposes, weighted replace/extract/compare and format-aware surface copies; selection/comparison results are CL bit arrays |
| `BufferProxy`, `bufferproxy`, `newbuffer` | `px.buffer`, `px.bufferproxy` | Owner-backed views, bounds/lifetime checks, explicit release and slicing |
| `camera`, camera backends | `px.camera` | Linux V4L2 enumeration/capture, negotiated resolution, queried controls, RGB/HSV/YUV conversions |
| `scrap` | `px.scrap` | UTF-8 clipboard and primary selection; advertises text-only capabilities |
| `threads` | `px.threads` | Workers, multiple values, failure propagation, ordered bounded parallel map |
| `fastevent` | `px.fastevent` | Operational facade over the modern event queue |
| `_sdl2`, `_sdl2.sdl2`, `_sdl2.video` | `px.sdl2`, `px.sdl2.video` | Independent windows with identity, fullscreen/windowed requests, resize/border/opacity/grab/icon controls; renderer state, targets/readback, texture updates, atlas Image regions with tint/alpha/pivots and ownership |
| `_sdl2.audio` | `px.sdl2.audio` | Raw queued PCM playback/capture devices, enumeration and ownership |
| `_sdl2.mixer` | `px.sdl2.mixer` | Post-mix observation via a bounded native PCM ring, drained on the Lisp thread |
| `examples` | `px.examples`, `pixelisp/examples` | Four playable games—Prism Breaker, Orbit Patrol, Crater Command, and Echo Grove—with a shared 900×620 runner, deterministic bounded runs, synthetic input, gameplay snapshots, and generated audio |
| `tests` | `pixelisp/tests` | FiveAM runner and opt-in device integration tests |
| `cdrom`, `Overlay` | `px.cdrom`, `px:make-overlay` | Retired with SDL2; explicit unavailable results/conditions |
| `rwobject`, `pkgdata`, packaging helpers | ASDF, pathnames, native adapters | Lisp-native resource paths/builds; no Python import, pickle or PyInstaller protocols |

## Deliberate differences

- Public spelling uses hyphens. Native object methods take the receiver as
  the first argument, and properties support `setf` where provided.
- Tuples become Lisp sequences or value objects. Pixel arrays use X/Y/channel
  axes, and sound arrays use frames/channels. Live foreign views are explicit
  objects, not NumPy arrays or implementation-specific foreign CL arrays.
  Native surface views lock immediately. Raw byte buffers for cropped
  subsurfaces are bounded by the root allocation, which can shorten final-row
  padding compared with pygame. Raw array writes ignore drawing clips,
  shared alpha views require a real
  alpha channel, and byte offsets/strides reflect imported channel layouts.
  PixelArray comparisons decode colors across different native layouts; copied
  selection/comparison masks use bits rather than new PixelArray wrappers.
- Drawing, antialiasing, alpha rounding, filtered transforms, and text layout
  can differ from pygame's exact pixels. The implementation favors readable
  CPU algorithms; there is no performance or bit-exact parity claim.
- Dirty-group redraws restore saved backgrounds and redraw every visible member
  in draw order to preserve overlap. They can report broader damage than
  pygame's optimized dirty rectangles; returned damage is clipped to the
  effective target and group clip.
- Laplacian edges use deterministic opaque white padding and snapshotted
  inputs. The local pygame 2.6.1 build produced varying corner pixels, so its
  differential fixture compares interior responses; Lisp tests verify the
  defined padding and alias behavior separately.
- `tick-busy-loop` cooperatively sleeps. Timers coalesce missed intervals.
  Sound/music queues advance when events are pumped or `px.mixer:update` runs.
  Native key repeat also coalesces overdue intervals to one event per pump;
  synthetic Lisp-posted key events never start a held-key repeat schedule.
- The default display has a logical software resolution and scales it when
  the native window is resized. Explicit SDL renderer windows use a separate
  API and cannot be mixed with that software window's native surface.
  Display information is returned as ordinary plists; mode enumeration returns
  size pairs or NIL, without pygame's unrestricted-mode integer sentinel.
- SDL renderer target support depends on the active backend. `to-surface` is
  a slow readback from the current render target, limited to an in-bounds
  physical-pixel area; when a destination surface is supplied, its size must
  match the selected area and use unlocked 32-bit pixels. Partial `update-texture` areas are strict and do
  not clip. As in pygame 2.6.1's SDL upload path, the area selects the texture
  destination while source bytes begin at the source surface's top-left.
  SDL clips readback to the physical viewport; unread destination pixels are
  preserved. These renderer APIs require the video thread and textures remain tied to
  their creating renderer.
- Atlas `Image` wrappers retain textures without allocating or freeing native
  storage. Crops must be nonempty and contained in their parent region. Image
  drawing restores the texture's previous tint, alpha and blend settings;
  pygame leaves those settings on the shared texture after drawing.
- RLE is an SDL source-blit hint, distinct from the current encoded/locked
  state. It is limited to owned root surfaces with no live subsurfaces or pixel
  views. Disable it before creating a subsurface. SDL's RLE path can change
  alpha rounding and mixed color-key/per-pixel-alpha results, as it does in
  pygame; the API guide and differential fixtures cover this behavior.
- Clipboard transfer is text-only. Camera capture is V4L2/Linux. MIDI devices,
  camera controls, rumble, audio codecs, and other native capabilities depend
  on the installed backend and device, with explicit errors when unavailable.
- Python-only implementation modules are mapped to these Lisp capabilities;
  their internal import names are not duplicated as standalone packages.

## Verification boundary

The automated suite tests real native buffers with dummy audio/video, tiny
pixel fixtures, direct FreeType/TTF rendering, image round-trips, samples/music,
window/renderer ownership, renderer target restoration and readback, partial
and format-converting texture updates, texture origins/blend modes, atlas crops
and modifier isolation, RLE pixel access and borrowing rules, virtual
joysticks, worker behavior and lifetimes.
Xvfb exercises X11 presentation, clipboard text, independent window grabs,
window flags and fullscreen transitions.
An optional differential
script checks selected geometry/pixel/mask behavior against pygame 2.6.1.

Physical camera capture, MIDI device I/O, audio recording, and rumble require
the opt-in checks and suitable hardware. Their adapters are implemented, but
passing device-independent tests does not verify those physical operations.
macOS, Windows, other Lisp implementations, and non-x86-64 native ABIs have not
been certified by this Linux/SBCL test run.
