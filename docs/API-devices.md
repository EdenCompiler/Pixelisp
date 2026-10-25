# Devices, threads, and SDL2 extensions

Pixelisp keeps device access explicit. SDL joystick, controller, cursor,
clipboard, audio, window, renderer, and texture objects own native handles and
should be closed with `px:dispose` or the module's `close` function. The
`with-*` macros close resources when their body exits. Camera objects are
reusable configurations: `start` opens capture, `stop` releases the stream,
and disposal permanently closes the Lisp resource.

The base system provides SDL input, clipboard, worker threads, SDL2 windows,
renderers, textures, and raw queued audio. `pixelisp/camera` adds the Linux
V4L2 helper and needs a C compiler, `pkg-config`, SDL2/SDL2_mixer development
files, and libv4l2. `pixelisp/midi` adds optional PortMidi support and needs
libportmidi. Neither dependency is required merely to load `pixelisp/all`;
the adapters are loaded when first used. On Linux, install the relevant
development package only for the adapter you plan to use.

## Joysticks and mapped controllers

```lisp
(px.joystick:init)
(format t "~{~A~%~}" (px.joystick:names))
(px.joystick:with-joystick (pad 0)
  (px.joystick:update)
  (format t "X=~,2F button 0=~A~%"
          (px.joystick:get-axis pad 0)
          (px.joystick:get-button pad 0)))
```

`px.joystick:get-axis` normalizes signed SDL axis values to approximately
`[-1,1]`; hats return `(x y)` components in `{-1,0,1}`. Use
`px.controller:controller-p` and `open-controller` for SDL's standard game
controller mapping, where axes and buttons can also be named keywords such as
`:left-x` and `:a`. Joystick enumeration initializes SDL's joystick subsystem
when needed. Call `quit` when the subsystem is no longer needed.

`px.joystick:get-guid` returns an open device's 32-character lowercase hardware
GUID, useful for saving bindings across reconnects. `get-power-level` returns
`:unknown`, `:empty`, `:low`, `:medium`, `:full`, or `:wired`; reported battery
information depends on the device and SDL driver. Both reject disposed devices.

`px.controller:name-for-index` returns the name for a nonnegative enumeration
index, or NIL if no mapped controller exists at that index. This index can
change after hotplugging; use `instance-id` to identify an open device in events.
`get-eventstate` and `set-eventstate` query or toggle native controller events:

```lisp
(let ((previous (px.controller:get-eventstate)))
  (unwind-protect
       (px.controller:set-eventstate nil)
    (px.controller:set-eventstate previous)))
```

These module queries initialize the controller subsystem lazily. The switch
leaves joystick events enabled independently and does not filter Lisp-posted
events. The test suite verifies identity queries and the switch with SDL virtual
devices; it does not verify a physical device's battery reporting.

## Text clipboard

The SDL scrap adapter currently handles UTF-8 text and reports that limit
through `capabilities`:

```lisp
(px.scrap:init)
(px.scrap:put-text "hello from Pixelisp")
(px.scrap:get-text)          ; => "hello from Pixelisp"
(px.scrap:get "text/plain") ; => UTF-8 octets
```

The default mode uses the system clipboard. Set mode to `:selection` to use
the platform's primary selection where SDL supports it. The adapter reports
unsupported binary or MIME-specific operations rather than silently
converting them.

## Worker threads

```lisp
(let ((job (px.threads:spawn (lambda () (values :done 42)))))
  (multiple-value-bind (status result) (px.threads:join job)
    (list status result)))

(px.threads:parallel-map #'1+ '(1 2 3 4) :workers 2)
```

`join` waits for completion, returns every value from the worker function, and
re-signals an error raised by that function. `parallel-map` uses at most the
requested number of workers and preserves input order.

## Camera capture

Load `pixelisp/camera` (or `pixelisp/all`) before using the camera API. Camera
listing probes V4L2 capture nodes but does not start capture:

```lisp
(px.camera:init)
(px.camera:list-cameras)
(px.camera:with-camera (camera "/dev/video0" :size '(640 480) :format :rgb)
  (let ((frame (px.camera:get-image camera :timeout 500)))
    (when frame (px.surface:save frame "frame.png"))))
```

Frames are returned as RGB surfaces by default. `get-raw` returns tightly
packed RGB24 octets. `:hsv` and `:yuv` request conversion after capture. Camera
controls are device-dependent; inspect them with `get-controls` or
`control-info` before setting a value. Capture waits are bounded by the
`timeout` argument in milliseconds.

