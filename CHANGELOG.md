# Changes

## Unreleased

- Add native-order octet copies and writes for contiguous integer and floating
  buffer views. Partial element updates preserve untouched bytes; validation
  and overlap snapshots complete before mutation, while gapped and reversed
  views require an explicit array copy.
- Add `average-surfaces` with decoded palette-color averaging by default and
  optional raw-index averaging for all-indexed inputs, plus generic-only
  smoothscale backend queries/setters. Decoded palette means are mapped
  correctly through the destination palette; local pygame 2.6.1 indexed
  averaging is inconsistent, so only raw-index and truecolor paths are
  differential-checked.
- Add SDL2 modal-parent requests, input-only focus, and a writable relative
  mouse property. Relative mode follows SDL's global state; backend capability
  failures signal `px:unsupported-feature`.
- Give Echo Grove a fading melody cue using cached averaged-color afterglow
  frames in its indexed atlas.
- Add WeakSprite/WeakDirtySprite equivalents: groups retain sprites while
  reusable sprites hold weak reverse memberships. Echo Grove replaces its
  display group on restart without retaining retired scene groups.
- Discover normalized installed font families lazily through fontconfig, accept
  ordered string/list/vector fallback names and common aliases, and return NIL
  for unmatched names. SysFont variants synthesize only missing requested styles.
- Add FreeType padded text cells and copied foreground/background defaults,
  keeping baseline ink and raw masks stable. Explicit NIL backgrounds override
  saved colors; unsupported padded rotation fails before drawing.
- Add direct FreeType point sizes with configurable module/default and per-font
  DPI, read-only resolution queries, fractional sizes and DPI-aware bitmap
  strike selection, style strength and underline metrics. The default remains
  72 DPI; existing whole-number sizes retain their previous pixel scale.
- Accept native packed integer colors in surface fills/pixel writes and drawing
  primitives, retaining exact palette indices and unused storage bits on full
  samples. Echo Grove paints its warning cues by index, including duplicate-color
  themes. Antialiasing and blend effects decode channels when needed.
- Add live PixelArray row/column selections, metadata readers, line transposes,
  rank-preserving color operations and native-format line copies/broadcasts.
- Add independently owned joystick/controller bridges and editable mapping
  hashes, with stable-ID lookup, balanced subsystem cleanup and native input
  event spelling/remapping fixes. Prism Breaker supports gamepad movement,
  serving and hotplug replacement, and uses line views for paddle highlights.
- Load direct FreeType and ftfont fonts from encoded octets and binary streams;
  select collection faces and inspect their source path, index and face count.
  Retain native source storage through face disposal and failed setup cleanup.
- Add PixelArray color setters and bulk assignment from colors, Lisp arrays and
  packed views, with singleton broadcasting, overlap snapshots and native
  format remapping. Prism Breaker uses broadcast shading for its scoring rows.
- Add indexed and lower-depth surfaces, validated channel masks, editable
  palettes, mapped pixel writes and depth/template conversion. Subsurfaces
  share pixel indices with independent palettes; copies retain raw indices.
- Extend copied arrays, packed views and nearest transforms across native
  pixel widths; retain distinct keyed indices with duplicate palette colors.
  Add optional native-format image loading and RGBA32 filtered rotozoom output.
- Use an indexed Echo Grove atlas with palette-driven last-life highlights.
- Load SDL_ttf fonts from encoded octet vectors and caller-owned binary streams,
  retaining private native storage until font cleanup. Mini-game text caches
  now share encoded font assets.
- Select mixer output devices and allowed audio-setting changes, including
  pre-init defaults and pygame-compatible buffer rounding.
- Copy mouse device/window identity, touch origin, wheel direction and precise
  scrolling into events, with an older-SDL fallback. Crater Command uses
  fractional wheel input for power and horizontal aiming.
