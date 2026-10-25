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

`(px.image:save surface pathname &key (quality 90))` chooses PNG, JPEG, or BMP from the pathname extension. JPEG quality is an integer from 0 to 100. PNG and BMP are lossless; JPEG discards color detail.

`from-string` and `from-bytes` copy packed pixel data into a new surface. `to-string` and `to-bytes` copy pixels out as a specialized `(unsigned-byte 8)` vector. Both functions take dimensions as `(width height)` and a channel order such as `:rgb`, `:rgba`, `:rgbx`, `:argb`, `:bgra`, or `:bgr`. A true `flipped` argument reverses row order. Alpha is 255 for formats without an alpha channel.

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

`(px.font:make-font pathname point-size)` opens a font and returns a managed resource. A NIL pathname selects the bundled DejaVu Sans font, with the system sans font as a fallback. `px.font:sys-font` resolves a family name through fontconfig and accepts `:bold` and `:italic`. `px.sysfont` re-exports the system-font lookup functions.

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

Call `px.mixer:init` before loading or playing sounds. It opens SDL_mixer's shared audio device and accepts `:frequency`, `:size`, `:channels`, and `:buffer`; supported sample sizes are 8, -8, 16, -16, and -32 bits. `pre-init` stores defaults for the next initialization, while `get-init` returns the active frequency, signed sample size, and channel count.

Mixer shutdown is repeatable. Read-only playback queries return their idle value when the mixer is closed (`get-busy` is false, `get-pos` is -1, and the channel count is zero); operations that need an open mixer signal `px:initialization-error`. `px.font:quit` also closes fonts and is safe to call more than once.

`(px.mixer:make-sound pathname)` loads a decoded WAV sample. `px.sndarray:make-sound` copies a specialized Lisp array into mixer-owned sample storage; mono samples use a one-dimensional vector, and multichannel samples use `(frames channels)`. `px.sndarray:array` returns a copy. `px.sndarray:samples` returns a live `px.buffer` view whose writes change the sound data. Close the view when finished; disposing its sound invalidates it.

`px.mixer:play` returns a channel object when playback starts. Channels can be selected with `:channel`, repeated with `:loops` (`-1` means repeat indefinitely), limited with `:maxtime`, or started with `:fade-ms`. `stop`, `pause`, `unpause`, and `fadeout` accept a channel, a sound, or NIL for all channels. `set-volume` and `get-volume` use the range 0 to 1. `queue` schedules the next sound on a channel. Call `px.mixer:update` once per game-loop iteration (the normal event pump also calls it) so queued sounds advance on the Lisp thread.

The `px.mixer.music` package handles streamed music separately from short sound chunks. Load a pathname, then use `play`, `pause`, `unpause`, `rewind`, `stop`, `set-pos`, or `queue`. Music is a singleton native stream; `unload` releases the current stream. `get-pos` reports elapsed playback milliseconds, and returns -1 when stopped.

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

The reference is [pygame 2.6.1 FreeType](https://github.com/pygame/pygame/blob/2.6.1/docs/reST/ref/freetype.rst),
with native metric units described by [FreeType's face fields](https://freetype.org/freetype2/docs/reference/ft2-face_creation.html#ft_facerec).
Vertical layout, text rotation, independent horizontal/vertical font sizes, and
pygame's layout cache remain unimplemented in this direct renderer.

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
