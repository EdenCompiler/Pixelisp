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
| `Surface`, `surface`, `surflock` | `px.surface` | 8/12/15/16/24/32-bit surfaces, validated masks, editable indexed palettes, mapped writes, format conversion, owned/shared pixel storage with independent palette state, parent coordinates, pixel-format/blend queries, positioned rectangles, batch blits, RGB/RGBA blend effects, premultiplied alpha, RLE source hints, clipping, locks, typed views and bounded raw byte buffers |
| `display` | `px.display` | Default window/framebuffer, selected monitor and desktop sizing, closest-mode queries, visibility/minimized state, presentation, partial updates, resizing, fullscreen, captions/icons, driver/display/mode queries, iconify request, screensaver control |
| `draw`, `draw_py` | `px.draw` | Filled/outlined primitives, independent fitted rectangle corner radii, clipping, antialiased lines, damaged bounds |
| `gfxdraw` | `px.gfxdraw` | Surface-based primitives, antialiasing, textured polygons, Bézier curves |
| `image`, `imageext` | `px.image` | SDL_image loading from paths, encoded octets and binary streams with optional decoded format/palette preservation; PNG/JPEG/BMP/TGA saving to paths, streams and encoded vectors; raw and premultiplied pixel byte exports and shared 32-bit foreign imports |
| `transform` | `px.transform` | Native format/index-preserving flip, nearest scaling, rotation, scale2x and chop; 24/32-bit smooth scaling, RGBA32 rotozoom, color operations, thresholding, Laplacian edges |
| `event` | `px.event` | Native event copying including mouse device/window identity, touch origin and precise wheel deltas; include/exclude retrieval with optional pumping, filtering/queries/names, independent window mouse/keyboard grabs, Lisp payloads, custom types, thread-safe posting, polling/waiting |
| `key` | `px.key` | Scancode state, keyword names, modifiers, focus, text-input controls and configurable pump-delivered native key repeat |
| `mouse` | `px.mouse` | Position, relative movement, buttons, visibility, focus, relative mode |
| `cursors`, `Cursor` | `px.cursors` | System/color/bitmap cursors and ASCII bitmap compilation |
| `joystick` | `px.joystick` | Enumeration, hardware GUIDs, power-level reports, axes/buttons/hats/balls, lifetime, rumble |
| `_sdl2.controller` | `px.controller`, `px.sdl2.controller` | Gamepad mappings, index names, native event-state controls, normalized axes/buttons, hotplug events, rumble and touchpads |
| `_sdl2.touch` | `px.touch`, `px.sdl2.touch` | Device/finger enumeration and normalized touch events |
| `time` | `px.time` | Clocks, frame caps, elapsed/raw time, FPS, delay, pump-delivered timers |
| `math`, `Vector2`, `Vector3` | `px.math` | Vector arithmetic, indexed components and swizzles with validated writes, updates, length scaling, geometry, scalar/vector interpolation, decimal rounding, bounded movement, degree/radian rotations, scalar clamp and polar/spherical conversion |
| `mask`, `Mask` | `px.mask` | Bit masks, positioned rectangle anchors including empty masks, alpha/key/threshold construction, overlap, composition/convolution, components, outlines, colored/source-plane painting |
| `sprite` | `px.sprite` | CLOS sprites, source-image crops, single/ordered/RenderUpdates/layered/dirty groups, membership/update, old/new damage tracking and retry preservation, blend flags, positive/negative draw-order indexing, group clips/repaint invalidation and collision helpers |
| `font`, `sysfont` | `px.font`, `px.sysfont` | Fonts loaded from paths, encoded octets or binary streams with retained native storage; UTF-8 SDL_ttf text, metrics/styles, per-font ISO 15924 shaping script when SDL_ttf 2.20+ has HarfBuzz, fontconfig discovery, bundled fallback font |
| `freetype`, `_freetype` | `px.freetype` | Direct glyph rasterization, retained text, embedded-bitmap control, independent size axes, kerning, face/strike metrics, baseline placement, outline rotation, vertical layout, strong/oblique/wide/underline styles with per-call overrides, inverted coverage masks, raw rendering to integer arrays and live byte-plane views |
| `ftfont` | `px.ftfont` | SDL_ttf-shaped facade backed by optional direct FreeType module |
| `mixer`, `mixer_music`, `mixer.music` | `px.mixer`, `px.mixer.music` | Output-device selection and allowed-setting negotiation; sound/music decoding from paths, encoded memory and binary streams; channels, volume/panning, fades/queues, streamed music with retained native asset storage, playback controls and pump-delivered completion events |
| `midi`, `pypm` | `px.midi` | PortMidi device streams, timestamps, SysEx, filters, note helpers and event conversion |
| `sndarray` | `px.sndarray` | Integer PCM and float32 copied sample arrays/live views, sound creation from arrays |
| `surfarray` | `px.surfarray` | Packed/RGB/channel copies across native depths, packed views except 24-bit, full byte-channel views at 24/32-bit, array-to-surface operations |
| `pixelcopy` | `px.pixelcopy` | Copy into existing arrays and map pixel formats |
| `PixelArray`, `pixelarray` | `px.pixelarray` | Packed shared views, slices/transposes, weighted replace/extract/compare and format-aware surface copies; selection/comparison results are CL bit arrays |
| `BufferProxy`, `bufferproxy`, `newbuffer` | `px.buffer`, `px.bufferproxy` | Owner-backed views, bounds/lifetime checks, explicit release and slicing |
| `camera`, camera backends | `px.camera` | Linux V4L2 enumeration/capture, negotiated resolution, queried controls, RGB/HSV/YUV conversions |
| `scrap` | `px.scrap` | UTF-8 clipboard and primary selection; advertises text-only capabilities |
| `threads` | `px.threads` | Workers, multiple values, failure propagation, ordered bounded parallel map |
| `fastevent` | `px.fastevent` | Operational facade over the modern event queue |
| `_sdl2`, `_sdl2.sdl2`, `_sdl2.video` | `px.sdl2`, `px.sdl2.video` | Independent windows with identity, fullscreen/windowed requests, resize/border/opacity/grab/icon controls; renderer blitting, driver/capability queries, custom blend composition, state, targets/readback, texture updates, atlas Image regions with tint/alpha/pivots and ownership |
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
- Surface constructors retain Pixelisp's existing RGB byte order at 24/32-bit;
  custom masks select other SDL layouts. RGB565 and indexed RGB332 defaults
  match conventional SDL formats. Palettes are opaque RGB; use a color key
  for indexed transparency. Images normalize to RGBA32 unless
  `:preserve-format t` is requested. Packed `get-view` and PixelArray views
  support 24-bit values with three-byte strides, while surfarray `pixels2d`
  rejects that depth as pygame does. Copied 24-bit values use 32-bit arrays.
  Nonempty surfaces and the documented native depths are supported; other
  bit depths or mask layouts signal explicit errors.