## MIDI

Load `pixelisp/midi` (or `pixelisp/all`) to access PortMidi. Enumeration is
safe without opening a port; actual input and output use are explicit:

```lisp
(px.midi:init)
(loop for id below (px.midi:get-count)
      collect (px.midi:get-device-info id))

(let ((id (px.midi:get-default-input-id)))
  (when id
    (px.midi:with-input (stream id)
      (when (px.midi:poll stream)
        (px.midi:read stream 16)))))
```

Output sends bytes to real hardware, so applications should choose a device
deliberately. The helpers `note-on`, `note-off`, `set-instrument`, and
`pitch-bend` build standard channel messages. MIDI event timestamps use
PortTime milliseconds. No port is opened by loading the system.

## SDL2 renderer and raw audio

```lisp
(px.sdl2.video:with-window (window :title "Demo" :size '(640 480))
  (px.sdl2.video:with-renderer (renderer window)
    (setf (px.sdl2.video:draw-color renderer) '(20 30 50))
    (px.sdl2.video:clear renderer)
    (px.sdl2.video:present renderer)))
```

Window controls work with any live `px.sdl2.video:window` and must run on the
video thread. `window-id` and `window-display-index` are read-only queries.
`window-resizable-p`, `window-borderless-p`, and `window-grab-p` are readable
and settable boolean states. `window-opacity` reads or sets opacity from 0.0
(transparent) to 1.0 (opaque); a backend that does not support opacity signals
`px:unsupported-feature`. `set-fullscreen` requests fullscreen, with `:desktop
t` selecting desktop-sized mode; `set-windowed` exits fullscreen, and
`window-fullscreen-mode` reports NIL, `:desktop`, or `:exclusive`. These are
requests to SDL and the window manager, so actual state changes can be
asynchronous or platform-dependent. `maximize-window`, `minimize-window`,
`restore-window`, and `focus-window` issue the corresponding window-manager
requests. `set-window-icon` takes a software surface and rejects a locked one.

```lisp
(px.sdl2.video:with-window (window :title "Pixelisp" :size '(800 600)
                                   :resizable t)
  (format t "SDL window ~D on display ~D~%"
          (px.sdl2.video:window-id window)
          (px.sdl2.video:window-display-index window))
  (setf (px.sdl2.video:window-borderless-p window) nil)
  (when (eq :desktop (px.sdl2.video:window-fullscreen-mode window))
    (px.sdl2.video:set-windowed window)))
```

