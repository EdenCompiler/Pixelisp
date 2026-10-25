# Changes

## Unreleased

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