- Drawing, antialiasing, alpha rounding, filtered transforms, and text layout
  can differ from pygame's exact pixels. The implementation favors readable
  CPU algorithms; there is no performance or bit-exact parity claim.
- Direct FreeType strong/oblique/wide styling requires outline fonts; bitmap
  fonts can still be rendered and underlined. Bitmap wide styling and pygame's
  layout cache are not implemented. Sizes use rounded pixels rather than
  points and configurable DPI; independent axes accept positive width and a
  nonnegative height, with zero height selecting equal ppem. Wide and underline
  styles cannot be rotated; vertical text cannot be underlined. Vertical
  placement uses FreeType metrics, with synthesized values when the font lacks
  them. Bounds include advance padding. Face metrics use native font units or
  explicit pixel queries; raw glyph metrics remain unstyled. Style
  rasterization and advance rounding can differ from pygame.
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
  Desktop sizing fills zero axes independently. `mode-ok` queries native
  display depths rather than changing the 32-bit software drawing format;
  as in pygame's SDL2 backend, non-fullscreen flags are ignored by this query.
- Sprite crop rectangles are copied rather than shared mutable properties and
  work in every group, extending pygame's DirtySprite crop support. RenderUpdates
  honors Pixelisp visibility and reports old hidden bounds; pygame's plain
  RenderUpdates draws its members without consulting DirtySprite visibility.
- Float32 sound arrays use `single-float` and report sample format 32, distinct
  from signed integer PCM32 (-32). Pygame 2.6.1 can report -32 for both formats.
  Out-of-range float values are retained, with -1 through 1 the conventional
  playback range; dtype conversions are explicit Lisp operations.
- SDL renderer target support depends on the active backend. `to-surface` is
  a slow readback from the current render target, limited to an in-bounds
  physical-pixel area; when a destination surface is supplied, its size must
  match the selected area and use unlocked 32-bit pixels. Partial `update-texture` areas are strict and do
  not clip. As in pygame 2.6.1's SDL upload path, the area selects the texture
  destination while source bytes begin at the source surface's top-left.
  SDL clips readback to the physical viewport; unread destination pixels are
  preserved. Custom blend factors/operations are composed by SDL; support is
  checked when assigning a mode to a renderer or texture. These renderer APIs
  require the video thread; textures remain tied to their creating renderer.
- Atlas `Image` wrappers retain textures without allocating or freeing native
  storage. Crops must be nonempty and contained in their parent region. Image
  drawing restores the texture's previous tint, alpha and blend settings;
  pygame leaves those settings on the shared texture after drawing.
