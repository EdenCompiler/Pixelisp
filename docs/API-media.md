# Image, font, and sound APIs

Pixelisp exposes SDL_image, SDL_ttf, SDL_mixer, and an optional direct FreeType renderer through ordinary Common Lisp packages. The main system loads `px.image`, `px.font`, `px.mixer`, `px.mixer.music`, and `px.sndarray`; the separate `pixelisp/freetype` system adds `px.freetype` and the `px.ftfont` compatibility facade. Loading a system does not initialize an audio device. Image and font operations initialize their SDL helper library when needed.

## Images

`(px.image:load source &key namehint)` decodes an image and returns an owned
`px.surface:surface`. SOURCE may be a pathname, string path, encoded
`(unsigned-byte 8)` vector, or binary input stream. For encoded memory data,
`:namehint` can supply a codec/extension such as `"PNG"` or `"icon.png"` when
SDL_image needs a format hint. The hint is ASCII alphanumeric (an extension is
accepted); supported codecs depend on the linked SDL_image build. Streams remain
open and owned by the caller. Loaded pixels are normalized into the drawing
API's surface format, so dispose the returned surface when finished.
`load-bytes` explicitly decodes encoded image-file bytes. `from-bytes` is an
alias for `from-string` and copies raw packed pixel bytes using the selected
dimensions and channel order; it does not decode a PNG/JPEG file.

`(px.image:save surface destination &key namehint (quality 90))` chooses PNG,
JPEG, BMP, or TGA from a pathname extension. Unknown extensions now select TGA,
matching pygame; earlier Pixelisp versions selected BMP. JPEG quality is an
integer from 0 to 100. PNG, BMP, and TGA are lossless; JPEG discards color detail.

DESTINATION can also be a binary output stream. Supply `:namehint :png`,
`:jpeg`, `:bmp`, or `:tga` to select its format, or omit it for TGA. The stream
remains open, and output starts at its current position. Use `finish-output`
before reading buffered output. Image encoding finishes before the first
stream write, so invalid codec arguments leave the stream untouched; ordinary
stream I/O errors can still leave partial output.

`(px.image:save-bytes surface &key namehint (quality 90))` returns a complete
encoded image as a specialized octet vector. `to-bytes` returns raw pixel
channels instead. PNG/JPEG/BMP memory output uses the lazy native adapter's
growable SDL stream, with no Lisp callbacks or intermediate files. TGA uses a
portable Lisp writer with uncompressed BGR/BGRA pixels and a top-left origin;
pygame can choose RLE compression and different transparency encoding.

```lisp
;; Encode an asset for storage in an archive; decode it again without a file.
(let ((encoded (px.image:save-bytes image :namehint "sprite.png")))
  (px:with-resource (decoded (px.image:load-bytes encoded))
    (px.surface:blit screen decoded '(40 60))))
```

`from-string` and `from-bytes` copy packed pixel data into a new surface. `to-string` and `to-bytes` copy pixels out as a specialized `(unsigned-byte 8)` vector. Both functions take dimensions as `(width height)` and a channel order such as `:rgb`, `:rgba`, `:rgbx`, `:argb`, `:bgra`, or `:bgr`. A true `flipped` argument reverses row order. Alpha is 255 for formats without an alpha channel.

Exports also accept `:rgba-premult` and `:argb-premult` (pygame's underscore
spellings, such as `"RGBA_PREMULT"`, work too). Each RGB channel becomes
`floor(channel * alpha / 255)`; alpha itself stays unchanged. This requires a
real per-pixel alpha channel. The source pixels, clip, color key, and blanket
alpha remain unchanged. Use this when supplying pixels to a compositor that
expects premultiplied colors. As in pygame, these are output formats only;
raw imports use the ordinary channel-order names.

```lisp
(let* ((pixels (make-array 16 :element-type '(unsigned-byte 8)
                           :initial-contents '(255 0 0 255 0 255 0 255
                                               0 0 255 255 255 255 255 255)))
       (image (px.image:from-bytes pixels '(2 2) :rgba)))
  (unwind-protect
       (px.image:save image #P"output.png")
    (px:dispose image)))
```

