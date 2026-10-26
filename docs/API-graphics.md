# Graphics, vectors, masks, and sprites

Pixelisp's CPU graphics APIs work directly on `px.surface` surfaces. Drawing
does not need an SDL renderer or a window. Transform operations return a new
surface; drawing and mask edits update their first argument. Unless noted,
positions are `(x y)` pairs, sizes are `(width height)`, and colors are RGB or
RGBA values accepted by `pixelisp:make-color` (lists are convenient).

Load the complete system before using surfaces and drawing:

```lisp
(ql:quickload "pixelisp")
```

## Drawing

`px.draw` follows the pygame draw-module argument order: surface, color, then
geometry. It includes `rect`, `line`, `lines`, `aaline`, `aalines`, `circle`,
`ellipse`, `polygon`, and `arc`. A zero `:width` fills supported closed
shapes; positive widths draw an inward border. Each drawing function returns a
rectangle enclosing the pixels it changed (an empty rectangle when clipping
removes all pixels). Drawing honors the surface clip and unlocks the surface
even if drawing signals an error.

`rect` accepts a common `:border-radius` plus independent
`:border-top-left-radius`, `:border-top-right-radius`,
`:border-bottom-left-radius`, and `:border-bottom-right-radius` overrides.
A negative override inherits the common radius; zero keeps that corner square.
When adjacent radii exceed an edge, all four radii scale proportionally to fit.
Outlines stay inside the rectangle and reduce the inner corner radii by the
stroke width. The CPU rasterizer retains Pixelisp's documented pixel-rounding
differences from pygame.

```lisp
;; A tab with rounded top corners and square bottom corners.
(px.draw:rect screen "steelblue" '(20 20 180 60) :border-radius 18
              :border-bottom-left-radius 0 :border-bottom-right-radius 0)
```

```lisp
(px.surface:with-surface (canvas '(160 100) :alpha t)
  (px.draw:rect canvas '(25 35 50) '(8 8 144 84))
  (px.draw:line canvas '(240 220 90) '(12 15) '(140 82) :width 3)
  (px.draw:circle canvas '(80 180 230 180) '(80 50) 18))
```

`px.gfxdraw` offers the pygame.gfxdraw-style argument order where coordinates
precede the color, for example `(px.gfxdraw:box surface x1 y1 x2 y2 color)`.
Its `filled-*`, `aa*`, polygon, arc, pie, and Bezier helpers use the same CPU
rasterizers. `textured-polygon` fills an area from a repeating texture.

## Transforms and pixel operations

`px.transform:flip`, `scale`, `smoothscale`, and `rotate` return independent
surfaces. `scale` uses nearest-neighbor sampling; `smoothscale` averages
samples. `scale-by` and `smoothscale-by` accept scale factors. Other helpers
include `rotozoom`, `scale2x`, `chop`, `grayscale`, `average-color`,
`average-surfaces`, and `threshold`. Surface alpha metadata and color keys are
preserved by transforms where applicable.

`laplacian` finds edges with a 3×3 kernel: eight times each center channel
minus its eight neighbors, clamped to octets. Missing neighbors are opaque
white. It returns a new surface, or accepts an optional destination of the
same dimensions and pixel byte size. Its raw output ignores destination clips
and source blending/color keys; an input snapshot makes overlapping inputs
and in-place operation stable. Alpha is filtered too, so fully opaque RGBA
input can produce transparent edges. Use an opaque source when displaying
RGB edge responses, such as an opaque gameplay backdrop.

```lisp
(let ((half (px.transform:smoothscale source '(64 48)))
      (mirror (px.transform:flip source t nil)))
  (unwind-protect
       (px.surface:blit screen half '(10 10))
    (pixelisp:dispose half)
    (pixelisp:dispose mirror)))
```

`px.mask` stores one collision bit per pixel. `from-surface` uses alpha greater
than its default threshold of 127, or excludes the surface's color key when
one is set. `overlap` and `overlap-area` take the offset of the second mask in
the first mask's coordinates. `overlap-mask`, `draw`, and `erase` provide
composable mask operations. `connected-components` treats diagonal neighbors
as connected.

`get-rect` returns a fresh rectangle with the mask's size. Like
`px.surface:get-rect`, it accepts point anchors such as `:center #(100 80)` or
`:top-left '(20 30)`, and scalar anchors such as `:right 200` or `:center-x 90`.
Compact pygame spellings such as `:topleft` work too. Anchors apply in caller
order; later assignments win. Empty mask dimensions remain zero, so placing
an empty mask does not turn it into a nonempty collision area.

```lisp
(let* ((mask (px.mask:from-surface image))
       (hit (px.mask:overlap mask obstacle-mask '(12 4))))
  (when hit (format t "Collision at ~S~%" hit)))
```