- Renderer `blit` accepts textures/images, rectangle sequences and position
  pairs, with contained source-local areas. It returns a fresh requested Rect
  or the viewport for NIL/empty destinations. As in pygame's renderer method,
  special flags are ignored and the return value is not clipped damage.
- RLE is an SDL source-blit hint, distinct from the current encoded/locked
  state. It is limited to owned root surfaces with no live subsurfaces or pixel
  views. Disable it before creating a subsurface. SDL's RLE path can change
  alpha rounding and mixed color-key/per-pixel-alpha results, as it does in
  pygame; the API guide and differential fixtures cover this behavior.
- Clipboard transfer is text-only. Camera capture is V4L2/Linux. MIDI devices,
  camera controls, rumble, audio codecs, and other native capabilities depend
  on the installed backend and device, with explicit errors when unavailable.
- Image and sound decoding keep caller-owned Lisp streams open. Pygame's
  SDL_mixer wrapper can close a supplied sound stream after decoding; Pixelisp
  leaves that decision to the caller. Memory sound inputs use the explicit
  `:file` keyword to distinguish encoded assets from raw PCM `:buffer` data.
  Memory music inputs retain copied encoded bytes until replaced or unloaded;
  large Lisp streams are materialized before native playback. TGA output uses
  uncompressed raw BGR/BGRA pixels; pygame can use RLE and encode transparency
  differently. PNG/JPEG/BMP memory encoding uses the optional native bridge.
- Font byte inputs retain a private native copy and SDL stream until font
  disposal. Caller streams remain open and may be closed immediately after
  construction. Direct FreeType/ftfont constructors still accept paths only.
  Mixer change flags accept Lisp keyword lists or SDL bitmasks; `:device-name`
  corresponds to pygame's `devicename`. Wheel fields use hyphenated keywords,
  and window references are integer SDL IDs rather than pygame window objects.
- Python-only implementation modules are mapped to these Lisp capabilities;
  their internal import names are not duplicated as standalone packages.

## Verification boundary

The automated suite tests real native buffers with dummy audio/video, tiny
pixel fixtures, direct FreeType/TTF rendering, image round-trips, samples/music,
FreeType style/rotation overrides, vertical placement, bitmap-strike metadata
and unsupported-style checks, independent size axes and scoped metric/render
overrides, premultiplied image export, encoded sound decoding and stream
ownership, retained music buffers and queue cleanup, image encoding roundtrips
and stream positions, FreeType retained text/bitmap flags, no-pump event selection and exclusion ordering,
window/renderer ownership, renderer target restoration and readback, partial
and format-converting texture updates, texture origins/blend modes, atlas crops
and modifier isolation, custom blend encoding and accelerated blending pixels,
positioned masks, RLE pixel access and borrowing rules, virtual
joysticks, worker behavior and lifetimes.
Renderer blitting tests cover pixels, cropping, destination/viewport return
values and shared texture state; the mini-game renderer runner uses this API.
Xvfb exercises X11 presentation, clipboard text, independent window grabs,
window flags and fullscreen transitions. Display tests cover desktop-size
resolution, selected-monitor placement, native mode queries and visibility;
multi-monitor physical placement still depends on the connected SDL backend.
Sprite tests cover crop painting, old/new damage, clear/removal bookkeeping and
failed-blit retries. Float32 audio tests cover copies, live strides, PCM decode
conversion, dummy playback, invalid writes and repeated shutdown.
Memory-font tests cover rendering after source mutation/closure, stream offsets,
registration failure cleanup and repeated shutdown. Mixer-device tests cover
enumerated dummy outputs, strict/negotiated settings, defaults, buffer rounding,
invalid flags and failed-open recovery. Mouse-event tests populate native SDL
unions and queue events to check copied precision, direction, touch origin and
window IDs, plus the older-SDL precision fallback. Gameplay tests check wheel
input changes Crater Command's next shot and packed fonts back cached labels.
Native-format tests cover padded rows, palettes and duplicate keyed indices,
shared subsurface pixels with independent palettes, copies, conversions, decoded image
format preservation, strided live arrays and native-width transform pixels.
Echo Grove tests verify palette changes follow its remaining mistake lives.
An optional differential
script checks selected geometry/pixel/mask behavior against pygame 2.6.1.
The retained-text fixture compares immediate reuse. The local pygame build's
rotated-layout cache is unstable when a metrics query interrupts reuse;
Pixelisp tests that sequence independently without depending on the cache.

Physical camera capture, MIDI device I/O, audio recording, and rumble require
the opt-in checks and suitable hardware. Their adapters are implemented, but
passing device-independent tests does not verify those physical operations.
macOS, Windows, other Lisp implementations, and non-x86-64 native ABIs have not
been certified by this Linux/SBCL test run.
