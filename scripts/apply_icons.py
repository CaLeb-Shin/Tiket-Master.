#!/usr/bin/env python3
"""
Apply generated 1024x1024 icons to all platform-specific sizes.
Resizes and copies icons to iOS, Android, macOS, and Web locations.
"""

import os
import shutil
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TICKET_SRC = os.path.join(ROOT, 'icon_sources', 'melon_ticket_icon_1024.png')
ADMIN_SRC = os.path.join(ROOT, 'icon_sources', 'melon_admin_icon_1024.png')

TICKET_APP = os.path.join(ROOT, 'melon_ticket_app')
ADMIN_APP = os.path.join(ROOT, 'melon_admin')


def resize_and_save(src_path, out_path, size):
    """Resize icon to given size and save as PNG."""
    img = Image.open(src_path)
    resized = img.resize((size, size), Image.LANCZOS)
    resized.save(out_path, 'PNG')
    print(f"  {size}x{size} → {os.path.relpath(out_path, ROOT)}")


def apply_ticket_icons():
    print("\n=== Melon Ticket App Icons ===\n")

    # iOS icons
    ios_dir = os.path.join(TICKET_APP, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    ios_sizes = {
        'Icon-App-1024x1024@1x.png': 1024,
        'Icon-App-20x20@1x.png': 20,
        'Icon-App-20x20@2x.png': 40,
        'Icon-App-20x20@3x.png': 60,
        'Icon-App-29x29@1x.png': 29,
        'Icon-App-29x29@2x.png': 58,
        'Icon-App-29x29@3x.png': 87,
        'Icon-App-40x40@1x.png': 40,
        'Icon-App-40x40@2x.png': 80,
        'Icon-App-40x40@3x.png': 120,
        'Icon-App-60x60@2x.png': 120,
        'Icon-App-60x60@3x.png': 180,
        'Icon-App-76x76@1x.png': 76,
        'Icon-App-76x76@2x.png': 152,
        'Icon-App-83.5x83.5@2x.png': 167,
    }
    print("iOS:")
    for filename, size in ios_sizes.items():
        resize_and_save(TICKET_SRC, os.path.join(ios_dir, filename), size)

    # Android icons
    android_sizes = {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192,
    }
    print("\nAndroid:")
    for folder, size in android_sizes.items():
        out = os.path.join(TICKET_APP, 'android', 'app', 'src', 'main', 'res', folder, 'ic_launcher.png')
        resize_and_save(TICKET_SRC, out, size)

    # macOS icons
    macos_dir = os.path.join(TICKET_APP, 'macos', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    macos_sizes = {
        'app_icon_16.png': 16,
        'app_icon_32.png': 32,
        'app_icon_64.png': 64,
        'app_icon_128.png': 128,
        'app_icon_256.png': 256,
        'app_icon_512.png': 512,
        'app_icon_1024.png': 1024,
    }
    print("\nmacOS:")
    for filename, size in macos_sizes.items():
        resize_and_save(TICKET_SRC, os.path.join(macos_dir, filename), size)

    # Web icons
    web_sizes = {
        'favicon.png': 16,
        'icons/Icon-192.png': 192,
        'icons/Icon-512.png': 512,
        'icons/Icon-maskable-192.png': 192,
        'icons/Icon-maskable-512.png': 512,
    }
    print("\nWeb:")
    for filepath, size in web_sizes.items():
        resize_and_save(TICKET_SRC, os.path.join(TICKET_APP, 'web', filepath), size)


def apply_admin_icons():
    print("\n=== Melon Admin Icons ===\n")

    # Web icons only (admin is web-only)
    web_sizes = {
        'favicon.png': 16,
        'icons/Icon-192.png': 192,
        'icons/Icon-512.png': 512,
        'icons/Icon-maskable-192.png': 192,
        'icons/Icon-maskable-512.png': 512,
    }
    print("Web:")
    for filepath, size in web_sizes.items():
        resize_and_save(ADMIN_SRC, os.path.join(ADMIN_APP, 'web', filepath), size)


if __name__ == '__main__':
    apply_ticket_icons()
    apply_admin_icons()
    print("\nAll icons applied!")
