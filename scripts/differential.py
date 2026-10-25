#!/usr/bin/env python3
"""Compare selected native-Lisp fixtures against pygame 2.6.1.

Run from any directory. Python/pygame are optional test tools, never library
runtime dependencies. Keep cases small and deterministic so a mismatch points
to an observable semantic difference rather than a renderer or screenshot.
"""
import json
from io import BytesIO
import os
from pathlib import Path
import subprocess

os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")
os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
os.environ.setdefault("SDL_AUDIODRIVER", "dummy")
import pygame

ROOT = Path(__file__).resolve().parent.parent
CASE_NAMES = [
    "exclusive rectangle edges", "rectangle clipping", "horizontal flip",
    "quarter-turn rotation", "alpha mask threshold", "mask overlap point",
    "mask overlap area", "raw copy under zero alpha", "zero-radius circle",
    "channel blend effects", "premultiplied alpha", "rectangle fitting",
    "line clipping", "vector movement", "color conversions",
    "surface layout queries", "mask painting", "Laplacian interior responses", "single-sprite groups",
    "named color palette", "color inputs", "per-color effects and updates",
    "rectangle scaling and mutation", "object collisions", "vector update and rotation",
    "captured audio completions",
    "Color arithmetic", "I1I2I3 conversion", "event filtering",
    "weighted pixel matching", "pixel transpose", "surface batching and anchors",
    "keyboard repeat settings",
    "scalar lerp and vector rounding",
    "rectangle update shapes",
    "image load from bytes",
    "screensaver controls",
    "layered sprite lookup",
    "layered dirty clip and repaint",
    "vector component indexing", "vector swizzles", "surface buffer views",
    "padded surface views", "controller event switch",
]


def red_values(surface):
    return [surface.get_at((x, y)).r
            for y in range(surface.get_height())
            for x in range(surface.get_width())]


def channel_blends():
    source = pygame.Surface((1, 1), pygame.SRCALPHA, 32)
    target = pygame.Surface((1, 1), pygame.SRCALPHA, 32)
    source.fill((200, 50, 128, 40))
    source.set_alpha(3)
    source.set_colorkey((200, 50, 128))
    results = []
    for flag in [pygame.BLEND_RGB_ADD, pygame.BLEND_RGB_SUB, pygame.BLEND_RGB_MULT,
                 pygame.BLEND_RGB_MIN, pygame.BLEND_RGB_MAX, pygame.BLEND_RGBA_ADD,
                 pygame.BLEND_RGBA_SUB, pygame.BLEND_RGBA_MULT, pygame.BLEND_RGBA_MIN,
                 pygame.BLEND_RGBA_MAX]:
        target.fill((100, 80, 60, 120))
        target.blit(source, (0, 0), special_flags=flag)
        results.append(list(target.get_at((0, 0))))
    return results


def premultiplied_alpha():
    source = pygame.Surface((3, 1), pygame.SRCALPHA, 32)
    for x, alpha in enumerate([0, 128, 255]):
        source.set_at((x, 0), (200, 50, 128, alpha))
    converted = source.premul_alpha()
    target = pygame.Surface((3, 1), pygame.SRCALPHA, 32)
    target.fill((100, 80, 60, 120))
    target.blit(converted, (0, 0), special_flags=pygame.BLEND_PREMULTIPLIED)
    return [[list(surface.get_at((x, 0))) for x in range(3)]
            for surface in [converted, target]]


def clipped_lines():
    cases = [((0, 0, 10, 10), (-3.9, -1.9, 3.9, 8.9)),
             ((0, 0, 10, 10), (3.9, -1.9, -3.9, 8.9)),
             ((5, 5, -10, 10), (-10, 7, 10, 7)),
             ((0, 0, 10, 10), (10, 0, 10, 10))]
    return [[list(point) for point in pygame.Rect(rect).clipline(line)]
            for rect, line in cases]


def color_conversions():
    color = pygame.Color(128, 64, 32, 99)
    color.hsva = (120, 50, 50, 50)
    results = [list(color)]
    color.hsla = (210, 33.3, 45.5, 99.9)
    results.append(list(color))
    color.cmy = (0.5, 0.125, 0.875)
    results.append(list(color))
    results.append(list(pygame.Color(128, 64, 32, 99).correct_gamma(0.5)))
    return results