`from-buffer` shares a foreign-memory allocation with SDL instead of copying it. Pass `:owner` to keep the allocation's owning Lisp object reachable. The allocation must be valid and writable until the surface is disposed; a moving Lisp vector is not suitable storage. Shared imports require a supported 32-bit byte order (`:rgba`, `:bgra`, `:argb`, or `:rgbx`). For ordinary Lisp vectors, use `from-string`.

`get-sdl-image-version` reports the linked SDL_image version. `get-extended` reports that the extended image codecs are available through the linked library.

## SDL_ttf fonts

`(px.font:make-font source point-size)` opens a font and returns a managed resource.
SOURCE can be a pathname, string path, encoded `(unsigned-byte 8)` vector, or
binary input stream. NIL selects the bundled DejaVu Sans font, with the system
sans font as a fallback. `px.font:font` accepts the same sources;
`load-font-bytes` explicitly requires an encoded octet vector.
`px.font:sys-font` resolves a family name through fontconfig and accepts `:bold`
and `:italic`. `px.sysfont` re-exports the system-font lookup functions.

Binary streams are consumed from their current position to EOF and remain
open. Encoded inputs are copied into native-owned storage because SDL_ttf may
read glyph data after construction. You may change the original vector or
close the input stream immediately. Closing the font first closes its native
font, then its native stream, then releases its encoded bytes. The standard
path constructor keeps its existing behavior; loading the library opens no
font or device.

```lisp
;; Read a packed font asset; keep using FONT after INPUT has closed.
(let ((font (with-open-file (input "assets/ui.ttf" :element-type '(unsigned-byte 8))
              (px.font:make-font input 24))))
  (unwind-protect
       (px:with-resource (label (px.font:render font "Ready!" t "white"))
         (px.surface:blit screen label '(20 20)))
    (px:dispose font)))
```

Use `size` to measure UTF-8 text, `metrics` to inspect per-character glyph bounds and advance, and `render` to produce a surface. `render` takes an antialias flag and foreground color; an optional background color selects shaded rendering. Empty text returns a transparent surface. Font style accessors include `get-bold`/`set-bold`, `get-italic`/`set-italic`, `get-underline`/`set-underline`, and `get-strikethrough`/`set-strikethrough`. `get-height`, `get-linesize`, `get-ascent`, and `get-descent` expose font metrics.

`px.font:set-script` sets a four-ASCII-letter ISO 15924 script tag on one font
and returns the tag on success. For example, `"Latn"`, `"Grek"`, and `"Cyrl"`
select Latin, Greek, and Cyrillic shaping. This setting selects script rules
for SDL_ttf's text shaping; it does not set text direction or provide paragraph
layout. Text remains an ordinary Unicode string encoded as UTF-8, and the
existing rendering, style, and metric APIs continue to operate on the font.
The per-font native entry point requires SDL_ttf 2.20.0 or newer compiled with
HarfBuzz support. A missing native symbol signals `px:unsupported-feature`;
a native call failure signals `px:error`.

Fonts are native resources: use `px:dispose` or `px.font:close`, or place them in `px:with-resource`. After disposal, later use signals `px:disposed-resource`. `px.font:quit` disposes open fonts before quitting SDL_ttf. The optional `px.ftfont` facade offers the familiar SDL_ttf-style constructor and renderer backed by the direct FreeType implementation.

## Mixer and music

Call `px.mixer:init` before loading or playing sounds. It opens SDL_mixer's shared
audio device and accepts `:frequency`, `:size`, `:channels`, `:buffer`,
`:device-name`, and `:allowed-changes`. Supported sample sizes are 8, -8, 16,
-16, -32, and 32 bits. Positive 32 selects native-endian float32 samples; -32
retains signed integer PCM32. `pre-init` stores defaults for the next
initialization, while `get-init` returns the actual active frequency, sample
format, and channel count as three values.