`px.mask:to-surface` paints a mask into a new owned alpha surface, or into a
provided `:surface` of any size. `:dest` moves the mask relative to the
destination and honors its drawing clip. `:set-color` and `:unset-color`
choose raw RGBA values, or NIL to preserve that kind of destination pixel.
Defaults match pygame: opaque white for set bits and opaque black for unset
bits. Earlier Pixelisp versions used transparent black for unset bits; pass
`'(0 0 0 0)` explicitly to retain that result.

Optional `:set-surface` and `:unset-surface` planes provide colors at mask
coordinates; positions outside a smaller plane fall back to the corresponding
color. Planes must match destination depth, byte size, and alpha mask.
Sources are snapshotted before drawing so shared/overlapping images are safe.
No blit alpha, modulation, or color-key operation is applied to these samples.
Colors and live owners are validated before destination writes.

```lisp
;; Draw collision bits over existing art while preserving unset pixels.
(px.mask:to-surface collision-mask :surface screen :dest '(80 60)
                    :set-color '(255 80 140 255) :unset-color nil)
```

## Vectors

`px.math:make-vector2` and `make-vector3` accept components, one repeated
number, another vector, or a list/array. `x`, `y`, and `z` are readable and
settable. Arithmetic such as `add`, `subtract`, `multiply`, and `divide`
returns a new vector; scalar second arguments apply to every component.
Functions ending in `-ip` mutate their first vector and return it.

`component` reads a coordinate by zero-based index; negative indices count from
the end. It supports `setf`. `swizzle` reads lowercase `x`/`y`/`z` patterns,
including repeated coordinates and embedded `0`/`1` constants. A one-character
pattern returns a number; longer patterns return a fresh list. Patterns must
contain a coordinate valid for the vector's dimension.

```lisp
(let ((velocity (px:make-vector2 3 4)))
  (setf (px.math:component velocity -1) 8)
  (px.math:swizzle velocity "xy01") ; => (3 8 0 1)
  (setf (px.math:swizzle velocity "xy") (px.math:swizzle velocity "yx"))
  (px.math:components velocity))  ; => (8 3)
```

Writable patterns contain distinct coordinates, with no constants. Assign a
scalar to a single coordinate, or a list/vector matching the pattern's length.
All indices, selectors, and values are checked before any coordinate changes.

```lisp
(let* ((velocity (px:make-vector2 3 4))
       (direction (px.math:normalize velocity))
       (next (px.math:add '(10 20) (px.math:multiply direction 5))))
  (px.math:components next)) ; => (13 24)
```

`length`, `length-squared`, `dot`, `cross`, `distance-to`, `normalize`,
`rotate`, `angle-to`, `reflect`, and `project` provide common geometry.
`lerp` accepts either two real scalars or two vectors, and `slerp` interpolates
vectors; both require an amount from 0 through 1. `round-vector` returns a new
Vector2/Vector3 rounded to a requested number of decimal digits (negative digits
round to tens, hundreds, and so on). Exact halfway values round away from zero,
matching pygame. Normalizing, projecting
onto, or finding the angle of a zero vector signals an error. `as-polar` and
`as-spherical` return multiple values; their inverse functions construct a
vector from those coordinates.

`move-towards` returns a fresh vector moved toward a target by at most a
distance; `move-towards-ip` updates the receiver. Both support 2D and 3D
vectors and sequence targets. Positive distances stop at the target without
overshooting, negative distances move away, and coincident inputs stay put.
Combine this with `clamp-magnitude` or `clamp-magnitude-ip` for speed limits
(the optional minimum follows the required maximum).

```lisp
;; SPEED is pixels per second; DT is the frame duration in seconds.
(px.math:move-towards-ip position mouse-position (* speed dt))
(px.math:clamp-magnitude-ip velocity 250)
```

`scale-to-length` sets a vector's length in place and returns it; negative
lengths reverse direction. A zero vector has no direction for a nonzero
requested length. `update-vector` replaces all components, accepting separate
values, a list/vector, or a single repeated scalar. Failed updates do not
partially mutate the receiver.

`rotate-rad` and `rotate-rad-ip` accept radians with the same Vector2/Vector3
axis rules as degree rotation. Vector3 also has `rotate-x/y/z-ip` in degrees,
`rotate-x/y/z-rad` for copies, and corresponding `-rad-ip` forms. Scalar
`px.math:clamp` limits a real value to a lower and upper bound. Like pygame,
it tests the lower bound first; reversed bounds are not reordered.

```lisp
(px.math:scale-to-length velocity 180)
(px.math:rotate-z-rad-ip direction (/ pi 2))
(px.math:update-vector position #(40 80))
(px.math:clamp health 0 100)
```

## Sprites and groups

Sprites are CLOS instances intended for subclassing. A sprite has an `image`,
position `rect`, optional collision `mask` and `radius`, visibility, dirty
state, and layer. `make-sprite` sets the rectangle from the image when no rect
is supplied. Override `px.sprite:update` to add game behavior.

