# Core, surfaces, and the game loop

Every package has both `pixelisp.<module>` and `px.<module>` names. Functions
accept ordinary lists/vectors at coordinate and color boundaries. Objects are
explicit receiver arguments, for example `(px.surface:fill screen '(0 0 0))`.

## Values and conditions

`px:make-color` takes R, G, B and optional A octets, or one Color, RGB(A)
list/vector, named color, hexadecimal string, or canonical integer. Color accessors are
`px:color-r/g/b/a` or `px.color:r/g/b/a`, all with `setf`. `px.color:lerp`,
`normalize`, and `to-list` provide conversion and interpolation.

`px.color:parse` always returns a fresh Color. Named strings are insensitive to
case and spaces, using the bundled 665-name pygame 2.6.1/X11 palette. Hexadecimal
forms are `"#rrggbb"`, `"#rrggbbaa"`, `"0xrrggbb"`, and `"0xrrggbbaa"`.
`px.colordict:color-names` lists the names; `lookup` returns an RGBA list or NIL;
`the-colors` returns an independent hash table of names to RGBA lists. Mutating
these returned values does not change the built-in palette. No Python or
system color database is needed at runtime.

```lisp
(px:make-color "Dark Slate Gray")
(px:make-color "#4080c080")
(px.surface:fill screen "midnightblue") ; Color names also work in drawing APIs.
```

`px.color:to-integer` returns `#xRRGGBBAA`; the single-integer constructor uses
that same format, including alpha. This is distinct from the native packed
pixel integers returned by `px.surface:map-rgb`. Surface color arguments accept
names and hex strings; turn a canonical integer into a Color explicitly.

`update-color` mutates a Color after validating all inputs. Three separate
numeric channels retain its alpha; a single parsed value replaces RGBA,
including alpha's default of 255. `grayscale` returns a luminance-weighted
Color with unchanged alpha, and `premul-alpha` returns RGB multiplied by alpha.
Both return independent values.

Color arithmetic uses named functions: `add`, `subtract`, `multiply`,
`floor-divide`, `modulo`, and `invert`. Each operates independently on **all four
RGBA channels** and returns a fresh Color. Addition/multiplication saturate at
255, subtraction at 0; division and modulo produce 0 when the corresponding
divisor channel is zero. Multiplication is a direct integer product, without
normalizing by 255. These functions accept the same inputs as `parse`.

```lisp
(px.color:add "steelblue" '(30 30 30 0)) ; Brighten RGB while retaining alpha.
(px.color:multiply '(100 30 50 255) '(2 1 1 1)) ; => Color(200 30 50 255)
```

`px.color:hsva` and `hsla` return hue in degrees (0–360), followed by
saturation, value/lightness, and alpha in percentages (0–100). Their `setf`
forms accept three or four values; omitted alpha retains the current value.
`cmy` uses three normalized values (0–1) and also supports `setf`.
`i1i2i3` exposes average intensity plus two chroma components; its ranges are
0–1 for I1 and -0.5–0.5 for I2/I3. Its `setf` form accepts a three-value
list/vector, preserves alpha, and clips the reconstructed RGB channels to
octets. Setting I2 and I3 to zero produces a neutral color at the same average
intensity. Validation finishes before any channel changes.
`correct-gamma` returns a new Color with all four channels gamma corrected.
Color-space setters truncate to octets; gamma correction rounds to the nearest
octet. Invalid property inputs leave the color unchanged.

```lisp
(let ((color (px:make-color 0 0 0 180)))
  (setf (px.color:hsva color) #(210 80 95)) ; Preserve alpha 180.
  (px.color:to-list (px.color:correct-gamma color 0.8)))
```

`px:make-rect` takes x, y, width, height. Rectangles have integer coordinates,
exclusive right/bottom edges, `setf` position/size/center properties, and
`px.rect` functions for movement, inflation, clipping, union, clamping,
normalization, containment, and point/rectangle/list collisions. Edge contact
does not count as overlap.

