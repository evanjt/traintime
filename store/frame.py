#!/usr/bin/env python3
"""Frame raw captures in the manufacturers' own device art.

Apple's product bezels (developer.apple.com/design/resources, used under its
marketing guidelines) have a transparent screen hole; the capture goes under
them. Google's device art from Android Studio (Apache 2.0) is a back plate, a
screen mask and sometimes a foreground; the capture goes between. The Garmin
frame is a product photo with its display blanked.
"""

from PIL import Image, ImageDraw
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CAPTURES = os.path.join(SCRIPT_DIR, "captures")
FRAMED = os.path.join(SCRIPT_DIR, "framed")
FRAMES = os.path.join(SCRIPT_DIR, "frames")

# Google art places the screen by its layout file; Apple art by its hole.
DEVICES = {
    "iphone": dict(art="apple-iphone-17-pro-max.png"),
    "iphone-duo-inner": dict(art="apple-iphone-duo-inner.png"),
    "iphone-duo-outer": dict(art="apple-iphone-duo-outer.png"),
    "apple-watch": dict(art="apple-watch-s11-46mm.png"),
    # The Pixel's "mask" is drawn over the screen (rounded corners, camera).
    "android": dict(back="google-pixel-5-back.webp", over="google-pixel-5-mask.webp",
                    screen=(60, 65, 1080, 2340)),
    "android-qhd": dict(back="google-pixel-7-pro-back.webp", over="google-pixel-7-pro-mask.webp",
                        screen=(48, 66, 1440, 3120)),
    "wear-os": dict(back="google-watch-round-back.png", fore="google-watch-round-fore.png",
                    mask="google-watch-round-mask.png", screen=(25, 26, 320, 320)),
}


def screen_rect(device):
    """(x, y, w, h) of the screen inside the device art."""
    spec = DEVICES[device]
    if "screen" in spec:
        return spec["screen"]
    # Flood the transparent hole from the art's centre; islands inside it (the
    # Dynamic Island) stay out of the flood but inside its bounding box.
    art = Image.open(os.path.join(FRAMES, spec["art"]))
    hole = art.getchannel("A").point(lambda a: 255 if a < 128 else 0)
    ImageDraw.floodfill(hole, (art.width // 2, art.height // 2), 128)
    return _bbox(hole)


def _bbox(hole):
    x0, y0, x1, y1 = hole.point(lambda v: 255 if v == 128 else 0).getbbox()
    return x0, y0, x1 - x0, y1 - y0


def frame_device(device, capture):
    """The capture (path or image) in the device art, as an RGBA image."""
    spec = DEVICES[device]
    shot = capture if isinstance(capture, Image.Image) else Image.open(capture)
    x, y, w, h = screen_rect(device)
    shot = shot.convert("RGBA")
    # A capture from a taller screen is cut at the bottom, never squashed.
    if shot.height * w > shot.width * h + shot.width:
        shot = shot.crop((0, 0, shot.width, round(shot.width * h / w)))
    shot = shot.resize((w, h), Image.LANCZOS)
    if "art" in spec:
        art = Image.open(os.path.join(FRAMES, spec["art"])).convert("RGBA")
        out = Image.new("RGBA", art.size, (0, 0, 0, 0))
        out.paste(shot, (x, y))
        out.alpha_composite(art)
        return out
    out = Image.open(os.path.join(FRAMES, spec["back"])).convert("RGBA")
    layer = Image.new("RGBA", out.size, (0, 0, 0, 0))
    if "mask" in spec:
        mask = Image.open(os.path.join(FRAMES, spec["mask"])).convert("RGBA")
        if mask.size != (w, h):
            mask = mask.crop((x, y, x + w, y + h))
        layer.paste(shot, (x, y), mask.getchannel("A"))
    else:
        layer.paste(shot, (x, y))
    out.alpha_composite(layer)
    if "over" in spec:
        out.alpha_composite(Image.open(os.path.join(FRAMES, spec["over"])).convert("RGBA"), (x, y))
    if "fore" in spec:
        out.alpha_composite(Image.open(os.path.join(FRAMES, spec["fore"])).convert("RGBA"))
    return out


def save_framed(device, capture, dest, width):
    framed = frame_device(device, capture)
    framed = framed.resize((width, round(framed.height * width / framed.width)), Image.LANCZOS)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    framed.save(dest)
    print(f"  Framed: {os.path.relpath(dest, SCRIPT_DIR)}")


def frame_apple_watch():
    for src, dst in [("watch-station-view.png", "01-station-view.png"),
                     ("watch-tracking.png", "02-focused-tracking.png")]:
        save_framed("apple-watch", os.path.join(CAPTURES, "apple-watch", src),
                    os.path.join(FRAMED, "apple-watch", dst), 560)


def frame_wear_os():
    """The station and tracking captures on the round watch, for the website
    gallery and the Play watch board."""
    for src, dst in [("01.png", "01-station-view-framed.png"),
                     ("02.png", "02-focused-tracking-framed.png")]:
        # Through RGB, as Play receives it: the capture's edge alpha is dropped.
        shot = Image.open(os.path.join(CAPTURES, "wear-os", src)).convert("RGB")
        framed = frame_device("wear-os", shot)
        framed = framed.crop(framed.getbbox())
        framed = framed.resize((440, round(framed.height * 440 / framed.width)), Image.LANCZOS)
        dest = os.path.join(FRAMED, "wear-os", dst)
        framed.save(dest)
        print(f"  Framed: {os.path.relpath(dest, SCRIPT_DIR)}")


def frame_iphone():
    for name in ["01-station-view", "02-focused-tracking", "03-station-picker"]:
        save_framed("iphone", os.path.join(CAPTURES, "iphone", f"{name}-raw.png"),
                    os.path.join(FRAMED, "iphone", f"{name}.png"), 440)


def frame_garmin():
    """Frame Garmin screenshots using existing framed image as template."""
    # Display position within the 403x558 framed image
    DISPLAY_X, DISPLAY_Y = 76, 143
    DISPLAY_SIZE = 260
    RADIUS = DISPLAY_SIZE // 2

    # Load existing framed image and blank circular display area
    template = Image.open(os.path.join(FRAMED, "garmin", "01-station-view-framed.png")).copy()
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
        raw_path = os.path.join(CAPTURES, "garmin", raw_name)
        if not os.path.exists(raw_path):
            print(f"  Skipping {raw_name} (not found)")
            continue

        raw = Image.open(raw_path).convert("RGBA")

        result = template.copy()
        result.paste(raw, (DISPLAY_X, DISPLAY_Y), mask)
        result.save(os.path.join(FRAMED, "garmin", framed_name))
        print(f"  Framed: {raw_name} -> {framed_name}")



if __name__ == "__main__":
    print("Framing Apple Watch screenshots...")
    frame_apple_watch()
    print("Framing Garmin screenshots...")
    frame_garmin()
    print("Framing iPhone screenshots...")
    frame_iphone()
    print("Framing Wear OS screenshots...")
    frame_wear_os()
    print("Done!")