`:device-name` is an SDL output-device name or NIL for the default output.
`px.sdl2.audio:devices` enumerates output names without opening a device.
`:allowed-changes` controls how SDL may adapt the requested settings. Pass a
list of `:frequency`, `:format`, `:channels`, and/or `:samples`, or their SDL
integer bitmask (1, 2, 4, and 8 respectively). The default is frequency and
channel changes (5). NIL or 0 requests the specified format; SDL can still
convert internally to a hardware format. Actual availability depends on the
audio backend. Buffer sizes round up to a power of two, with a 256-frame minimum.

Numeric zero for frequency, size, channels, or buffer uses the stored
`pre-init` default. For change flags, -1 uses the stored default and 0 remains
strict. `pre-init` itself resets omitted settings to the library defaults.
An already-open mixer retains its settings until `quit`; reinitializing it
does not switch outputs. Failed opening leaves it closed and available for a
later attempt.

```lisp
;; Use an enumerated output or NIL for the system default.
(px.mixer:pre-init :frequency 22050 :size -16 :channels 1
                   :buffer 300 :device-name (first (px.sdl2.audio:devices))
                   :allowed-changes '(:frequency :channels))
(px.mixer:init) ; Requests a 512-frame buffer after rounding.
(multiple-value-bind (frequency format channels) (px.mixer:get-init)
  (format t "~D Hz, ~D-bit format, ~D channels~%" frequency format channels))
```

For a float32 mixer, copied arrays and live `px.sndarray:samples` views use
specialized `single-float` elements. Mono data uses a frame vector; multichannel
data uses `(frames channels)`, with four-byte samples and channel-interleaved
native strides. Float array construction and live writes require single floats,
without implicit conversion from integers or double floats. The conventional
playback range is -1.0 through 1.0; out-of-range values are preserved. Raw PCM
`:buffer` octets remain unchanged. File decoding converts samples into the active
mixer format through SDL_mixer.

`get-init` and `sample-format` report 32 for float32 and -32 for signed PCM32.
This removes an ambiguity in pygame's current query, which can report -32 for
both native formats. Python/NumPy dtype protocols become Lisp element types.

```lisp
(px.mixer:init :frequency 22050 :size 32 :channels 1)
(let ((samples (make-array 2205 :element-type 'single-float :initial-element 0.0)))
  (dotimes (i (length samples))
    (setf (aref samples i) (coerce (* 0.2 (sin (* 2 pi 440 (/ i 22050)))) 'single-float)))
  (px:with-resource (sound (px.sndarray:make-sound samples))
    (px.mixer:play sound)
    (loop while (px.mixer:get-busy sound) do (px.time:delay 10))))
```

Mixer shutdown is repeatable. Read-only playback queries return their idle value when the mixer is closed (`get-busy` is false, `get-pos` is -1, and the channel count is zero); operations that need an open mixer signal `px:initialization-error`. `px.font:quit` also closes fonts and is safe to call more than once.

`(px.mixer:make-sound pathname)` decodes a sound file through SDL_mixer.
`(px.mixer:make-sound nil :file source)` also accepts a pathname, string path,
encoded `(unsigned-byte 8)` vector, or binary input stream. Streams are read
from their current position to EOF and remain open. `load-sound-bytes` is the
explicit octet-vector decoder. Decoded samples belong to the returned sound;
the input vector or stream may be reused as soon as decoding returns. WAV is
covered by the tests; other codecs depend on the linked SDL_mixer build.

Choose exactly one source: the positional path, `:file`, `:array`, or `:buffer`.
`:buffer` copies raw PCM in the active mixer's format; it does not decode a WAV
header. `px.sndarray:make-sound` copies a specialized Lisp array into sample
storage; mono samples use a one-dimensional vector, and multichannel samples
use `(frames channels)`. `px.sndarray:array` returns a copy.
`px.sndarray:samples` returns a live `px.buffer` view whose writes change the
sound data. Close the view when finished; disposing its sound invalidates it.

```lisp
;; ASSET-BYTES could come from a resource archive or an embedded WAV vector.
(px:with-resource (effect (px.mixer:load-sound-bytes asset-bytes))
  (px.mixer:play effect)
  ;; A game normally keeps EFFECT alive across many frames. Here we wait for it.
  (loop while (px.mixer:get-busy effect) do (px.time:delay 10)))
```