Anchor pairs `top-left`, `top-right`, `bottom-left`, `bottom-right`, `mid-top`,
`mid-left`, `mid-bottom`, and `mid-right` support `setf` without changing size.
`fit` returns a new rectangle scaled proportionally and centered within another
rectangle, rounding to integer dimensions. A source with both dimensions zero
returns a centered empty rectangle. `collide-list-all` returns all overlapping
indices, in input order. `clipline` returns two integer endpoint lists, or NIL
when no segment lies inside; it accepts four coordinates, two endpoint pairs,
or two separate endpoints. It truncates endpoints before clipping, treats
right/bottom as exclusive, and normalizes a copy of negative-sized bounds.

`center-x` and `center-y` expose settable scalar centers. `clamp-ip`, `union-ip`,
and `union-all-ip` mutate the receiver and return it. `scale-by` returns a new
rectangle, and `scale-by-ip` mutates; pass one uniform factor, two scalar
factors, or a two-value list/vector. Factors use their absolute magnitudes.
As in pygame, an explicit zero Y factor uses the X factor, and integer center
rounding can move odd-sized rectangles by a pixel even at a factor of 1.

`collide-objects` returns the first matching object from a list/vector, and
`collide-objects-all` returns every match in sequence order. Their `:key`
function extracts the rectangle. `collide-dict` and `collide-dict-all` accept
CL hash tables and return fresh `(key . value)` entries. By default keys are
rectangles; `:use-values t` selects values instead. Hash traversal order is
implementation-defined, so sort results when an application requires order.

```lisp
(px.rect:collide-objects cursor-rect actors :key #'px.sprite:rect)
(px.rect:scale-by panel-rect #(1.5 1.2))
```

`px.rect:update-rect` replaces all four rectangle values. Pass four coordinates,
one Rect or four-value sequence, or two `(x y)` pairs. Values are validated
before any field changes and then truncated to integers, like `make-rect`.

```lisp
(let ((bounds (px:make-rect 10 10 100 60)))
  (px.rect:clipline bounds '(-20 30) '(200 30))) ; => ((10 30) (109 30))
```

Library conditions inherit `px:error` and carry `px:operation` and `px:message`.
Specific types are `initialization-error`, `dependency-error`,
`unsupported-feature`, `disposed-resource`, and `resource-in-use`.

## Initialization and resources

`(px:init :video t :audio nil)` initializes timers/events and the requested SDL
subsystems. Fonts and the mixer initialize lazily when first used. Loading an
ASDF system does not open devices. `(px:quit)` disposes registered resources,
shuts subsystems down, and can be called again.

```lisp
(px:with-init ()
  (px:with-resource (image (px.image:load #p"sprite.png"))
    ;; IMAGE is disposed on normal return or a condition.
    (px.surface:get-size image)))
```

Repeated `dispose` is harmless. Accessing a disposed native resource signals
`disposed-resource`; disposing a surface with active pixel locks signals
`resource-in-use`.

## Surfaces

`px.surface:make-surface` takes a size and `:alpha` flag. A surface without
per-pixel alpha is opaque; `:alpha t` starts with transparent pixels. Operations:

- `get-at`, `set-at`, `fill`, `blit`, `blits` read or write pixels. `fill` and
  `blit` return the affected rectangle. `blit` takes `:area` for a source region.
- `get-clip`/`set-clip` control destination clipping. `set-at` silently ignores
  out-of-clip positions; `get-at` checks bounds.
- `get-alpha`/`set-alpha` control whole-surface modulation;
  `get-colorkey`/`set-colorkey` control the transparent color. Color keys are
  copied on input and output, so mutating a channel list or returned Color
  cannot disagree with SDL's stored transparency key.
- `copy`, `convert`, and `convert-alpha` make independent pixel allocations.
  A raw copy preserves pixel values, including RGB values underneath zero alpha.
- `subsurface` shares a contained rectangular region; `scroll` shifts pixels
  inside the clip; `get-bounding-rect` finds non-keyed pixels above an alpha threshold.
- `size`, `width`, `height`, `get-rect`, and their `get-*` aliases inspect size.

`set-alpha` and `set-colorkey` accept an optional `:rle` boolean. When supplied,
it enables or disables SDL's run-length encoding (RLE) blit hint; when omitted,
the current hint is retained. `set-rle` changes the same hint directly and
returns the requested boolean. `rle-enabled-p` reports that requested hint,
including while SDL temporarily decodes pixels for access. `must-lock-p` reports
SDL's current `SDL_MUSTLOCK` state. `get-locked` reports whether any Pixelisp
locks are active, including locks held by open pixel views; this is distinct from whether
SDL currently requires a lock before direct pixel access.