def pixel_colors(surface):
    return [list(surface.get_at((x, y)))
            for y in range(surface.get_height()) for x in range(surface.get_width())]


def surface_details():
    root = pygame.Surface((12, 8), pygame.SRCALPHA, 32)
    child = root.subsurface((3, 2, 6, 5))
    grandchild = child.subsurface((1, 2, 2, 2))
    return [list(grandchild.get_offset()), list(grandchild.get_abs_offset()),
            grandchild.get_pitch(), grandchild.get_bitsize(), grandchild.get_bytesize(),
            list(root.unmap_rgb(root.map_rgb((17, 34, 51, 68))))]


def mask_painting():
    mask = pygame.mask.Mask((3, 2))
    for point in [(0, 0), (2, 0), (1, 1)]:
        mask.set_at(point)
    target = pygame.Surface((4, 3), pygame.SRCALPHA, 32)
    plane = pygame.Surface((1, 1), pygame.SRCALPHA, 32)
    target.fill((8, 16, 24, 32))
    plane.fill((17, 29, 41, 0))
    target.set_clip((1, 1, 3, 2))
    mask.to_surface(surface=target, setsurface=plane, dest=(1, 1),
                    setcolor=(90, 80, 70, 60), unsetcolor=None)
    return pixel_colors(target)


def laplacian():
    source = pygame.Surface((3, 3), pygame.SRCALPHA, 32)
    source.set_at((1, 1), (20, 30, 40, 50))
    edges = pygame.transform.laplacian(source)
    source.fill((255, 255, 255, 255))
    flat = pygame.transform.laplacian(source)
    # pygame 2.6.1 in this environment produces varying corner pixels; only
    # interior samples are a deterministic differential reference.
    return [list(edges.get_at((1, 1))), list(flat.get_at((1, 1)))]


def single_group():
    first, second = pygame.sprite.Sprite(), pygame.sprite.Sprite()
    group = pygame.sprite.GroupSingle(first)
    group.add(second)
    result = [int(group.sprite is second), int(first.alive())]
    group.sprite = first
    result.append(int(second.alive()))
    first.kill()
    result.append(len(group))
    return result


def named_palette():
    from pygame.colordict import THECOLORS
    return [list(pygame.Color(name)) for name in sorted(THECOLORS)]


def color_operations():
    color = pygame.Color(200, 50, 128, 128)
    result = [list(color.grayscale()), list(color.premul_alpha())]
    color.update(1, 2, 3)
    result.append(list(color))
    color.update((4, 5, 6))
    result.append(list(color))
    result.append(int(pygame.Color('#10203040')))
    return result


def rect_tools():
    rect = pygame.Rect(5, 8, 5, 3)
    result = [list(rect.scale_by(2, 0.5)), list(rect.scale_by(-2)), list(rect.scale_by(1, 0))]
    rect.centerx, rect.centery = 20, -5
    result.append(list(rect))
    rect.clamp_ip((0, 0, 30, 30))
    result.append(list(rect))
    return result


def object_collisions():
    bounds = pygame.Rect(0, 0, 10, 10)
    objects = [(1, pygame.Rect(2, 2, 1, 1)), (2, pygame.Rect(10, 0, 1, 1)),
               (3, pygame.Rect(9, 9, 2, 2))]
    return [bounds.collideobjects(objects, key=lambda item: item[1])[0],
            [item[0] for item in bounds.collideobjectsall(objects, key=lambda item: item[1])],
            sorted(item[0] for item in bounds.collidedictall(dict(objects), 1))]


def vector_api():
    vector = pygame.Vector2(3, 4)
    vector.scale_to_length(10)
    result = [[round(component) for component in vector],
              [round(component) for component in vector.rotate_rad(3.141592653589793 / 2)]]
    vector.update((7, 8))
    result.append(list(vector))
    result.append([round(component) for component in pygame.Vector3(0, 0, 1).rotate_y_rad(3.141592653589793 / 2)])
    result.append(pygame.math.clamp(5, 10, 0))
    return result