- Add copied sprite source rectangles and RenderUpdates groups with old/new
  painted damage, lost/hidden bounds, clear bookkeeping and failed-blit retry
  preservation. Echo Grove now samples pad frames from a shared sprite sheet.
- Add native-endian float32 mixer samples, specialized single-float copies and
  live sound views, raw PCM/decode support, and explicit float/integer format
  reporting. Retain float values outside the conventional playback range.
- Add selected-monitor display creation, desktop-sized zero axes, native
  `mode-ok` depth queries, and shown/minimized active-state reporting.
- Save encoded PNG/JPEG/BMP/TGA images to octet vectors and caller-owned binary
  streams. Native codecs use a growable C buffer without Lisp callbacks or
  temporary files; TGA uses a readable uncompressed Lisp writer. Unknown file
  extensions now select TGA, matching pygame's default.
- Load and queue streamed music from encoded memory and binary streams, with
  native backing storage retained through playback and released on replacement
  or unload. Queues wait for natural completion and are discarded on stop.
- Add FreeType previous-text reuse with NIL and embedded-bitmap strike control,
  preserving owned text copies and documenting the absence of a layout cache.
- Add independent FreeType horizontal/vertical pixel sizes with copied property
  values, per-call overrides, validated writes and bitmap-strike checks.
- Decode sound assets from encoded octet vectors and caller-owned binary
  streams, keeping raw PCM buffers distinct. Exercise memory decoding in
  Echo Grove's cached melody cues.
- Export RGBA/ARGB premultiplied pixel bytes with pygame rounding, native
  alpha-mask checks and unchanged source pixels. Extend native tests and pygame
  comparisons for the new media capabilities.
- Add FreeType outline rotation with normalized angles and per-call overrides,
  vertical glyph placement, and early validation of unsupported style/layout
  combinations. Keep rasterization, styling and layout in commented helpers.
- Add event retrieval exclusions and optional pumping for get/peek/clear,
  preserving queue order, limits and video-thread checks.
- Add renderer `blit` for textures and atlas images with destination/viewport
  return rectangles; use it in the mini-game renderer runner. Expand pixel,
  lifetime and pygame differential checks for these capabilities.
- Add direct FreeType strong, oblique, wide and underline styles, per-call
  overrides, strength/underline placement controls, face capability queries,
  bitmap-strike information and sized glyph height.
- Add SDL custom blend composition for renderer, texture and atlas-image
  drawing, plus renderer driver/capability information as ordinary plists.
- Add mask rectangle anchors, preserving empty dimensions and caller order.
  Extend pygame differential checks with mask placement, blend encoding,
  font metadata and numeric style flags.
- Add SDL renderer target scopes, viewport/logical scaling, readback, texture
  updates, blend controls, and rotation origins.
- Add texture atlas Image views with nested crops and independent drawing
  modifiers, plus independent-window identity, fullscreen, opacity, grab, icon,
  resize, border, focus and minimize/maximize/restore controls.
- Add surface RLE hints and lock queries, with explicit ownership and view rules.
- Add FreeType baseline placement, inverted coverage and raw array/view rendering.
- Add a selectable renderer backend and F11 fullscreen control to the four
  mini-games; use RLE for Orbit Patrol's cached frames.
- Expand differential fixtures against pygame 2.6.1 and register previously
  omitted PixelArray and rounded-rectangle tests with the main FiveAM suite.

- Add scoped Surface byte, packed-pixel, RGB, and channel views; bound cropped
  raw buffers by their owners' allocations. Add vector indexing and swizzling
  with validated `setf`, joystick GUID/power queries, and controller event-state
  and name queries. Exercise views and vectors in the mini games and add pygame
  differential fixtures for the new capabilities.
- Add display minimize requests and screensaver controls, per-font SDL_ttf
  script selection, negative sprite draw-order indices, and clipped dirty-group
  repaint requests.
- Rename the project to Pixelisp, including its ASDF systems and public package namespaces.
- Add scalar `px.math:lerp`, decimal-place `round-vector` with pygame-style
  halfway rounding, and validated multi-form `px.rect:update-rect` updates.
