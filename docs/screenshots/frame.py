#!/usr/bin/env python3
"""Frame screenshots in device mockups for all platforms."""

from PIL import Image, ImageDraw
import numpy as np
import io
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
APPLE_DIR = os.path.join(SCRIPT_DIR, "apple")
GARMIN_DIR = os.path.join(SCRIPT_DIR, "garmin")
IPHONE_DIR = os.path.join(SCRIPT_DIR, "iphone")


def frame_apple_watch():
    """Frame Apple Watch screenshots using existing framed image as template."""
    SCREEN_X, SCREEN_Y = 72, 194
    SCREEN_W, SCREEN_H = 416, 496

    # Build frame overlay by comparing all 3 original framed images from git.
    # Pixels identical across all 3 = frame (bezel, case, bands).
    # Pixels that differ = screen content → make transparent.
    import subprocess
    refs = []
    for name in ["01-station-view.png", "02-focused-tracking.png"]:
        data = subprocess.run(
            ["git", "show", f"HEAD:docs/screenshots/apple/{name}"],
            capture_output=True,
        ).stdout
        refs.append(np.array(Image.open(io.BytesIO(data))))
    refs.append(np.array(Image.open(os.path.join(APPLE_DIR, "03-station-picker.png"))))

    # Max pixel difference across all 3 references in the screen region
    screens = [r[SCREEN_Y:SCREEN_Y + SCREEN_H, SCREEN_X:SCREEN_X + SCREEN_W] for r in refs]
    diffs = []
    for i in range(3):
        for j in range(i + 1, 3):
            diffs.append(np.max(np.abs(
                screens[i][:, :, :3].astype(int) - screens[j][:, :, :3].astype(int)
            ), axis=2))
    max_diff = np.maximum(diffs[0], np.maximum(diffs[1], diffs[2]))

    # Identify bezel pixels at screen corners. A pixel is frame/bezel if:
    # 1. Identical across all 3 refs (max_diff <= 3)
    # 2. Located in a corner region (bezel only intrudes at rounded corners)
    # 3. Either non-black (actual bezel metal) OR semi-transparent (watch edge)
    # Black opaque pixels matching across refs are just black screen background.
    CORNER = 30
    EDGE_TOP = 10     # glass gradient rows at top
    EDGE_BOTTOM = 16  # glass gradient rows at bottom
    brightness = np.max(screens[0][:, :, :3], axis=2)
    alpha = screens[0][:, :, 3]

    is_matching = max_diff <= 8
    is_visible_bezel = (brightness > 0) | (alpha < 255)

    # Bezel exists at corners AND along top/bottom glass edge
    edge_mask = np.zeros((SCREEN_H, SCREEN_W), dtype=bool)
    edge_mask[:CORNER, :CORNER] = True
    edge_mask[:CORNER, SCREEN_W - CORNER:] = True
    edge_mask[SCREEN_H - CORNER:, :CORNER] = True
    edge_mask[SCREEN_H - CORNER:, SCREEN_W - CORNER:] = True
    edge_mask[:EDGE_TOP, :] = True
    edge_mask[SCREEN_H - EDGE_BOTTOM:, :] = True

    is_frame = is_matching & is_visible_bezel & edge_mask

    # Paste mask: 255 = replace with new content, 0 = keep original frame pixel
    paste_mask = Image.fromarray(
        np.where(is_frame, 0, 255).astype(np.uint8), mode="L"
    )

    # Use first reference as base (frame pixels are identical across all refs)
    base_frame = Image.fromarray(refs[0])

    mappings = [
        ("watch-station-view.png", "01-station-view.png"),
        ("watch-tracking.png", "02-focused-tracking.png"),
    ]

    for src_name, dst_name in mappings:
        src_path = os.path.join(APPLE_DIR, src_name)
        if not os.path.exists(src_path):
            print(f"  Skipping {src_name} (not found)")
            continue

        raw = Image.open(src_path).convert("RGBA")
        resized = raw.resize((SCREEN_W, SCREEN_H), Image.LANCZOS)

        result = base_frame.copy()
        result.paste(resized, (SCREEN_X, SCREEN_Y), paste_mask)
        result.save(os.path.join(APPLE_DIR, dst_name))
        print(f"  Framed: {src_name} -> {dst_name}")


