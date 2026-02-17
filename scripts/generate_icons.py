#!/usr/bin/env python3
"""
Generate premium app icons for Melon Ticket and Melon Admin.
Multi-layer gradients, metallic textures, depth, glow, and glass effects.
"""

import math
import random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SIZE = 1024
CORNER_RADIUS = int(SIZE * 0.22)  # iOS-style rounded corners


def radial_gradient(size, center, radius, color_inner, color_outer):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    pixels = img.load()
    cx, cy = center
    for y in range(size):
        for x in range(size):
            dist = math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
            t = min(dist / radius, 1.0)
            t = t * t * (3 - 2 * t)  # smoothstep
            r = int(color_inner[0] + (color_outer[0] - color_inner[0]) * t)
            g = int(color_inner[1] + (color_outer[1] - color_inner[1]) * t)
            b = int(color_inner[2] + (color_outer[2] - color_inner[2]) * t)
            a = int(color_inner[3] + (color_outer[3] - color_inner[3]) * t)
            pixels[x, y] = (r, g, b, a)
    return img


def linear_gradient(size, color_top, color_bottom, angle_deg=0):
    """Vertical (or angled) linear gradient."""
    img = Image.new('RGBA', (size, size))
    pixels = img.load()
    angle = math.radians(angle_deg)
    cos_a = math.cos(angle)
    sin_a = math.sin(angle)
    for y in range(size):
        for x in range(size):
            # Project onto gradient direction
            nx = (x - size / 2) / size
            ny = (y - size / 2) / size
            proj = nx * sin_a + ny * cos_a + 0.5
            t = max(0.0, min(1.0, proj))
            r = int(color_top[0] + (color_bottom[0] - color_top[0]) * t)
            g = int(color_top[1] + (color_bottom[1] - color_top[1]) * t)
            b = int(color_top[2] + (color_bottom[2] - color_top[2]) * t)
            a = int(color_top[3] + (color_bottom[3] - color_top[3]) * t)
            pixels[x, y] = (r, g, b, a)
    return img


def add_noise(img, amount=5):
    pixels = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            noise = random.randint(-amount, amount)
            r = max(0, min(255, r + noise))
            g = max(0, min(255, g + noise))
            b = max(0, min(255, b + noise))
            pixels[x, y] = (r, g, b, a)
    return img


def create_rim_light(size, thickness=3, color=(255, 255, 255, 15)):
    """Create a subtle inner rim/edge light."""
    outer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(outer)
    # Outer filled rect
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=CORNER_RADIUS, fill=color)
    # Punch out inner
    inner = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw_inner = ImageDraw.Draw(inner)
    m = thickness
    draw_inner.rounded_rectangle([m, m, size - 1 - m, size - 1 - m], radius=max(1, CORNER_RADIUS - m),
                                 fill=(255, 255, 255, 255))
    # Use inner as an inverse mask
    r, g, b, a_outer = outer.split()
    _, _, _, a_inner = inner.split()
    # Subtract inner alpha from outer alpha
    from PIL import ImageChops
    a_result = ImageChops.subtract(a_outer, a_inner)
    outer.putalpha(a_result)
    return outer