Groups keep membership in insertion order. `ordered-group` is provided as an
explicit ordered variant; layered groups draw in ascending layer order, and
`change-layer` changes that sprite's order in that group only. Adding a sprite
to more than one group is supported. `kill` removes it from all groups but does
not dispose its image. Group updates use a snapshot, so membership changes
during an update callback are safe.

`group-single` is a group that keeps its most recently added sprite. Construct
one with `make-group-single`; `single-sprite` returns its member or NIL, and
supports `setf` to replace it or clear with NIL. Replacement updates both
sides of membership without disposing the old sprite's image. Copies retain
the class and share the sprite while keeping independent membership.
`get-top-sprite`/`get-bottom-sprite` return the last/first sprite in draw order,
or NIL for an empty group.
`get-sprite` reads a group's draw-order sequence by index; negative indices
count backward from the end, so `-1` selects the last sprite.

```lisp
(defclass player (px.sprite:sprite) ())
(defmethod px.sprite:update ((item player) &optional (dx 1))
  (incf (px:rect-x (px.sprite:rect item)) dx))

(let* ((hero (px:make-sprite :image image :layer 1))
       (actors (px.sprite:make-layered-group hero)))
  (px.sprite:update actors 2)
  (px.sprite:draw actors screen))
```

`draw` blits visible images and returns their affected rectangles. A
`layered-dirty-group` tracks old bounds and redraws its group when sprites move
or visibility changes; pass a background surface or restoration callback to
`draw`/`clear` to erase prior pixels. Collision helpers include rectangle,
circle, and mask tests; `sprite-collide` and `group-collide` accept a custom
collision predicate.

Dirty groups expose `get-clip`/`set-clip` and `repaint-rect`. The clip getter
returns a copy; the setter copies its rectangle, and NIL removes the extra clip.
The group clip intersects the target surface's clip and is restored after a
group operation. Changing the group clip forces a redraw; with a background,
the newly permitted area is refreshed so widening the clip clears old pixels.
Pixels outside the current clip remain untouched. `repaint-rect` copies
the supplied rectangle, restores that background region, and requests a group
redraw; use it after painting over a static background while sprites in the
region remain stationary.

A dirty-group update restores prior sprite bounds, pending erasures, and queued
repaint rectangles, then redraws all visible members in draw order to preserve
overlap. Its returned damage rectangles are clipped to the effective target
and group clip. This rebuild reports broader damage than pygame's optimized
rectangle updates. If a restoration callback signals, the group keeps a full
redraw pending so a later `draw` can retry.

```lisp
(px.surface:fill background "tomato" '(90 105 300 105))
(px.sprite:repaint-rect actors '(90 105 300 105))
(px.sprite:set-clip actors '(140 75 240 160))
(px.sprite:draw actors screen background)
```

Sprite constructors accept `:blend-flags`, and the settable `blend-flags`
property controls the surface `:special-flags` used by group drawing. Changing
it marks a clean sprite dirty so stationary effects are redrawn too.

Sprite constructors also accept `:source-rect` to sample a region of the image,
such as one frame of a sprite sheet. NIL samples the whole image. `source-rect`
supports `setf` and copies rectangles on both input and output; changing a crop
marks the sprite dirty. The crop uses image coordinates, while the sprite's
`rect` still determines the destination origin and collision bounds. Image and
destination clips follow the normal surface blit rules. Crops work with all
Pixelisp group types; pygame exposes this property through DirtySprite.

```lisp
(let ((actor (px.sprite:make-sprite :image sheet :rect (px:make-rect 100 80 32 32)
                                   :source-rect '(64 0 32 32))))
  ;; Advance to the fourth frame without changing the actor's screen position.
  (setf (px.sprite:source-rect actor) '(96 0 32 32)))
```

`make-render-updates-group` provides pygame's RenderUpdates behavior. It draws
in insertion order and returns damage for current and previous painted bounds.
Overlapping old/new bounds are united; disjoint bounds remain separate. Removed
and hidden sprites contribute their former painted regions. Call `clear` with
a background before drawing to restore prior pixels; damage reporting alone
does not erase them. The optional background argument to `draw` performs that
clear. Failed blits preserve pending damage so a later draw can retry.

```lisp
(px.sprite:clear actors screen background)
(let ((damage (px.sprite:draw actors screen)))
  ;; UPDATE with NIL presents the whole frame, so skip it when nothing changed.
  (when damage (px.display:update damage)))
```

## Surface lifetime

Surfaces are resources. Prefer `px.surface:with-surface` for short-lived
surfaces; for a transformed surface or mask output that outlives a local
operation, dispose it with `pixelisp:dispose` when finished. Masks and vectors
are ordinary Lisp values and need no disposal.
