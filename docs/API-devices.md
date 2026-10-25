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

Textures belong to the renderer that created them. Closing a window or
renderer closes its children first. Raw audio devices are opened paused;
`queue` accepts PCM octets in the negotiated format and `start` begins
playback. `dequeue` reads octets from an explicitly opened capture device.
Use `devices` to list device names without opening them.

The optional `px.sdl2.mixer:start-capture` bridge records the SDL_mixer
postmix stream in a bounded native ring buffer. `read-capture` drains up to a
requested number of bytes. The audio callback never calls Lisp; applications
must stop capture before shutting down the mixer.