The controls follow pygame 2.6.1's `_sdl2.video.Window` API where applicable;
see the [tagged pygame 2.6.1 source](https://github.com/pygame/pygame/blob/2.6.1/src_c/cython/pygame/_sdl2/video.pyx)
and the [SDL2 video reference](https://wiki.libsdl.org/SDL2/CategoryVideo).

The renderer controls include `draw-rect`, `viewport`, `logical-size`,
`renderer-scale`, and `draw-blend-mode`. Their getters return the current SDL
state; setters accept a rectangle or NIL for the full viewport, a positive
`(width height)` logical size (or `(0 0)` to disable it), positive scale
factors, and blend keywords `:none`, `:blend`, `:add`, `:mod`, `:mul` or SDL
blend-mode integers. These settings affect renderer operations and do not
change the separate software display surface.

Target textures let a renderer draw into a texture and use that texture later.
Check `target-supported-p` first; create the texture with `:access :target`,
then bind it using `with-render-target`. The macro restores the prior target,
including when its body signals an error. `target` returns the bound texture
or NIL. A target must belong to the same renderer. Closing a window or
renderer closes its children first, and disposing an active target unbinds it.

```lisp
(let ((target (px.sdl2.video:make-texture renderer '(128 96) :access :target)))
  (unwind-protect
       (px.sdl2.video:with-render-target (renderer target)
         (px.sdl2.video:clear renderer '(30 40 70 255))
         (px.sdl2.video:draw-texture renderer sprite :destination '(16 16 32 32)
                                      :angle 20 :origin '(0 0)))
    (px.sdl2.video:close target)))
```

`to-surface` reads pixels from the current target into a new RGBA surface, or
overwrites a supplied surface. `:area` is a physical-pixel rectangle within
the current target; a supplied destination must use 32-bit pixels and have
exactly that area's width and height. Active destination views/locks must be
closed first. Readback uses the destination's native format and pitch, including
BGRA buffers and padded subsurfaces, and ignores the surface's drawing clip.
SDL reads only the intersection with the renderer's physical viewport. Pixels
outside it remain unchanged in a supplied destination, or transparent in a new
surface. Readback preserves the renderer's viewport, scale and logical size.
The operation
is slow and is best kept out of a per-frame
path. Read the backbuffer before `present` when you need the current frame.

Textures belong to the renderer that created them. `texture-get-rect` returns
a texture-sized rectangle and accepts the same anchor/value pairs as
`px.surface:get-rect`. `update-texture` uploads a software surface, converting
its pixel format to the texture's format when needed. For a partial update,
`:area` selects the destination rectangle while the uploaded source patch
starts at the source surface's top-left. The area must fit the texture, and
the source must be at least as wide and high as the area; out-of-bounds updates
signal an error instead of clipping. SDL documents texture updates as slow and
recommends them for textures that change infrequently.

`draw-texture` accepts `:source`, `:destination`, `:angle`, `:flip-x`, and
`:flip-y`; `:origin` supplies the rotation point relative to the destination's
top-left. Without an origin SDL rotates around the destination center. These
texture calls, like the renderer controls, must run on the video thread.

## Texture atlas images

`make-image` creates a lightweight `image` view over a renderer-owned texture;
it does not copy or allocate pixel data. Its optional source rectangle is a
nonempty, contained crop relative to the input texture or parent image. A child
crop can be nested inside that parent crop. Rectangles are strict: zero-sized
and out-of-bounds regions signal an error rather than being clipped.

`image-source-rect` returns a copy of the view's rectangle in absolute texture
coordinates. Setting it also takes an absolute texture-coordinate rectangle
and requires it to remain inside the view's parent region. `image-get-rect`
returns a positioned copy of the view rectangle using the same anchor/value
pairs as `texture-get-rect`; changing the returned rect does not mutate the
image. The `image-texture` setter can rebind a view to another texture owned by
the same renderer, provided the parent region fits. The modifier accessors
(`image-angle`, `image-origin`, `image-flip-x`, `image-flip-y`, `image-color`,
`image-alpha`, and `image-blend-mode`) read or set per-view drawing state.
Origin and color getters return copies. Colors accept the same lists, vectors,
and `px:color` values as other Pixelisp color arguments; `image-alpha` is an
integer from 0 through 255. Blend mode accepts `:none`, `:blend`, `:add`,
`:mod`, `:mul` or the corresponding SDL values 0, 1, 2, 4, and 8.

`draw-image` accepts an optional contained `:source` crop relative to the view.
Its `:destination` can be a `(x y)` position, a rectangle that scales the image,
or NIL to fill the renderer's current viewport. Angle, origin, flip, color,
alpha, and blend settings come from the image. Since SDL stores color/alpha/blend
modifiers on the shared texture, Pixelisp applies the image's values for the
draw and restores the texture's previous values afterwards, even if drawing
fails. This keeps two atlas views of the same texture independent. Images
retain their texture wrapper, but become unusable when that texture is closed;
all image access and drawing must run on the video thread.

```lisp
(let* ((atlas (px.sdl2.video:make-image texture))
       (button (px.sdl2.video:make-image atlas '(16 8 32 16)))
       (icon (px.sdl2.video:make-image button '(8 0 16 16))))
  (setf (px.sdl2.video:image-color icon) '(255 220 180)
        (px.sdl2.video:image-alpha icon) 224
        (px.sdl2.video:image-angle icon) 8)
  (px.sdl2.video:draw-image renderer icon :destination '(20 30)))
```

The API follows pygame's `_sdl2.video` texture, renderer surface, and image
behavior where applicable: [pygame 2.6.1 source](https://github.com/pygame/pygame/blob/2.6.1/src_c/cython/pygame/_sdl2/video.pyx)
and [pygame SDL2 video reference](https://www.pygame.org/docs/ref/sdl2_video.html).
SDL's [render readback reference](https://wiki.libsdl.org/SDL2/SDL_RenderReadPixels)
documents the readback call and its performance warning. Raw audio devices are opened paused;
`queue` accepts PCM octets in the negotiated format and `start` begins
playback. `dequeue` reads octets from an explicitly opened capture device.
Use `devices` to list device names without opening them.

The optional `px.sdl2.mixer:start-capture` bridge records the SDL_mixer
postmix stream in a bounded native ring buffer. `read-capture` drains up to a
requested number of bytes. The audio callback never calls Lisp; applications
must stop capture before shutting down the mixer.