- Add display driver/count/mode/info queries that work without creating a
  window, plus encoded image loading from octet vectors and binary streams.
  Keep raw pixel imports on `from-bytes`/`from-string`.
- Release accepted native images and partial destinations when image
  normalization fails during allocation, conversion, or pixel copying.
- Add weighted PixelArray replacement/extraction/comparison, dependent transposed
  views, and format-aware copies that retain opaque/per-pixel-alpha capability.
- Add list/vector Surface batch blits, optional damage lists, scalar/pair layout
  anchors, channel shifts/losses, and native blend-mode queries.
- Add pump-delivered native keyboard repeat with configurable delay/interval,
  key-release/focus-loss cancellation, and independent event payload copies.
- Add saturated Color arithmetic, zero-safe channel division/remainders,
  inversion, and the settable normalized I1I2I3 color space.
- Add independent rectangle corner radii with proportional fitting and
  inward outline geometry.
- Add event-filter queries/names and independent mouse/keyboard window grabs;
  align queue filtering with all-type selection and removal of pending events.
- Add named/hexadecimal/canonical-integer Color construction, the 665-name
  palette, defensive dictionary copies, color updates, grayscale and premultiplication.
- Add scalar rectangle centers, centered scaling, in-place unions/clamping,
  and collision queries over objects and hash tables.
- Add vector updates, length scaling, radian rotations, in-place axis rotations,
  and scalar clamping.
- Add channel/music completion events captured and delivered on Lisp threads,
  including rapid stops, replacement, queue advancement, and channel resizing.
- Add GroupSingle-style groups, draw-order queries, and sprite blend flags
  with dirty-state updates when an effect changes.
- Add Laplacian edge detection with raw pixel output and input snapshots.
- Expand mask painting with destination offsets/clipping, source-plane
  fallbacks, skipped colors, format validation, and safe overlapping sources.
  The default unset color is now opaque black, matching pygame; use explicit
  transparent RGBA or NIL for transparency/preservation.
- Add surface parent/offset queries, native pixel layout inspection, and
  packed pixel mapping/reads.
- Replace the former example collection with four playable games: Prism
  Breaker, Orbit Patrol, Crater Command, and Echo Grove. Add a shared runner
  with bounded, seeded, fixed-step, screenshot, pause, restart, and synthetic
  input support.
- Add RGB/RGBA add, subtract, multiply, min/max surface effects, and
  premultiplied alpha conversion/compositing.
- Add rectangle anchors, aspect-preserving fitting, line clipping, and all-hit
  collision indices; support signed clip bounds and integer endpoint rounding.
- Add Vector2/Vector3 movement toward or away from a target, with in-place forms.
- Add settable HSV/HSL/CMY color properties and gamma correction, including
  validation before mutation and saturated extreme gamma values.
- Protect buffer shape/stride metadata from mutation, validate view construction
  before pinning owners, and check owner lifetime even for empty views.
- Make shared pixel writes and array copies independent of drawing clips.
  Report real channel offsets and negative strides for imported BGRA layouts;
  reject shared alpha access when an opaque surface has no alpha byte.
- Copy color-key values at API boundaries to keep Lisp and native transparency
  settings consistent when callers mutate their own colors.
- Guard mixer, music, and input operations around initialization/shutdown, and
  release partially allocated sound/font resources when construction fails.
- Copy and release SDL drop payloads, retain device-event fields, and normalize
  joystick/controller axis endpoints consistently with state polling.
- Fix mask principal-axis calculations around fractional centroids, and mask
  convolution destination/offset handling. Add a reference fixture to keep
  zero-radius circles empty, matching pygame.

## 0.1.0

- Initial SDL2-based Common Lisp game toolkit, graphics algorithms, native
  arrays/views, media/device adapters, examples, API guides, and test runners.