def audio_completions():
    pygame.display.init()
    pygame.mixer.init(frequency=22050, size=-16, channels=1, buffer=256)
    try:
        sound = pygame.mixer.Sound(buffer=bytes(4410))
        channel = pygame.mixer.Channel(0)
        kind = pygame.event.custom_type()
        channel.set_endevent(kind)
        for _ in range(2):
            channel.play(sound)
            channel.stop()
        channel.set_endevent(0)
        events = pygame.event.get(kind)
        return [len(events), [event.code for event in events]]
    finally:
        pygame.mixer.quit()
        pygame.display.quit()


def color_arithmetic():
    left, right = pygame.Color(250, 10, 80, 200), pygame.Color(20, 30, 40, 100)
    divisor = pygame.Color(0, 3, 7, 0)
    return [list(color) for color in [left + right, left - right, left * right,
                                     ~left, left // divisor, left % divisor]]


def i1i2i3():
    color = pygame.Color(128, 64, 32, 77)
    result = [[round(component * 1000000) for component in color.i1i2i3]]
    color.i1i2i3 = (0.5, 0.25, 0)
    result.append(list(color))
    return result


def event_filtering():
    pygame.display.init()
    first, second = pygame.event.custom_type(), pygame.event.custom_type()
    try:
        pygame.event.clear()
        pygame.event.post(pygame.event.Event(first))
        pygame.event.set_blocked(first)
        return [int(pygame.event.get_blocked(first)),
                int(pygame.event.get_blocked([first, second])),
                int(pygame.event.post(pygame.event.Event(first))),
                int(pygame.event.post(pygame.event.Event(second))),
                len(pygame.event.get([first, second]))]
    finally:
        pygame.event.set_allowed([first, second])
        pygame.display.quit()


def pixel_distance():
    surface = pygame.Surface((4, 1), pygame.SRCALPHA, 32)
    for x, color in enumerate([(100, 100, 100, 255), (120, 100, 100, 0),
                                (100, 120, 100, 255), (100, 100, 120, 128)]):
        surface.set_at((x, 0), color)
    selected = []
    with pygame.PixelArray(surface) as pixels:
        for weights in [(1, 0, 0), (0, 1, 0), (0, 0, 1)]:
            with pixels.extract((100, 100, 100, 255), 0.05, weights) as matches:
                selected.append([int(matches.surface.unmap_rgb(matches[x, 0]).r > 0)
                                 for x in range(4)])
        pixels.replace((100, 100, 100, 255), pygame.Color('gold'), 0.05, (10, 0, 0))
    return [selected, pixel_colors(surface)]


def pixel_transpose():
    surface = pygame.Surface((3, 2), pygame.SRCALPHA, 32)
    for y in range(2):
        for x in range(3):
            surface.set_at((x, y), (1 + x + y * 3, 0, 0, 255))
    with pygame.PixelArray(surface) as pixels:
        with pixels.transpose() as turned:
            return [list(turned.shape), list(turned.strides), red_values(turned.make_surface())]


def surface_batch():
    masks = (255, 65280, 16711680, 4278190080)
    target = pygame.Surface((4, 1), pygame.SRCALPHA, 32, masks)
    source = pygame.Surface((2, 1), pygame.SRCALPHA, 32, masks)
    source.set_at((0, 0), (10, 0, 0, 255))
    source.set_at((1, 0), (20, 0, 0, 255))
    target.fill((5, 0, 0, 255))
    target.set_clip((1, 0, 1, 1))
    damage = target.blits([(source, (0, 0), (0, 0, 2, 1)),
                           (source, (1, 0), (0, 0, 1, 1), pygame.BLEND_RGB_ADD)])
    return [[list(rect) for rect in damage], pixel_colors(target),
            list(source.get_shifts()), list(source.get_losses()),
            list(source.get_rect(midtop=(10, 20)))]


def key_repeat_settings():
    pygame.display.init()
    try:
        result = [list(pygame.key.get_repeat())]
        for args in [(80,), (10, 5), (0, 200), ()]:
            pygame.key.set_repeat(*args)
            result.append(list(pygame.key.get_repeat()))
        return result
    finally:
        pygame.display.quit()


def math_rounding():
    # Scale the decimal results before serialization so fixtures stay integers.
    rounded = [round(pygame.Vector2(2.5, -3.5)),
               round(pygame.Vector2(25, -35), -1),
               round(pygame.Vector2(2.675, -2.675), 2)]
    return [int(pygame.math.lerp(10, 20, 0.5)),
            [list(map(int, rounded[0])), list(map(int, rounded[1])),
             [int(round(component * 100)) for component in rounded[2]]]]


def rect_update_shapes():
    rect = pygame.Rect(0, 0, 1, 1)
    results = []
    for args in [(1, 2, 3, 4), ((5, 6, 7, 8),), ((9, 10), (11, 12))]:
        rect.update(*args)
        results.append(list(rect))
    return results


def image_from_bytes():
    # Self-contained 2x2 PNG fixture; no example files are required.
    png = bytes([
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 2,
        0, 0, 0, 2, 8, 6, 0, 0, 0, 114, 182, 13, 36, 0, 0, 0, 24, 73, 68, 65, 84,
        8, 153, 5, 193, 129, 1, 0, 0, 4, 192, 160, 248, 220, 229, 83, 34, 105, 71,
        226, 30, 63, 110, 6, 127, 136, 97, 48, 18, 0, 0, 0, 0, 73, 69, 78, 68, 174,
        66, 96, 130,
    ])
    image = pygame.image.load(BytesIO(png), "icon.png")
    return [list(image.get_size()), pixel_colors(image)]


def screensaver_controls():
    """Compare explicit allow/inhibit states, then restore the host setting."""
    pygame.display.init()
    original = pygame.display.get_allow_screensaver()
    try:
        states = []
        for allow in (False, True, False):
            pygame.display.set_allow_screensaver(allow)
            states.append(int(pygame.display.get_allow_screensaver()))
        return states
    finally:
        pygame.display.set_allow_screensaver(original)
        pygame.display.quit()


def layered_sprite_lookup():
    """Return stable sprite IDs at positive and negative draw-order indices."""
    group = pygame.sprite.LayeredUpdates()

    class IdentifiedSprite(pygame.sprite.Sprite):
        def __init__(self, sprite_id):
            super().__init__()
            self.sprite_id = sprite_id

    sprites = [IdentifiedSprite(index) for index in range(4)]
    for sprite, layer in zip(sprites, (1, -1, 1, 0)):
        group.add(sprite, layer=layer)
    indices = (0, 1, 2, 3, -1, -2, -3, -4)

    def ids_at_indices():
        return [group.get_sprite(index).sprite_id for index in indices]

    before = ids_at_indices()
    group.change_layer(sprites[2], -1)
    return [before, ids_at_indices()]


def layered_dirty_clip_repaint():
    """Compare pixels after background repaint and clipped/full redraws."""
    # Pygame uses the display bounds when LayeredDirty.set_clip(None) resets
    # its clip, so make the dummy display match these tiny test surfaces.
    pygame.display.set_mode((5, 2))
    target = pygame.Surface((5, 2))
    background = pygame.Surface((5, 2))
    target.fill((10, 0, 0))
    background.fill((10, 0, 0))

    first_image = pygame.Surface((2, 1))
    first_image.fill((200, 0, 0))
    second_image = pygame.Surface((2, 1))
    second_image.fill((80, 0, 0))

    first = pygame.sprite.DirtySprite()
    first.image, first.rect = first_image, first_image.get_rect(topleft=(1, 0))
    second = pygame.sprite.DirtySprite()
    second.image, second.rect = second_image, second_image.get_rect(topleft=(2, 0))
    group = pygame.sprite.LayeredDirty(first, second)
    group.change_layer(first, 0)
    group.change_layer(second, 1)
    group.clear(target, background)
    group.draw(target)
    result = [pixel_colors(target)]

    # The sprites are clean here; repaint only the edited background pixel.
    background.fill((40, 0, 0), (0, 1, 1, 1))
    group.repaint_rect(pygame.Rect(0, 1, 1, 1))
    group.draw(target)
    result.append(pixel_colors(target))

    # A narrow clip limits the repaint to one overlap pixel. Resetting the
    # clip forces the full tiny surface to reflect the latest background.
    background.fill((60, 0, 0), (1, 0, 4, 1))
    group.set_clip(pygame.Rect(2, 0, 1, 1))
    group.repaint_rect(pygame.Rect(1, 0, 4, 1))
    group.draw(target)
    result.extend([list(group.get_clip()), pixel_colors(target)])
    group.set_clip(None)
    group.repaint_rect(pygame.Rect(0, 0, 5, 2))
    group.draw(target)
    result.append(pixel_colors(target))
    pygame.display.quit()
    return result


def vector_indexing():
    two, three = pygame.Vector2(3, 4), pygame.Vector3(5, 6, 7)
    reads = [[int(two[i]) for i in (0, 1, -1, -2)],
             [int(three[i]) for i in (0, 1, 2, -1, -2, -3)]]
    two[-1], three[-3] = 9, 11
    errors = []
    for index in (3, -4):
        try:
            three[index]
            errors.append(0)
        except IndexError:
            errors.append(1)
    return reads + [list(two), list(three), errors]


def vector_swizzles():
    two, three = pygame.Vector2(3, 4), pygame.Vector3(5, 6, 7)
    reads = [two.x, list(two.yx), list(two.xyx), list(two.xy01), list(three.zxy10)]
    two.xy, three.zx = two.yx, (11, 12)
    after = [list(two), list(three)]
    duplicate = 0
    try:
        three.xx = (40, 50)
    except AttributeError:
        duplicate = 1
    errors = []
    for pattern in ('z', '', '01'):
        try:
            getattr(two, pattern)
            errors.append(0)
        except AttributeError:
            errors.append(1)
    return [reads] + after + [duplicate, list(three), errors]


def rgba_surface(size):
    # Explicit masks match Pixelisp's public native layout for raw-byte checks.
    return pygame.Surface(size, pygame.SRCALPHA, 32,
                          (0xff, 0xff00, 0xff0000, 0xff000000))


def surface_buffer_views():
    surface = rgba_surface((2, 2))
    surface.fill((10, 20, 30, 40))
    views = [memoryview(surface.get_buffer())]
    views += [memoryview(surface.get_view(kind)) for kind in ('0', '1', '2', '3', 'g', 'A')]
    buffer, raw, linear, packed, rgb, green, alpha = views
    try:
        raw[0], green[1, 1], alpha[0, 0] = 99, 77, 160
        result = [list(buffer.shape), list(raw.shape), list(linear.shape),
                  list(packed.shape), list(rgb.shape), list(rgb.strides),
                  rgb[0, 0, 0], green[1, 1],
                  [list(surface.get_at((x, y))) for y in range(2) for x in range(2)],
                  int(surface.get_locked())]
    finally:
        for view in reversed(views):
            view.release()
    return result + [int(surface.get_locked())]


def padded_surface_views():
    parent = rgba_surface((4, 4))
    parent.fill((0, 0, 0, 0))
    child = parent.subsurface((1, 0, 2, 2))
    errors = []
    for kind in ('0', '1'):
        try:
            view = memoryview(child.get_view(kind))
            view.release()
            errors.append(0)
        except ValueError:
            errors.append(1)
    views = [memoryview(child.get_buffer()), memoryview(child.get_view('2')),
             memoryview(child.get_view('r'))]
    buffer, packed, red = views
    try:
        red[0, 1] = 88
        return [errors, list(buffer.shape), list(packed.shape), list(packed.strides),
                parent.get_at((1, 1)).r]
    finally:
        for view in reversed(views):
            view.release()


def controller_event_switch():
    from pygame._sdl2 import controller
    controller.init()
    previous = controller.get_eventstate()
    try:
        states = []
        for enabled in (False, True, False):
            controller.set_eventstate(enabled)
            states.append(int(controller.get_eventstate()))
        return states + [int(controller.name_forindex(controller.get_count() + 10) is None)]
    finally:
        controller.set_eventstate(previous)
        controller.quit()


def reference():
    source = pygame.Surface((2, 2), pygame.SRCALPHA, 32)
    for index, pixel in enumerate([
        (10, 2, 3, 127), (20, 5, 6, 128),
        (30, 8, 9, 255), (40, 11, 12, 0),
    ]):
        source.set_at((index % 2, index // 2), pixel)
    rect = pygame.Rect(10, 20, 30, 40)
    mask = pygame.mask.from_surface(source)
    other = pygame.mask.Mask((2, 2), fill=True)
    circle = pygame.Surface((3, 3), pygame.SRCALPHA, 32)
    circle.fill((1, 2, 3, 4))
    damage = pygame.draw.circle(circle, (255, 255, 0), (1, 1), 0)
    return [
        [int(rect.collidepoint(point))
         for point in [(10, 20), (40, 20), (10, 60), (39, 59)]],
        list(pygame.Rect(-2, 1, 4, 3).clip(pygame.Rect(0, 0, 3, 3))),
        red_values(pygame.transform.flip(source, True, False)),
        red_values(pygame.transform.rotate(source, 90)),
        [mask.get_at((x, y)) for y in range(2) for x in range(2)],
        list(mask.overlap(other, (1, 0))),
        mask.overlap_area(other, (1, 0)),
        list(source.copy().get_at((1, 1))),
        [damage.width, damage.height, list(circle.get_at((1, 1)))],
        channel_blends(),
        premultiplied_alpha(),
        [list(pygame.Rect(0, 0, *size).fit((1, 1, 8, 8)))
         for size in [(3, 2), (2, 3), (-5, 3), (5, -3), (0, 5)]],
        clipped_lines(),
        [list(pygame.Vector2(0, 0).move_towards((3, 4), distance))
         for distance in [5, -5, 100]],
        color_conversions(),
        surface_details(),
        mask_painting(),
        laplacian(),
        single_group(),
        named_palette(),
        [list(pygame.Color(value)) for value in
         ['Dark Slate Gray', 'grey42', '#102030', '0x10203040', 0x01020304, (1, 2, 3)]],
        color_operations(),
        rect_tools(),
        object_collisions(),
        vector_api(),
        audio_completions(),
        color_arithmetic(),
        i1i2i3(),
        event_filtering(),
        pixel_distance(),
        pixel_transpose(),
        surface_batch(),
        key_repeat_settings(),
        math_rounding(),
        rect_update_shapes(),
        image_from_bytes(),
        screensaver_controls(),
        layered_sprite_lookup(),
        layered_dirty_clip_repaint(),
        vector_indexing(), vector_swizzles(), surface_buffer_views(),
        padded_surface_views(), controller_event_switch(),
    ]


def main():
    if pygame.version.ver != "2.6.1":
        raise SystemExit(f"Expected pygame 2.6.1, found {pygame.version.ver}")
    result = subprocess.run(
        ["sbcl", "--no-userinit", "--script", str(ROOT / "scripts/reference-fixtures.lisp")],
        cwd=ROOT, env=os.environ, text=True, capture_output=True, timeout=60,
    )
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    output = next((line.removeprefix("PIXELISP_FIXTURE ")
                   for line in result.stdout.splitlines()
                   if line.startswith("PIXELISP_FIXTURE ")), None)
    if output is None:
        raise SystemExit("Lisp fixture did not emit its JSON result")
    actual, expected = json.loads(output), reference()
    if len(actual) != len(CASE_NAMES) or len(expected) != len(CASE_NAMES):
        raise SystemExit("Fixture counts do not match the named reference cases")
    failed = []
    for name, got, wanted in zip(CASE_NAMES, actual, expected):
        if got != wanted:
            failed.append(f"{name}: Pixelisp={got!r}; pygame={wanted!r}")
    if failed:
        raise SystemExit("\n".join(failed))
    print(f"{len(CASE_NAMES)} differential fixtures passed against pygame {pygame.version.ver}")


if __name__ == "__main__":
    main()