def generate_ticket_icon(output_path):
    """Melon Ticket icon — rich burgundy with music note ♪."""
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))

    # === Layer 1: Base gradient (deep burgundy → near-black) ===
    bg = linear_gradient(SIZE, (52, 10, 22, 255), (14, 3, 8, 255), angle_deg=15)
    img = Image.alpha_composite(img, bg)

    # === Layer 2: Warm radial glow (upper-center) ===
    glow1 = radial_gradient(SIZE, (SIZE * 0.42, SIZE * 0.32), SIZE * 0.6,
                            (170, 35, 60, 90), (0, 0, 0, 0))
    img = Image.alpha_composite(img, glow1)

    # === Layer 3: Secondary highlight (top-left, pinkish) ===
    glow2 = radial_gradient(SIZE, (SIZE * 0.2, SIZE * 0.12), SIZE * 0.4,
                            (200, 60, 85, 50), (0, 0, 0, 0))
    img = Image.alpha_composite(img, glow2)

    # === Layer 4: Bottom shadow (depth) ===
    shadow = radial_gradient(SIZE, (SIZE * 0.75, SIZE * 0.88), SIZE * 0.5,
                             (5, 0, 2, 70), (0, 0, 0, 0))
    img = Image.alpha_composite(img, shadow)

    # === Layer 5: Ambient reflected light (bottom-left, very subtle) ===
    ambient = radial_gradient(SIZE, (SIZE * 0.15, SIZE * 0.85), SIZE * 0.4,
                              (100, 20, 40, 25), (0, 0, 0, 0))
    img = Image.alpha_composite(img, ambient)

    # === Noise ===
    img = add_noise(img, amount=4)

    # === Glass highlight (top) ===
    glass = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    glass_draw = ImageDraw.Draw(glass)
    glass_draw.ellipse(
        [int(SIZE * 0.05), int(-SIZE * 0.35), int(SIZE * 0.95), int(SIZE * 0.32)],
        fill=(255, 255, 255, 22)
    )
    glass = glass.filter(ImageFilter.GaussianBlur(radius=SIZE * 0.07))
    img = Image.alpha_composite(img, glass)

    # === Music note using Apple Symbols ♪ ===
    font_size = int(SIZE * 0.9)
    font = ImageFont.truetype("/System/Library/Fonts/Apple Symbols.ttf", font_size)
    note_char = "♪"

    draw = ImageDraw.Draw(img)
    bbox = draw.textbbox((0, 0), note_char, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (SIZE - tw) // 2 - bbox[0]
    ty = (SIZE - th) // 2 - bbox[1] - int(SIZE * 0.02)

    # Drop shadow
    shadow_layer = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    shadow_d = ImageDraw.Draw(shadow_layer)
    shadow_d.text((tx + 5, ty + 8), note_char, font=font, fill=(0, 0, 0, 100))
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=14))
    img = Image.alpha_composite(img, shadow_layer)

    # Outer glow (soft white bloom around the note)
    bloom = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    bloom_d = ImageDraw.Draw(bloom)
    bloom_d.text((tx, ty), note_char, font=font, fill=(255, 220, 230, 35))
    bloom = bloom.filter(ImageFilter.GaussianBlur(radius=20))
    img = Image.alpha_composite(img, bloom)

    # Main note — white with very slight warmth
    draw = ImageDraw.Draw(img)
    draw.text((tx, ty), note_char, font=font, fill=(255, 252, 250, 250))

    # Top-edge highlight on the note
    highlight = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    h_draw = ImageDraw.Draw(highlight)
    h_draw.text((tx, ty - 3), note_char, font=font, fill=(255, 255, 255, 50))
    highlight = highlight.filter(ImageFilter.GaussianBlur(radius=5))
    # Mask to note area
    note_mask = Image.new('L', (SIZE, SIZE), 0)
    mask_d = ImageDraw.Draw(note_mask)
    mask_d.text((tx, ty), note_char, font=font, fill=255)
    highlight.putalpha(Image.composite(highlight.split()[3], Image.new('L', (SIZE, SIZE), 0), note_mask))
    img = Image.alpha_composite(img, highlight)

    # === Vignette ===
    vignette = radial_gradient(SIZE, (SIZE // 2, SIZE // 2), SIZE * 0.65,
                               (0, 0, 0, 0), (0, 0, 0, 55))
    img = Image.alpha_composite(img, vignette)

    # === Rim light (subtle inner border glow) ===
    rim = create_rim_light(SIZE, thickness=2, color=(255, 200, 210, 18))
    rim_blurred = rim.filter(ImageFilter.GaussianBlur(radius=2))
    img = Image.alpha_composite(img, rim_blurred)

    img.save(output_path, 'PNG')
    print(f"Ticket icon saved: {output_path}")


def generate_admin_icon(output_path):
    """Melon Admin icon — dark premium with gold 'M' monogram."""
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))

    # === Layer 1: Deep dark gradient (angled) ===
    bg = linear_gradient(SIZE, (28, 20, 35, 255), (8, 5, 12, 255), angle_deg=20)
    img = Image.alpha_composite(img, bg)

    # === Layer 2: Burgundy core glow ===
    glow1 = radial_gradient(SIZE, (SIZE * 0.48, SIZE * 0.42), SIZE * 0.5,
                            (110, 18, 42, 65), (0, 0, 0, 0))
    img = Image.alpha_composite(img, glow1)

    # === Layer 3: Gold warm accent (top) ===
    glow2 = radial_gradient(SIZE, (SIZE * 0.35, SIZE * 0.15), SIZE * 0.45,
                            (120, 80, 30, 30), (0, 0, 0, 0))
    img = Image.alpha_composite(img, glow2)

    # === Layer 4: Deep bottom shadow ===
    shadow = radial_gradient(SIZE, (SIZE * 0.7, SIZE * 0.9), SIZE * 0.5,
                             (3, 0, 5, 60), (0, 0, 0, 0))
    img = Image.alpha_composite(img, shadow)

    # === Noise ===
    img = add_noise(img, amount=3)

    # === Glass highlight ===
    glass = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    glass_draw = ImageDraw.Draw(glass)
    glass_draw.ellipse(
        [int(SIZE * 0.08), int(-SIZE * 0.32), int(SIZE * 0.92), int(SIZE * 0.30)],
        fill=(255, 255, 255, 18)
    )
    glass = glass.filter(ImageFilter.GaussianBlur(radius=SIZE * 0.06))
    img = Image.alpha_composite(img, glass)

    # === 'M' monogram ===
    # Use Helvetica Neue Bold for clean, premium look
    font_size = int(SIZE * 0.55)
    font = ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", font_size, index=1)  # Bold
    text = "M"

    draw = ImageDraw.Draw(img)
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (SIZE - tw) // 2 - bbox[0]
    ty = (SIZE - th) // 2 - bbox[1] - int(SIZE * 0.015)

    # Drop shadow
    shadow_layer = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    shadow_d = ImageDraw.Draw(shadow_layer)
    shadow_d.text((tx + 5, ty + 8), text, font=font, fill=(0, 0, 0, 110))
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=14))
    img = Image.alpha_composite(img, shadow_layer)

    # Outer gold bloom
    bloom = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    bloom_d = ImageDraw.Draw(bloom)
    bloom_d.text((tx, ty), text, font=font, fill=(220, 180, 100, 30))
    bloom = bloom.filter(ImageFilter.GaussianBlur(radius=22))
    img = Image.alpha_composite(img, bloom)

    # Gold gradient text
    text_mask = Image.new('L', (SIZE, SIZE), 0)
    mask_d = ImageDraw.Draw(text_mask)
    mask_d.text((tx, ty), text, font=font, fill=255)

    # Multi-stop gold gradient (top-light → mid-deep → bottom-warm)
    gold = Image.new('RGBA', (SIZE, SIZE))
    gold_px = gold.load()
    for y in range(SIZE):
        t = y / (SIZE - 1)
        if t < 0.3:
            # Light gold top
            lt = t / 0.3
            r = int(255 + (235 - 255) * lt)
            g = int(230 + (195 - 230) * lt)
            b = int(170 + (120 - 170) * lt)
        elif t < 0.7:
            # Rich gold mid
            lt = (t - 0.3) / 0.4
            r = int(235 + (215 - 235) * lt)
            g = int(195 + (165 - 195) * lt)
            b = int(120 + (85 - 120) * lt)
        else:
            # Deep warm gold bottom
            lt = (t - 0.7) / 0.3
            r = int(215 + (190 - 215) * lt)
            g = int(165 + (140 - 165) * lt)
            b = int(85 + (65 - 85) * lt)
        for x in range(SIZE):
            gold_px[x, y] = (r, g, b, 255)

    gold_text = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    gold_text.paste(gold, mask=text_mask)
    img = Image.alpha_composite(img, gold_text)

    # Top edge highlight on text
    edge_light = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    edge_d = ImageDraw.Draw(edge_light)
    edge_d.text((tx, ty - 2), text, font=font, fill=(255, 245, 220, 60))
    edge_light = edge_light.filter(ImageFilter.GaussianBlur(radius=4))
    edge_masked = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    edge_masked.paste(edge_light, mask=text_mask)
    img = Image.alpha_composite(img, edge_masked)

    # Bottom edge shadow on text (inner bevel)
    bevel = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    bevel_d = ImageDraw.Draw(bevel)
    bevel_d.text((tx, ty + 2), text, font=font, fill=(0, 0, 0, 35))
    bevel = bevel.filter(ImageFilter.GaussianBlur(radius=3))
    bevel_masked = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    bevel_masked.paste(bevel, mask=text_mask)
    img = Image.alpha_composite(img, bevel_masked)

    # === Vignette ===
    vignette = radial_gradient(SIZE, (SIZE // 2, SIZE // 2), SIZE * 0.65,
                               (0, 0, 0, 0), (0, 0, 0, 55))
    img = Image.alpha_composite(img, vignette)

    # === Rim light (gold tint) ===
    rim = create_rim_light(SIZE, thickness=2, color=(220, 180, 120, 14))
    rim_blurred = rim.filter(ImageFilter.GaussianBlur(radius=2))
    img = Image.alpha_composite(img, rim_blurred)

    img.save(output_path, 'PNG')
    print(f"Admin icon saved: {output_path}")


if __name__ == '__main__':
    import os

    base = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(base)

    out_dir = os.path.join(root, 'icon_sources')
    os.makedirs(out_dir, exist_ok=True)

    ticket_path = os.path.join(out_dir, 'melon_ticket_icon_1024.png')
    admin_path = os.path.join(out_dir, 'melon_admin_icon_1024.png')

    print("Generating Melon Ticket icon...")
    generate_ticket_icon(ticket_path)

    print("Generating Melon Admin icon...")
    generate_admin_icon(admin_path)

    print("\nDone!")
    print(f"  {ticket_path}")
    print(f"  {admin_path}")