Echo Grove packages its generated melody cues as WAV bytes and decodes them
once per cached note. This exercises memory loading during ordinary gameplay.

`px.mixer:play` returns a channel object when playback starts. Channels can be selected with `:channel`, repeated with `:loops` (`-1` means repeat indefinitely), limited with `:maxtime`, or started with `:fade-ms`. `stop`, `pause`, `unpause`, and `fadeout` accept a channel, a sound, or NIL for all channels. `set-volume` and `get-volume` use the range 0 to 1. `queue` schedules the next sound on a channel. Call `px.mixer:update` once per game-loop iteration (the normal event pump also calls it) so queued sounds advance on the Lisp thread.

The `px.mixer.music` package handles streamed music separately from short sound
chunks. `load` accepts a pathname, string path, encoded octet vector, or binary
input stream; `load-bytes` explicitly requires an octet vector. Binary streams
are consumed from their current position to EOF and remain open. Optional
`:namehint` selects a codec: WAV, MOD, MIDI, OGG, MP3, FLAC, or OPUS; an empty
hint autodetects the format, and filename hints such as `"theme.ogg"` work too.
Available decoders depend on the SDL_mixer build.

Memory and stream inputs are copied into native-owned encoded storage that
stays alive until the music is replaced or unloaded. Decoding during playback
uses native SDL streams; no audio callback calls Lisp. The caller may mutate
its original bytes or close its input stream immediately after loading.
Large streams are materialized as encoded bytes, so this avoids decoding the
whole track to PCM but does retain the encoded asset in memory.

Use `play`, `pause`, `unpause`, `rewind`, `stop`, `set-pos`, or `queue` after
loading. Music is a singleton native stream; `unload` releases it and any queued
track. `get-pos` reports elapsed playback milliseconds, and returns -1 when
stopped. `queue` accepts the same sources and name hints, plus `:loops`; it
prepares one pending track and replaces any prior queued track. Invalid sources
leave current/queued tracks unchanged. Natural handoff occurs when events are
pumped or `px.mixer:update` runs. Stopping music discards its queued track.

## Playback completion events

`px.mixer:set-endevent` configures a channel's completion event, and
`get-endevent` reads it. `px.mixer.music:set-endevent` / `get-endevent` configure
the singleton music stream. Use a custom event integer or a keyword, and pass
0 (or omit the type) to disable notifications. Channel events contain `:code`
with the channel ID; music uses `:code 0`.

```lisp
(let* ((finished (px.event:custom-type))
       (channel (px.mixer:make-channel 0)))
  (px.mixer:set-endevent channel finished)
  (px.mixer:play sound :channel channel)
  ;; In the application's ordinary event loop:
  (dolist (event (px.event:get :types finished))
    (format t "Channel ~D finished~%" (px.event:attribute event :code))))
```

Completion is observed and events are posted by the mixer update/event pump
on the Lisp thread. Stop, replacement, and queued playback each retain their
own completion record. Pending records keep the configured event type, even
if notification is subsequently disabled. Native audio threads never call
application Lisp. Keep pumping so queues advance and events are delivered.
Channel settings reset when the mixer is reopened; music's module-wide event
type persists across shutdown. Shutdown discards undelivered records.

## Direct FreeType

Load `pixelisp/freetype` for `px.freetype`. `render` returns a surface and a
baseline-relative bounds Rect; `render-raw` returns a packed grayscale mask and
its `(width height)`. The packed vector is row-major (`x + y * width`). Pass
`:invert t` to `render-raw` to return `255 - coverage` for every mask pixel.

`style` is a settable bitmask: combine `style-strong` (1), `style-oblique` (2),
`style-underline` (4), and `style-wide` (8) with `logior`. `style-normal` (0)
clears all flags. The boolean properties `strong`, `oblique`, `underline`, and
`wide` change individual bits. Assigning `style-default` (255) leaves the font's
default unchanged. `get-rect`, `render`, `render-to`, `render-raw`, and
`render-raw-to` accept `:style` to override that default for one call; the font
itself is not changed. With `render` and `render-to`, supply the optional
foreground and background arguments before keyword arguments.