RLE can be enabled only on an independently owned root surface with no active
pixel locks/views or live child subsurfaces. Disable RLE before creating a
subsurface. Changing the hint while a pixel lock or view is active signals
`resource-in-use`. `copy` retains the requested RLE hint. SDL documents RLE as
a source-blit optimization that can require locking for pixel access; pygame
2.6.1 exposes the corresponding `RLEACCEL` flag on `Surface.set_alpha` and
`Surface.set_colorkey` ([SDL_SetSurfaceRLE](https://wiki.libsdl.org/SDL2/SDL_SetSurfaceRLE),
[SDL_MUSTLOCK](https://wiki.libsdl.org/SDL2/SDL_MUSTLOCK),
[pygame Surface reference](https://www.pygame.org/docs/ref/surface.html)).

The native RLE transparency path can change results when a source combines a
color key with per-pixel alpha. In a pygame 2.6.1 probe, an alpha surface with
pixels `(10 20 30 255)` and `(90 80 70 128)`, keyed on `(10 20 30)`, blitted to
a transparent alpha surface produced `(10 20 30 255)` and `(45 40 35 255)` with
RLE enabled; with RLE disabled it produced `(0 0 0 0)` and `(45 40 35 128)`.
Use either color-key transparency or per-pixel alpha when those pixels must
retain their usual transparency through blits.

`get-rect` accepts pair anchors such as `:top-right`, `:bottom-left`, `:mid-top`,
and `:center`, plus scalar position anchors `:x`, `:y`, `:left`, `:top`,
`:right`, `:bottom`, `:center-x`, and `:center-y`. Compact pygame spellings
(`:topright`, `:centerx`, etc.) also work. Anchors apply in caller order and
coordinates truncate to integers, following the existing Lisp Rect convention.

`blits` accepts list/vector batches whose entries are either
`(source destination &key :area :special-flags)` or positional
`(source destination [area [special-flags]])`; entries may also be vectors.
It returns damage rectangles in order. Pass `:return-rects nil` to render
without collecting a result list. A malformed entry signals after earlier
entries have drawn, so batch rendering preserves sequential behavior.

```lisp
(px.surface:blits screen
  (vector (vector image (px.surface:get-rect image :mid-top '(320 20)))
          (list glow '(280 140) nil :blend-rgb-add))
  :return-rects nil)
```

`fill` and `blit` accept `:special-flags` for effects. Supported keywords are
`:blend-rgb-add`, `:blend-rgb-sub`, `:blend-rgb-mult`, `:blend-rgb-min`, and
`:blend-rgb-max`, plus corresponding `:blend-rgba-*` modes. RGB modes retain
destination alpha; RGBA modes also combine alpha when present. The shorter
`:blend-add/sub/mult/min/max` names are RGB aliases. Channel effects use stored
channels, ignoring the source's color key and blanket alpha. An opaque blit
source has no alpha channel to combine. Addition/subtraction saturate at
0–255, and multiplication preserves white as an identity.

```lisp
;; FILL keeps its optional rectangle before keyword arguments; NIL uses the clip.
(px.surface:fill image '(255 120 100) nil :special-flags :blend-rgb-mult)
(px.surface:blit screen glow '(100 80) :special-flags :blend-rgb-add)
```

`premul-alpha` returns a new surface with RGB multiplied by per-pixel alpha;
blit that result with `:special-flags :blend-premultiplied`. Its whole-surface
alpha setting is retained, while the old color key is cleared for alpha
surfaces. Premultiplied compositing uses pixel alpha and ignores blanket alpha.
Opaque sources use ordinary blitting for this mode. Premultiplied fill is
unsupported. `:blend-alpha-sdl2` selects the ordinary native blitter, already
the library's default. Unknown flags signal `unsupported-feature` before
changing pixels. Effects honor clips and snapshot blit sources before writes,
so overlapping images and subsurfaces work safely. They use readable CPU
loops and allocate a source snapshot; large per-frame effects can be costly.

A subsurface retains its parent. Closing a parent invalidates the child even
if the child object remains referenced. Pixel locks on children also pin their
ancestors. Blitting locked surfaces signals `resource-in-use`.

`get-parent` returns the immediate parent surface or NIL, and `get-abs-parent`
returns the top-level surface (the receiver itself for independent images).
`get-offset` and `get-abs-offset` return fresh coordinate lists relative to
those parents. Offsets remain local to the shared pixels even if the parent
clip changes. A non-surface owner retained by a foreign import is private
storage ownership and is not returned as a geometric parent.

`get-pitch` reports bytes between rows; subsurfaces inherit the parent's pitch.
`get-bitsize`, `get-bytesize`, and `get-masks` inspect the actual pixel layout.
Current formats use 32 bits/four bytes, with different RGBA channel masks for
different byte orders. `map-rgb` packs an RGB(A) color for that specific surface;
`unmap-rgb` returns a fresh Color. `get-at-mapped` reads the raw packed pixel
independently of drawing clips. These queries check the complete owner chain.

`get-shifts` and `get-losses` return fresh RGBA lists of native channel bit
positions and precision losses. Missing alpha has shift 0 and loss 8.
`get-blendmode` reports SDL's current surface mode as `:none`, `:blend`,
`:add`, `:mod`, or `:mul`, retaining an unknown mode's integer value. It reflects
native state (including `set-alpha`), rather than a particular blit's software
`:special-flags` override.

```lisp
(px:with-resource (tile (px.surface:subsurface atlas '(32 16 16 16)))
  (list (px.surface:get-abs-offset tile) ; => (32 16)
        (px.surface:get-pitch tile)
        (px.surface:unmap-rgb tile (px.surface:get-at-mapped tile '(0 0)))))
```

## Displays and events

`px.display:set-mode` takes size plus `:title`, `:flags`, `:fullscreen`, and
`:resizable`, and returns a software framebuffer. Calling it again replaces
and disposes the old framebuffer. `flip` presents the whole image; `update`
accepts a rectangle or list of rectangles. A resized window scales the logical
framebuffer on `flip`; call `set-mode` to change logical resolution. Caption,
icon, fullscreen, desktop sizes, and native window size are also exposed.

`get-driver`, `get-num-displays`, `list-modes`, and `get-display-info` query SDL's
video backend. `list-modes` returns unique `(width height)` pairs in native
order, or NIL when the backend reports no modes. `get-display-info` returns a
fresh plist with desktop/current size, pixel format/depth, refresh rate, and
driver when available. These queries require initialized video and do not create
a window; call them on the video subsystem's initializing thread. Display-index
queries default to display zero.

`px.display:iconify` requests minimization of the current window and returns
true after issuing SDL's request; it cannot report whether the window manager
has completed minimization. `get-allow-screensaver` reads SDL's current
screensaver setting, and `set-allow-screensaver` takes a boolean to allow or
inhibit it and returns that value. These operations require initialized video
and the video thread. Restore the prior screensaver setting when an application
temporarily changes it.

`px.event:get` pumps input and returns queued events. `:types` filters events
without consuming other types; `:limit` bounds the result. `:exclude` instead
retrieves all other types and leaves the excluded events queued. Pass one type
or a list/vector, and use either `:types` or `:exclude`, not both. Invalid
selection arguments are rejected before pumping or consuming events.
`poll` returns one
event or NIL; `wait` accepts an optional millisecond timeout. `clear`, `peek`,
`set-blocked`, and `set-allowed` manage the queue.
For `get`, `peek`, and `clear`, NIL selects all types, while an empty vector
`#()` selects none.

Pass `:pump nil` to inspect or consume only events already in the Lisp queue.
This does not read SDL's native queue, deliver due timers, advance music queues,
or run other pump hooks. The default remains T. `peek` and `clear` retain their
positional type argument, so use `(px.event:peek nil :pump nil)` or
`(px.event:clear nil :pump nil)` when selecting all types without pumping.
Queue consumption and pumping stay on the video thread when video is active;
workers may continue to post events.

```lisp
(px.event:pump)
;; A UI pass can consume input while leaving this game's timer events queued.
(let ((input (px.event:get :exclude turn-timer-type :pump nil)))
  (dolist (event input) (handle-input event)))
(px.event:get :types turn-timer-type :pump nil)
```

Selection follows the [pygame 2.6.1 event reference](https://github.com/pygame/pygame/blob/2.6.1/docs/reST/ref/event.rst).

`get-blocked` accepts one type or a list/vector and returns true when any type
is blocked. An empty sequence returns false. Passing NIL to `set-blocked`
blocks every type; passing NIL to `set-allowed` allows every type. Blocking
also removes matching events already in the Lisp queue. The filtering APIs
share the posting lock, so worker posting and filter changes are serialized.
`event-name` returns a readable type name. Known keywords use pygame-style
names, such as `"KeyDown"` for `:key-down`; custom integers have a
`"UserEvent (ID)"` label, and unknown types include their value.

```lisp
(let ((type (px.event:custom-type)))
  (px.event:post (px.event:make-event type :payload '(1 2 3)))
  (px.event:attribute (first (px.event:get :types type)) :payload))
```

`post` accepts Lisp payloads and is thread-safe. Pumping must stay on the video
thread. Native key events expose `:key`, `:keycode`, `:scancode`, `:mod`, and
`:repeat`; mouse events expose positions/relative movement/buttons. Text input
is UTF-8. Window events contain SDL's numeric sub-event and size. Device events
retain SDL-style event names where no Lisp spelling adaptation is documented.
Joystick hat/ball events expose `:which`, `:hat` or `:ball`, plus `:value` or
`:rel`; controller touchpad and sensor events copy their coordinates and data
into ordinary Lisp values. Touch finger and gesture events expose their ids,
positions, movement, pressure, and gesture data. Drop-file events expose `:file`, and drop-text
events expose `:text`. SDL-owned drop strings are copied and released while the
event is decoded, so returned events never point into native event memory.

`px.key:pressed-p` queries a key keyword or numeric scancode. `get-pressed`
returns a bit vector indexed by scancode. Modifier state, key names, focus, and
text-input start/stop/rectangle operations are available. `px.mouse` provides
position, relative movement, button states, cursor visibility, focus, and
relative mode. Keyboard and mouse state calls require an initialized video
subsystem and signal `initialization-error` before initialization or after
shutdown.

`px.key:set-repeat` takes a delay and optional interval in milliseconds.
`(px.key:set-repeat 250 60)` repeats a held native key after 250 ms, then every
60 ms while events are pumped. Interval zero uses the nonzero delay; delay
zero disables repeating. `get-repeat` returns a fresh `(delay interval)` list.
The initial key-down remains ordinary, and generated events have `:repeat t`.
SDL's own repeated key-downs are suppressed so it cannot double the repeats.

The most recently pressed native key repeats until its release, window focus
loss, a configuration change, or shutdown. Worker-posted Lisp events do not
start repeats. A stalled pump emits at most one overdue repeat, matching the
library's timer coalescing policy. These APIs require initialized video and
the video thread. Text composition stays in the separate UTF-8 text-input API.

`px.event:set-grab` / `get-grab` control the default window's mouse grab;
`set-keyboard-grab` / `get-keyboard-grab` control keyboard grab independently.
They require initialized video, an existing display, and the video thread.
Getters report SDL's observed state, which depends on focus and backend
support. Keyboard grab signals `unsupported-feature` if the installed SDL
lacks the required API. Closing the window releases its grabs.

## Time

`px.time:tick` returns elapsed milliseconds and optionally caps the frame rate.
Clocks expose elapsed/raw frame time and recent FPS. `get-ticks` is monotonic
milliseconds since system loading. `delay` and `wait` sleep in milliseconds.
`tick-busy-loop` currently uses the same cooperative implementation as `tick`.

`set-timer` takes an event or event type, interval, and `:loops` count. Zero
loops repeats; zero interval cancels. Timers deliver during pumping and
coalesce missed intervals instead of flooding the queue after a long pause.

## Pixel arrays and live views

`px.surface:get-buffer` exposes native pixel bytes and row padding as a locked
`buffer-view`. `px.surface:get-view` selects a typed view using a one-character
string or character (letters are case insensitive):

| Kind | Dimensions | Elements |
| --- | --- | --- |
| `"0"` | `(byte-count)` | Contiguous bytes; rejects padded rows |
| `"1"` | `(width * height)` | Contiguous packed pixels; rejects padded rows |
| `"2"` (default) | `(width height)` | Packed pixels with native row pitch |
| `"3"` | `(width height 3)` | RGB bytes, including negative BGR channel strides |
| `"r"`, `"g"`, `"b"`, `"a"` | `(width height)` | One byte per selected channel |

Packed element types follow the native pixel storage width. RGB views support
preserved 24- and 32-bit formats with adjacent RGB/BGR bytes; alpha requires a
32-bit per-pixel alpha surface. Normal public surface constructors use 32 bits.
Missing channels signal `px:unsupported-feature` without leaving a lock behind.

```lisp
(px.buffer:with-view (alpha (px.surface:get-view image "a"))
  (setf (px.buffer:view-ref alpha 10 20) 0)) ; cut a transparent pixel
```

Views lock immediately and retain their surface and all surface parents until
closed. Drawing clips do not restrict raw writes. For a cropped subsurface,
`get-buffer` bounds its bytes by the root allocation, so final-row padding may
be shorter than pygame's nominal `pitch * height` buffer. Inter-row gaps can
include neighboring parent pixels. Use a channel or packed view when edits
should stay inside the child's logical rectangle.

`px.surfarray:array2d`, `array3d`, `array-alpha`, and channel variants copy pixels
into specialized CL arrays. The array axes are **X, Y, channel**. `make-surface`
and `blit-array` copy arrays back; `map-array` maps channels to packed pixels.
`px.pixelcopy:surface-to-array` fills an existing correctly shaped array.

The corresponding `pixels*` functions share storage and lock it:

```lisp
(px.buffer:with-view (pixels (px.surfarray:pixels3d surface))
  (setf (px.buffer:view-ref pixels 10 20 0) 255))
```

`px.buffer:slice` takes starts, sizes, and optional steps (including negative
steps). Close slices before their parent. `to-array` copies a view. `dimensions`
and `strides` return fresh lists to protect the bounds metadata. `byte-offset`
identifies the first component within the owner's backing storage, and strides
describe its actual byte layout: BGRA RGB views, for example, have a negative
channel stride. Slices carry their corresponding offset and stride changes.
`px.pixelarray` provides a packed-pixel facade, slicing, replacement, extraction,
comparison, and surface conversion. Foreign pointers are not ordinary CL
arrays, so Python/NumPy's buffer protocols are represented by these explicit
views rather than implementation-specific foreign array tricks.

Raw pixel views and array copies write the underlying storage independently of
the surface's drawing clip. `pixels-alpha` requires a real per-pixel alpha
channel; on opaque surfaces it signals `unsupported-feature`, while the copied
  `array-alpha` result contains 255 throughout.

## PixelArray editing

`px.pixelarray:with-pixel-array` opens a packed 32-bit X/Y view and closes it on
exit. `ref` reads a native packed integer and supports `setf`. `replace`,
`extract`, and `compare` accept `:distance` in 0–1 and `:weights`, whose first
three nonnegative values are normalized to a positive sum. The default RGB
weights are `(0.299 0.587 0.114)`.

At distance zero, replace/extract match exact native pixels, including alpha.
At positive distance they compare weighted Euclidean RGB distance divided by
255 and ignore alpha. Color arguments can be native packed integers or ordinary
RGB(A)/Color/name values. `replace` edits the view and returns it; `extract`
returns a copied bit array with 1 for selected pixels. `compare` returns a bit
array with 1 where colors match; it decodes each input's native format, so BGRA
and RGBA views can be compared by color. Exact comparison includes alpha.
Invalid options are checked before replacement starts.

`transpose` swaps the X/Y axes without copying pixels. It retains its parent
view, shares writes, and reports swapped byte strides, including negative
strides from slices. Close it before the parent view. `make-surface` returns an
owned image copied from a view, preserving per-pixel alpha capability and
decoding the actual pixel format. It resets modulation and color-key state.

```lisp
(px.pixelarray:with-pixel-array (pixels image)
  (px.pixelarray:replace pixels "tomato" "gold" :distance 0.15)
  (px.buffer:with-view (turned (px.pixelarray:transpose pixels))
    (px:with-resource (copy (px.pixelarray:make-surface turned))
      (px.image:save copy #p"transposed.png"))))
;; The source surface is unlocked again here, ready for drawing/blitting.
```
