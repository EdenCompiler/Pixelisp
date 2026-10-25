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
import wave

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
    "surface layout queries", "mask painting", "mask rectangle anchors", "Laplacian interior responses", "single-sprite groups",
    "named color palette", "color inputs", "per-color effects and updates",
    "rectangle scaling and mutation", "object collisions", "vector update and rotation",
    "captured audio completions",
    "Color arithmetic", "I1I2I3 conversion", "event filtering",
    "event selection without pumping",
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
    "SDL2 renderer targets and controls", "SDL2 texture partial update",
    "SDL2 texture rotation origin", "SDL2 nested image atlas rectangles",
    "SDL2 image modulation pixels", "RLE colorkey alpha and post-blit lock state",
    "custom SDL blend modes", "FreeType face information", "FreeType style flags",
    "SDL2 renderer blitting", "FreeType layout controls", "FreeType baseline ink bounds",
    "premultiplied image bytes", "encoded sound memory", "FreeType independent size axes",
    "encoded image output", "music memory playback", "FreeType retained text and bitmap settings",
]


def encoded_image_output():
    surface = pygame.Surface((2, 2), pygame.SRCALPHA, 32)
    for index, pixel in enumerate([(220, 10, 30, 0), (40, 200, 60, 64),
                                   (70, 80, 190, 128), (100, 110, 120, 255)]):
        surface.set_at((index % 2, index // 2), pixel)
    result = []
    for kind in ["png", "bmp"]:
        output = BytesIO()
        pygame.image.save(surface, output, kind)
        output.seek(0)
        decoded = pygame.image.load(output, kind)
        result.append([list(decoded.get_at((x, y))) for y in range(2) for x in range(2)])
    # Compare decoded pixels, since the TGA writers choose different compression.
    opaque = pygame.Surface((2, 1), 0, 32)
    opaque.set_at((0, 0), (10, 20, 30))
    opaque.set_at((1, 0), (40, 50, 60))
    output = BytesIO()
    pygame.image.save(opaque, output, "tga")
    output.seek(0)
    decoded = pygame.image.load(output, "tga")
    result.append([list(decoded.get_at((x, 0))) for x in range(2)])
    return result


def music_memory_playback():
    output = BytesIO()
    with wave.open(output, "wb") as asset:
        asset.setparams((1, 2, 22050, 0, "NONE", "not compressed"))
        asset.writeframes(bytes([0x34, 0x12, 0xDC, 0xFE]) * 128)
    pygame.mixer.quit()
    pygame.mixer.init(22050, -16, 1)
    try:
        pygame.mixer.music.load(BytesIO(output.getvalue()), "wav")
        states = [int(pygame.mixer.music.get_busy())]
        pygame.mixer.music.play(-1)
        states.append(int(pygame.mixer.music.get_busy()))
        pygame.mixer.music.pause()
        states.append(int(pygame.mixer.music.get_busy()))
        pygame.mixer.music.unpause()
        states.append(int(pygame.mixer.music.get_busy()))
        pygame.mixer.music.queue(BytesIO(output.getvalue()), "wav", loops=1)
        pygame.mixer.music.stop()
        states.append(int(pygame.mixer.music.get_busy()))
        pygame.mixer.music.unload()
        states.append(int(pygame.mixer.music.get_busy()))
        return states
    finally:
        pygame.mixer.quit()


def freetype_retained_text():
    font = pygame.freetype.Font(str(ROOT / "assets/fonts/DejaVuSans.ttf"), 24)
    results = [int(not any(font.render_raw(None)[0])), int(font.use_bitmap_strikes)]
    expected = font.render_raw("Replay", size=28, rotation=15)
    # Compare immediate reuse. In the local pygame 2.6.1 build, inserting
    # get_metrics() here corrupts the rotated-layout cache and can crash Python.
    # Pixelisp tests independently verify that metric queries preserve its text.
    results.append(int(expected == font.render_raw(None, size=28, rotation=15)))
    font.use_bitmap_strikes = False
    results.append(int(font.use_bitmap_strikes))
    font.render_raw("Next")
    results.append(int(font.render_raw(None) == font.render_raw("Next")))
    return results


def premultiplied_image_bytes():
    surface = pygame.Surface((2, 2), pygame.SRCALPHA, 32)
    for index, alpha in enumerate([0, 1, 128, 254]):
        surface.set_at((index % 2, index // 2), (200, 51, 129, alpha))
    # Blanket alpha, keys, and the drawing clip must not change raw export.
    surface.set_alpha(17)
    surface.set_colorkey((200, 51, 129))
    surface.set_clip((1, 0, 1, 1))
    return [list(pygame.image.tobytes(surface, fmt, flipped))
            for fmt in ["RGBA_PREMULT", "ARGB_PREMULT"]
            for flipped in [False, True]]


def encoded_sound_memory():
    pcm = bytes([0x34, 0x12, 0xDC, 0xFE, 0, 0, 0xFF, 0x7F])
    output = BytesIO()
    with wave.open(output, "wb") as asset:
        asset.setparams((1, 2, 22050, 0, "NONE", "not compressed"))
        asset.writeframes(pcm)
    pygame.mixer.quit()
    pygame.mixer.init(22050, -16, 1)
    try:
        stream = BytesIO(b"prefix" + output.getvalue())
        stream.seek(6)
        sound = pygame.mixer.Sound(file=stream)
        # Stream ownership is a documented Lisp adaptation; compare the audio.
        return list(sound.get_raw())
    finally:
        pygame.mixer.quit()


def freetype_independent_size_axes():
    font = pygame.freetype.Font(str(ROOT / "assets/fonts/DejaVuSans.ttf"), (14, 30))
    metrics = [list(map(round, font.get_metrics("A", size=size)[0]))
               for size in [(14, 30), (28, 30), (14, 15), (24, 0)]]
    return [metrics, list(map(round, font.size))]


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


def mask_rect_anchors():
    """Rect anchors on odd and empty masks, including sequential assignments."""
    odd = pygame.mask.Mask((5, 3))
    return [list(odd.get_rect(center=pygame.Vector2(10, 5))),
            list(odd.get_rect(topleft=[2, 4])),
            list(odd.get_rect(right=10, bottom=9)),
            list(odd.get_rect(x=1, left=7)),
            list(pygame.mask.Mask((0, 0)).get_rect(center=(10, 5))),
            list(pygame.mask.Mask((0, 3)).get_rect(midbottom=(5, 8)))]


def custom_blend_modes():
    """Canonical and custom factor/operation combinations from SDL 2.32."""
    from pygame._sdl2.video import Renderer
    modes = [((2, 1, 1), (2, 1, 1)),
             ((5, 6, 1), (2, 6, 1)),
             ((1, 2, 1), (1, 2, 1)),
             ((3, 4, 2), (5, 6, 3)),
             ((10, 9, 5), (7, 8, 4)),
             ((1, 10, 2), (10, 1, 5))]
    return [Renderer.compose_custom_blend_mode(color, alpha)
            for color, alpha in modes]


def freetype_face_information():
    """Compare scalable outline metrics and one fixed-size BDF strike."""
    import pygame.freetype as freetype
    freetype.init()
    outline = freetype.Font(str(ROOT / "assets/fonts/DejaVuSans.ttf"), 20)
    bitmap = freetype.Font(str(ROOT / "tests/fixtures/tiny-mono.bdf"), 8)

    def information(font, size):
        strikes = [[point_size, height, width, round(x_ppem), round(y_ppem)]
                   for point_size, height, width, x_ppem, y_ppem in font.get_sizes()]
        return [int(font.scalable), int(font.fixed_width), font.fixed_sizes,
                font.height, font.ascender, font.descender,
                font.get_sized_glyph_height(size), strikes]

    return [information(outline, 20), information(bitmap, 8)]


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


def event_selection():
    """Compare custom-event include/exclude selection without native pumping."""
    pygame.display.init()
    first, excluded, third = [pygame.event.custom_type() for _ in range(3)]
    types = (first, excluded, third)

    def post(records):
        for kind, code in records:
            pygame.event.post(pygame.event.Event(kind, code=code))

    def codes(events):
        return [event.code for event in events if event.type in types]

    try:
        pygame.event.clear(pump=False)
        post([(first, 11), (excluded, 21), (first, 12), (third, 31), (excluded, 22)])
        without_excluded = codes(pygame.event.get(exclude=excluded, pump=False))
        excluded_remaining = codes(pygame.event.get([excluded], pump=False))

        pygame.event.clear(pump=False)
        post([(first, 11), (first, 12), (third, 31), (excluded, 21), (excluded, 22)])
        included = codes(pygame.event.get([first, third], pump=False))
        include_remaining = codes(pygame.event.get(pump=False))

        pygame.event.clear(pump=False)
        post([(first, 41), (excluded, 42), (first, 43)])
        conflict = 0
        try:
            pygame.event.get(first, pump=False, exclude=excluded)
        except pygame.error:
            conflict = 1
        conflict_preserved = codes(pygame.event.get(pump=False))
        return [without_excluded, excluded_remaining, included, include_remaining,
                conflict, conflict_preserved]
    finally:
        pygame.event.clear(pump=False)
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


def sdl2_renderer_targets_and_controls():
    from pygame._sdl2 import Window, Renderer, Texture
    window = Window("renderer fixture", size=(8, 8), hidden=True)
    renderer = Renderer(window, accelerated=False)
    try:
        renderer.logical_size = (4, 4)
        renderer.scale = (1.25, 1.5)
        renderer.set_viewport((1, 1, 6, 6))
        renderer.draw_blend_mode = pygame.BLENDMODE_ADD
        controls = [list(renderer.logical_size),
                    [round(axis * 100) for axis in renderer.scale],
                    list(renderer.get_viewport()), int(renderer.draw_blend_mode)]

        renderer.logical_size = (0, 0)
        renderer.scale = (1, 1)
        renderer.set_viewport(None)
        renderer.draw_blend_mode = pygame.BLENDMODE_NONE
        target = Texture(renderer, (4, 4), target=True)
        renderer.target = target
        renderer.draw_color = (0, 0, 0, 255)
        renderer.clear()
        renderer.draw_color = (240, 20, 10, 255)
        renderer.draw_rect((1, 1, 2, 2))
        target_pixels = pixel_colors(renderer.to_surface())

        renderer.target = None
        renderer.draw_color = (0, 40, 0, 255)
        renderer.clear()
        window_pixel = list(renderer.to_surface().get_at((0, 0)))
        return [controls, target_pixels, window_pixel]
    finally:
        renderer.target = None
        del target
        del renderer
        window.destroy()


def sdl2_texture_partial_update():
    from pygame._sdl2 import Window, Renderer, Texture
    window = Window("texture update fixture", size=(6, 4), hidden=True)
    renderer = Renderer(window, accelerated=False)
    try:
        base = pygame.Surface((3, 2), pygame.SRCALPHA, 32)
        base.fill((0, 0, 40, 255))
        texture = Texture.from_surface(renderer, base)
        patch = pygame.Surface((2, 1), pygame.SRCALPHA, 32)
        patch.set_at((0, 0), (240, 20, 10, 255))
        patch.set_at((1, 0), (10, 220, 30, 255))
        texture.update(patch, area=(1, 1, 2, 1))
        renderer.draw_color = (0, 0, 0, 255)
        renderer.clear()
        texture.draw(dstrect=(1, 1, 3, 2))
        return pixel_colors(renderer.to_surface())
    finally:
        del texture
        del renderer
        window.destroy()


def sdl2_texture_rotation_origin():
    from pygame._sdl2 import Window, Renderer, Texture
    window = Window("texture origin fixture", size=(8, 8), hidden=True)
    renderer = Renderer(window, accelerated=False)
    try:
        source = pygame.Surface((2, 1), pygame.SRCALPHA, 32)
        source.set_at((0, 0), (255, 0, 0, 255))
        source.set_at((1, 0), (0, 255, 0, 255))
        texture = Texture.from_surface(renderer, source)
        renderer.draw_color = (0, 0, 0, 255)
        renderer.clear()
        texture.draw(dstrect=(3, 3, 2, 1), angle=90, origin=(0, 0))
        image = renderer.to_surface()
        return [list(image.get_at(point)) for point in [(2, 3), (2, 4), (3, 3)]]
    finally:
        del texture
        del renderer
        window.destroy()


def sdl2_image_nested_rects():
    from pygame._sdl2 import Window, Renderer, Texture, Image
    window = Window("nested image rectangles", size=(8, 4), hidden=True)
    renderer = Renderer(window, accelerated=False)
    try:
        source = pygame.Surface((4, 1), pygame.SRCALPHA, 32)
        texture = Texture.from_surface(renderer, source)
        atlas = Image(texture)
        parent = Image(atlas, (1, 0, 3, 1))
        image = Image(parent, (1, 0, 2, 1))
        return [list(parent.srcrect), list(image.srcrect),
                list(image.get_rect(center=(5, 2)))]
    finally:
        del image
        del parent
        del atlas
        del texture
        del renderer
        window.destroy()


def sdl2_image_modulation_pixels():
    from pygame._sdl2 import Window, Renderer, Texture, Image
    window = Window("image modulation", size=(8, 3), hidden=True)
    renderer = Renderer(window, accelerated=False)
    try:
        source = pygame.Surface((4, 1), pygame.SRCALPHA, 32)
        for x, color in enumerate([(200, 10, 20, 255), (20, 200, 30, 255),
                                   (30, 40, 210, 255), (70, 80, 90, 255)]):
            source.set_at((x, 0), color)
        texture = Texture.from_surface(renderer, source)
        image = Image(Image(texture, (1, 0, 3, 1)), (1, 0, 2, 1))
        image.color = (255, 128, 255)
        image.alpha = 128
        image.blend_mode = pygame.BLEND_ADD
        renderer.draw_color = (0, 0, 0, 255)
        renderer.clear()
        image.draw(dstrect=(3, 1, 2, 1))
        image.draw(dstrect=(0, 1))
        pixels = renderer.to_surface()
        return [[list(pixels.get_at((x, 1))) for x in (0, 1, 3, 4)]]
    finally:
        del image
        del texture
        del renderer
        window.destroy()


def renderer_blitting():
    from pygame._sdl2 import Window, Renderer, Texture
    window = Window("renderer blit", size=(8, 4), hidden=True)
    renderer = Renderer(window, accelerated=False)
    source = pygame.Surface((4, 1), pygame.SRCALPHA, 32)
    for x, red in enumerate((10, 20, 30, 40)):
        source.set_at((x, 0), (red, 0, 0, 255))
    texture = Texture.from_surface(renderer, source)
    pixels = pygame.Surface((8, 4), pygame.SRCALPHA, 32)
    try:
        renderer.draw_color = (0, 0, 0, 255)
        renderer.clear()
        cropped = list(renderer.blit(texture, pygame.Rect(2, 1, 4, 1),
                                     pygame.Rect(1, 0, 2, 1), 42))
        renderer.to_surface(pixels)
        crop_row = [pixels.get_at((x, 1)).r for x in range(8)]
        renderer.clear()
        offscreen = list(renderer.blit(texture, pygame.Rect(-1, 0, 4, 1)))
        renderer.to_surface(pixels)
        offscreen_row = [pixels.get_at((x, 0)).r for x in range(8)]
        empty = list(renderer.blit(texture, pygame.Rect(2, 1, 0, 1)))
        renderer.set_viewport(pygame.Rect(1, 1, 4, 2))
        viewport = list(renderer.blit(texture, None))
        return [cropped, crop_row, offscreen, offscreen_row, empty, viewport]
    finally:
        del texture
        del renderer
        window.destroy()


def freetype_layout_controls():
    import pygame.freetype as ft
    ft.init()
    font = ft.Font(str(ROOT / "assets/fonts/DejaVuSans.ttf"), 24)
    normalized = []
    for angle in (-45, 725, 360):
        font.rotation = angle
        normalized.append(font.rotation)
    font.get_rect("L", rotation=90)
    unchanged = font.rotation
    font.vertical = True

    def rejected(style, rotation):
        try:
            font.render_raw("L", style=style, rotation=rotation)
            return 0
        except ValueError:
            return 1

    return [normalized, unchanged, int(font.vertical),
            rejected(ft.STYLE_WIDE, 90), rejected(ft.STYLE_UNDERLINE, 90),
            rejected(ft.STYLE_UNDERLINE, 0), font.style]


def freetype_baseline_ink_bounds():
    """Measure ink independently of each library's advance-padding policy."""
    import pygame.freetype as ft
    ft.init()
    font = ft.Font(str(ROOT / "assets/fonts/DejaVuSans.ttf"), 24)
    result = []
    for vertical in (False, True):
        font.vertical = vertical
        row = []
        for angle in (0, 90, 180, 270):
            mask, (width, height) = font.render_raw("L", rotation=angle)
            rect = font.get_rect("L", rotation=angle)
            points = [(x + rect.x, y - rect.y) for y in range(height)
                      for x in range(width) if mask[x + y * width]]
            xs, ys = zip(*points)
            row.append([min(xs), min(ys), max(xs) - min(xs) + 1, max(ys) - min(ys) + 1])
        result.append(row)
    return result


def rle_colorkey_alpha_lock_state():
    source = pygame.Surface((3, 1), pygame.SRCALPHA, 32)
    for x, color in enumerate([(200, 10, 20, 255), (255, 0, 255, 255),
                               (20, 200, 30, 100)]):
        source.set_at((x, 0), color)
    source.set_colorkey((255, 0, 255), pygame.RLEACCEL)
    source.set_alpha(128)
    target = pygame.Surface((3, 1), pygame.SRCALPHA, 32)
    target.fill((10, 20, 30, 255))
    target.blit(source, (0, 0))
    # Check observable surface state and pixels, never pygame's private flag bits.
    return [[list(target.get_at((x, 0))) for x in range(3)],
            list(source.get_colorkey()), source.get_alpha(), int(source.get_locked())]


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
        mask_rect_anchors(),
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
        event_selection(),
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
        sdl2_renderer_targets_and_controls(), sdl2_texture_partial_update(),
        sdl2_texture_rotation_origin(), sdl2_image_nested_rects(),
        sdl2_image_modulation_pixels(), rle_colorkey_alpha_lock_state(),
        custom_blend_modes(), freetype_face_information(),
        [pygame.freetype.STYLE_NORMAL, pygame.freetype.STYLE_STRONG,
         pygame.freetype.STYLE_OBLIQUE, pygame.freetype.STYLE_UNDERLINE,
         pygame.freetype.STYLE_WIDE, pygame.freetype.STYLE_DEFAULT],
        renderer_blitting(), freetype_layout_controls(), freetype_baseline_ink_bounds(),
        premultiplied_image_bytes(), encoded_sound_memory(), freetype_independent_size_axes(),
        encoded_image_output(), music_memory_playback(), freetype_retained_text(),
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