Strong, oblique, and wide operate on FreeType outlines before rasterization.
They require an outline font and bypass any embedded bitmap strike; requests
on bitmap-only fonts signal `px:unsupported-feature` before changing style.
`strength` ranges from 0 through 1 and defaults to 1/36. Wide scales outlines
and advances horizontally; strong expands the outline in both dimensions.
Underline uses the font's native underline position and thickness, with a
minimum one-pixel stroke. `underline-adjustment` ranges from -2 through 2 and
defaults to 1: positive values scale the underline offset below the baseline,
while negative values place the stroke above it using the ascender. Pixel
rounding, glyph advances, and bounds retain Pixelisp's layout differences from
pygame. `get-metrics` reports the original glyph metrics without these styles.

```lisp
(ql:quickload "pixelisp/freetype")
(px:with-resource (font (px.freetype:make-font nil 28))
  (setf (px.freetype:strong font) t)
  ;; A single underlined prompt, preserving this font's strong default.
  (px:with-resource
      (label (px.freetype:render font "Your turn" '(245 220 130) nil
                                :style px.freetype:style-underline))
    (px.surface:blit screen label '(30 100))))
```

Read-only face information includes `scalable-p`, `fixed-width-p`, and
`fixed-sizes` (the count of embedded bitmap strikes). `height`, `ascender`, and
`descender` return unscaled font units, with descent normally negative; these
fields may be zero for bitmap fonts. `get-sized-glyph-height` returns the
pixel ascent-to-descent span including one baseline row, independently of
styling. `get-sizes` returns fresh lists of
`(point-size height width x-ppem y-ppem)` strike records, or NIL for an
outline-only font. The first three values are integers and ppem values are
fractional pixels. Bitmap sizes must match a supported strike when opening or
rendering that font.

`rotation` is a settable integer angle in counterclockwise degrees, normalized
to 0 through 359: -45 becomes 315 and 720 becomes 0. All rendering functions
and `get-rect` accept `:rotation` to override it for one call without changing
the font. Glyph outlines rotate before rasterization, with their placement
rotated around the text baseline. Rotation requires an outline font. As in
pygame, wide or underlined text cannot be rotated; an unsupported combination
signals `px:unsupported-feature` before painting a caller's target.

The boolean `vertical` property selects top-to-bottom layout using FreeType's
vertical bearings and advances. Glyphs remain upright within the column;
rotation turns the column and its glyphs together. Fonts without native
vertical metrics use the metrics FreeType synthesizes. This is explicit
orientation control, not automatic script detection or paragraph shaping.
Underlining is unavailable in vertical layout. Pixelisp's bounds include the
baseline advance, which can add blank padding after the last vertical glyph.

```lisp
(px:with-resource (font (px.freetype:make-font nil 28))
  (setf (px.freetype:origin font) t
        (px.freetype:rotation font) 90)
  (px.freetype:render-to font screen '(300 250) "UP" '(240 220 130) nil)
  ;; Render one upright label while retaining the font's stored angle.
  (px.freetype:render-to font screen '(40 80) "Score" '(255 255 255) nil :rotation 0)
  (setf (px.freetype:rotation font) 0
        (px.freetype:vertical font) t)
  (px.freetype:render-to font screen '(500 60) "ABC" '(160 220 255) nil))
```

Fonts expose `kerning`, `antialiased`, sized ascender/descender metrics, glyph
metrics, and kerning queries. The `origin` property defaults to NIL and can be
set with `(setf (px.freetype:origin font) t)`. There is no `:origin` constructor
keyword. With origin disabled, `render-to` and `render-raw-to` treat `dest` as
the top-left of the rendered bounds. With origin enabled, `dest` is a baseline
point; both methods offset the glyph bounds by their baseline-relative `x` and
`y` values. A negative bounds `y` is expected: it is the top edge's offset above
the baseline, so placement adds it to the baseline's Y coordinate. This keeps
`get-rect`'s baseline-relative measurements intact while letting callers place
the baseline directly.