def frame_garmin():
    """Frame Garmin screenshots using existing framed image as template."""
    # Display position within the 403x558 framed image
    DISPLAY_X, DISPLAY_Y = 76, 143
    DISPLAY_SIZE = 260
    RADIUS = DISPLAY_SIZE // 2

    # Load existing framed image and blank circular display area
    template = Image.open(os.path.join(GARMIN_DIR, "01-station-view-framed.png")).copy()
    draw = ImageDraw.Draw(template)
    draw.ellipse(
        [DISPLAY_X, DISPLAY_Y, DISPLAY_X + DISPLAY_SIZE - 1, DISPLAY_Y + DISPLAY_SIZE - 1],
        fill=(0, 0, 0, 255),
    )

    # Create circular mask for pasting
    mask = Image.new("L", (DISPLAY_SIZE, DISPLAY_SIZE), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.ellipse([0, 0, DISPLAY_SIZE - 1, DISPLAY_SIZE - 1], fill=255)

    raw_files = [
        ("01-station-view.png", "01-station-view-framed.png"),
        ("02-train-selection.png", "02-train-selection-framed.png"),
        ("03-focused-tracking.png", "03-focused-tracking-framed.png"),
        ("04-station-picker.png", "04-station-picker-framed.png"),
    ]

    for raw_name, framed_name in raw_files:
        raw_path = os.path.join(GARMIN_DIR, raw_name)
        if not os.path.exists(raw_path):
            print(f"  Skipping {raw_name} (not found)")
            continue

        raw = Image.open(raw_path).convert("RGBA")

        result = template.copy()
        result.paste(raw, (DISPLAY_X, DISPLAY_Y), mask)
        result.save(os.path.join(GARMIN_DIR, framed_name))
        print(f"  Framed: {raw_name} -> {framed_name}")


def frame_iphone():
    """Frame iPhone screenshots in an iPhone 17 Pro Max style device frame."""
    os.makedirs(IPHONE_DIR, exist_ok=True)

    # Scale 1320x2868 to gallery size
    SCREEN_W, SCREEN_H = 400, 868

    # iPhone 17 Pro Max: very thin bezels, titanium frame
    BEZEL = 10
    OUTER_RADIUS = 44
    INNER_RADIUS = 38
    FRAME_EDGE = 3  # titanium frame highlight width
    FRAME_W = SCREEN_W + BEZEL * 2  # 420
    FRAME_H = SCREEN_H + BEZEL * 2  # 888

    # Dynamic Island proportions (scaled from 1320 → 400 width)
    DI_W, DI_H = 92, 26
    DI_X = FRAME_W // 2 - DI_W // 2
    DI_Y = BEZEL + 8

    # Side button (power) on the right
    BTN_W, BTN_H = 3, 52
    BTN_X = FRAME_W - 1
    BTN_Y = FRAME_H // 4

    # Volume buttons on the left
    VOL_W, VOL_H = 3, 34
    VOL_X = 0
    VOL1_Y = FRAME_H // 4 - 10
    VOL2_Y = VOL1_Y + VOL_H + 12

    # Build frame layer (transparent background)
    frame = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(frame)

    # Outer titanium shell
    draw.rounded_rectangle(
        [0, 0, FRAME_W - 1, FRAME_H - 1],
        radius=OUTER_RADIUS,
        fill=(42, 42, 44, 255),  # dark titanium base
    )

    # Titanium frame highlight (subtle lighter edge)
    draw.rounded_rectangle(
        [FRAME_EDGE, FRAME_EDGE, FRAME_W - 1 - FRAME_EDGE, FRAME_H - 1 - FRAME_EDGE],
        radius=OUTER_RADIUS - FRAME_EDGE,
        fill=(30, 30, 32, 255),  # inner shell
    )

    # Screen area (black)
    draw.rounded_rectangle(
        [BEZEL, BEZEL, BEZEL + SCREEN_W - 1, BEZEL + SCREEN_H - 1],
        radius=INNER_RADIUS,
        fill=(0, 0, 0, 255),
    )

    # Side buttons
    draw.rounded_rectangle(
        [BTN_X - BTN_W + 1, BTN_Y, BTN_X, BTN_Y + BTN_H],
        radius=1, fill=(55, 55, 58, 255),
    )
    draw.rounded_rectangle(
        [VOL_X, VOL1_Y, VOL_X + VOL_W - 1, VOL1_Y + VOL_H],
        radius=1, fill=(55, 55, 58, 255),
    )
    draw.rounded_rectangle(
        [VOL_X, VOL2_Y, VOL_X + VOL_W - 1, VOL2_Y + VOL_H],
        radius=1, fill=(55, 55, 58, 255),
    )

    # Screen content mask
    screen_mask = Image.new("L", (SCREEN_W, SCREEN_H), 0)
    mask_draw = ImageDraw.Draw(screen_mask)
    mask_draw.rounded_rectangle(
        [0, 0, SCREEN_W - 1, SCREEN_H - 1],
        radius=INNER_RADIUS,
        fill=255,
    )

    mappings = [
        ("iphone-tracking-formation.png", "01-station-view.png"),
        ("iphone-tracking.png", "02-focused-tracking.png"),
        ("iphone-station-view.png", "03-station-picker.png"),
    ]

    for src_name, dst_name in mappings:
        src_path = os.path.join(APPLE_DIR, src_name)
        if not os.path.exists(src_path):
            print(f"  Skipping {src_name} (not found)")
            continue

        raw = Image.open(src_path).convert("RGBA")
        resized = raw.resize((SCREEN_W, SCREEN_H), Image.LANCZOS)

        # Composite: screen content, then frame on top
        result = frame.copy()
        result.paste(resized, (BEZEL, BEZEL), screen_mask)

        # Dynamic Island on top of screen content
        result_draw = ImageDraw.Draw(result)
        result_draw.rounded_rectangle(
            [DI_X, DI_Y, DI_X + DI_W, DI_Y + DI_H],
            radius=DI_H // 2,
            fill=(0, 0, 0, 255),
        )

        result.save(os.path.join(IPHONE_DIR, dst_name))
        print(f"  Framed: {src_name} -> {dst_name}")


if __name__ == "__main__":
    print("Framing Apple Watch screenshots...")
    frame_apple_watch()
    print()
    print("Framing Garmin screenshots...")
    frame_garmin()
    print()
    print("Framing iPhone screenshots...")
    frame_iphone()
    print()
    print("Done!")