`render-raw-to` writes grayscale coverage into a writable rank-two target and
returns the original, baseline-relative `get-rect` bounds. The return Rect is
not clipped or shifted by `dest`; writes are clipped to the target. Targets use
Pixelisp's `(width height)` X/Y axis order. An ordinary array must have an
integer element type that can represent every value from 0 through 255. A
`px.buffer:buffer-view` must be a live, writable rank-two
`(unsigned-byte 8)` plane, such as a surface alpha-channel view. Pixels whose
original glyph coverage is zero are left untouched, including in inverted
mode; for nonzero coverage, `:invert t` writes `255 - coverage`.

Pass NIL as text to `get-rect`, `render`, `render-to`, `render-raw`, or
`render-raw-to` to reuse the last successfully laid-out string on that font.
The font copies the string, so later caller edits do not change the retained
text. A fresh font reuses an empty string, and `get-metrics` does not replace
it. Size, style, rotation, and other properties still apply on each call;
this is text reuse, without pygame's layout cache. Failed layout validation
preserves the previous string; a later painting failure can occur after the
new layout has already been retained. Pixelisp retains its minimum 1×1 bounds
for blank rendered text.

The boolean `use-bitmap-strikes` property defaults to T. Set it to NIL to
request outlines from scalable fonts that also contain embedded bitmaps.
It is ignored for bitmap-only fonts, which still require a supported strike.
Synthetic styling and rotation already request outlines regardless of this
property.

```lisp
(px:with-resource (font (px.freetype:make-font nil 24))
  (px.freetype:get-rect font "Ready?")
  ;; Reuse the measured string with a different placement/color.
  (px.freetype:render-to font screen '(80 100) nil '(255 220 140)))
```

The reference is [pygame 2.6.1 FreeType](https://github.com/pygame/pygame/blob/2.6.1/docs/reST/ref/freetype.rst),
with native metric units described by [FreeType's face fields](https://freetype.org/freetype2/docs/reference/ft2-face_creation.html#ft_facerec).
The default `size` property, constructors, sized metrics, and per-call `:size`
arguments accept a positive scalar or a two-value list/vector
`(horizontal vertical)`. Sizes retain Pixelisp's pixel units; pygame uses
points and a configurable resolution. Scalar sizes keep the font's normal
aspect ratio. A pair selects independent horizontal and vertical ppem; a zero
vertical value, such as `'(24 0)`, selects equal ppem. Zero horizontal values
and undefined all-zero sizes are rejected. Bitmap-only fonts require a matching
native strike and cannot be stretched to arbitrary sizes.

The property copies pairs on input and output. A per-call override leaves the
default size unchanged, and invalid assignments preserve it. Fractional sizes
round to native pixel sizes, with a minimum of one pixel on nonzero axes.
Strong styling and underline sizing follow the vertical size. Pygame's layout
cache remains unimplemented.

```lisp
(px:with-resource (font (px.freetype:make-font nil '(16 32)))
  (px:with-resource (label (px.freetype:render font "TALL" '(180 230 255)))
    (px.surface:blit screen label '(30 60)))
  ;; A wider one-off label without changing the stored (16 32) size.
  (px.freetype:render-to font screen '(30 110) "WIDE" '(255 220 140) nil
                         :size #(32 20)))
```

```lisp
(let ((font (px.freetype:make-font nil 24))
      (surface (px.surface:make-surface '(320 80) :alpha t)))
  (unwind-protect
       (px.buffer:with-view (alpha (px.surface:get-view surface "A"))
         ;; The alpha plane is shared storage: nonzero mask bytes update it in place.
         (px.freetype:render-raw-to font alpha "Pixelisp" :dest '(12 36)))
    (px:dispose font)
    (px:dispose surface)))
```

Close a surface view when finished; its view locks the surface until closed.
Each font owns a FreeType face and follows the same explicit disposal rules as
SDL_ttf fonts.

All sample and image operations in this guide work with SDL's dummy video/audio drivers, so applications can exercise decoding and data manipulation in headless environments. Real playback and window presentation require the corresponding system devices.
