#!/usr/bin/env python3
"""Walking store video: a hand holding the phone on the way to the platform.

Three layers, composited per frame:
  1. the walk towards a platform, filmed at chest height, scaled to cover the
     frame and blurred so no face or operator logo is legible;
  2. the app, a simulator recording of tracking while the simulated location
     follows a route to the station, sped up to fit the loop and warped into
     the phone's screen;
  3. the hand holding the phone, a keyed photo whose screen is transparent,
     swaying in step with the walk and running off the bottom edge.

Inputs, in store/walk/ (gitignored, footage and photos stay out of the
repository):
  background.mp4    the walk, at least WALK_SECONDS long
  hand.png          the hand and phone, keyed, the screen transparent
  hand.json         {"screen": [[x, y], ...]}: the screen corners in hand.png
                    pixels, clockwise from top left
  <locale>/app.mp4  the app in that locale, recorded with
                    `xcrun simctl io <udid> recordVideo` while
                    `xcrun simctl location <udid> start` walks the route

Outputs, per locale: the App Store header (21:9) and search (3:2) videos and
the search still in manual/app-store/<locale>/, and the Play promo (16:9, for
YouTube) in manual/play/<locale>/.

Usage: walk.py [locale ...]
"""

import json
import math
import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
INPUTS = os.path.join(SCRIPT_DIR, "walk")

WALK_SECONDS = 20
FPS = 30

FORMATS = {
    "header": dict(size=(3840, 1646), out=("app-store", "walk-header.mp4"), still=None),
    "search": dict(size=(2880, 1920), out=("app-store", "walk-search.mp4"),
                   still=("walk-search.png", (3840, 2560))),
    "play": dict(size=(1920, 1080), out=("play", "walk-promo.mp4"), still=None),
}

# Steps a second. Whole strides (two steps) fit the loop, so the sway ends
# where it starts.
CADENCE = 1.8
# Sway, in frame heights and degrees: side to side once a stride, a bob once a
# step, and a roll with the side swing.
SIDE = 0.012
BOB = 0.008
ROLL = 1.2

# The screen's height and centre, in frame heights.
SCREEN_SHARE = 0.6
SCREEN_CENTRE = 0.55
# How far below the frame the photo must reach at rest, in frame heights, so
# the sway never lifts the hand's cut edge into view.
BELOW = 0.04

# Background blur, gaussian sigma in frame heights.
BLUR = 0.02

# Where in the loop the still is taken: late, with the distance and margin
# counted down.
STILL_AT = 0.85


def sway(t):
    """(dx, dy, roll) at t seconds: dx and dy in frame heights, roll in degrees."""
    phase = math.pi * CADENCE * t
    return SIDE * math.sin(phase), BOB * math.cos(2 * phase), ROLL * math.sin(phase)


def app_speed(app_seconds, seconds):
    """How much faster than real time the route recording plays to fill the loop."""
    if app_seconds < seconds:
        raise SystemExit(f"app recording is {app_seconds:.1f} s, shorter than the {seconds} s loop")
    return app_seconds / seconds


def perspective(quad, size):
    """PIL PERSPECTIVE coefficients mapping the quad, clockwise from top left,
    onto a size (w, h) frame."""
    import numpy as np

    w, h = size
    rows, rhs = [], []
    for (x, y), (u, v) in zip(quad, [(0, 0), (w, 0), (w, h), (0, h)]):
        rows.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        rhs.append(u)
        rows.append([0, 0, 0, x, y, 1, -v * x, -v * y])
        rhs.append(v)
    return tuple(np.linalg.solve(np.array(rows, float), np.array(rhs, float)))


def load_hand(path):
    from PIL import Image

    with open(os.path.splitext(path)[0] + ".json") as f:
        screen = [tuple(map(float, p)) for p in json.load(f)["screen"]]
    with Image.open(path) as img:
        size = img.size
    return dict(path=path, size=size, screen=screen)


def layout(hand, canvas):
    """The hand's scale and resting screen centre on a canvas (w, h)."""
    w, h = canvas
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = hand["screen"]
    screen_h = (math.hypot(x3 - x0, y3 - y0) + math.hypot(x2 - x1, y2 - y1)) / 2
    scale = SCREEN_SHARE * h / screen_h
    centre = (sum(x for x, _ in hand["screen"]) / 4, sum(y for _, y in hand["screen"]) / 4)
    rest = (w / 2, SCREEN_CENTRE * h)
    bottom = rest[1] + scale * (hand["size"][1] - centre[1])
    if bottom < h * (1 + BELOW):
        raise SystemExit(
            f"{os.path.basename(hand['path'])} ends {bottom:.0f} px down a {h} px frame: "
            "the hand must run off the bottom edge")
    return dict(hand=hand, canvas=canvas, scale=scale, centre=centre, rest=rest)


def _pose(lay, t):
    """Forward map from hand.png pixels to canvas pixels at t: a function of (x, y)."""
    dx, dy, roll = sway(t)
    h = lay["canvas"][1]
    tx, ty = lay["rest"][0] + dx * h, lay["rest"][1] + dy * h
    cos, sin = math.cos(math.radians(roll)), math.sin(math.radians(roll))
    k, (cx, cy) = lay["scale"], lay["centre"]

    def to_canvas(x, y):
        px, py = (x - cx) * k, (y - cy) * k
        return tx + cos * px - sin * py, ty + sin * px + cos * py

    return to_canvas, (k, cos, sin, cx, cy, tx, ty)


def place(lay, t):
    """The screen quad on the canvas at t, and the hand photo's bounding box."""
    to_canvas, _ = _pose(lay, t)
    quad = [to_canvas(x, y) for x, y in lay["hand"]["screen"]]
    w, h = lay["hand"]["size"]
    corners = [to_canvas(x, y) for x, y in ((0, 0), (w, 0), (w, h), (0, h))]
    xs, ys = [x for x, _ in corners], [y for _, y in corners]
    return quad, (min(xs), min(ys), max(xs), max(ys))


def _clip_box(box, canvas):
    w, h = canvas
    x0, y0 = max(0, math.floor(box[0])), max(0, math.floor(box[1]))
    x1, y1 = min(w, math.ceil(box[2])), min(h, math.ceil(box[3]))
    return x0, y0, x1, y1


def _over(frame, box, rgba):
    import numpy as np

    x0, y0, x1, y1 = box
    a = np.asarray(rgba, np.float32)
    alpha = a[..., 3:] / 255.0
    region = frame[y0:y1, x0:x1]
    region *= 1 - alpha
    region += a[..., :3] * alpha


def compose(lay, t, ground, app, hand_img):
    """One frame: the blurred walk, the app in the screen, the hand on top."""
    import numpy as np
    from PIL import Image

    frame = ground.astype(np.float32)
    quad, box = place(lay, t)
    xs, ys = [x for x, _ in quad], [y for _, y in quad]
    qbox = _clip_box((min(xs), min(ys), max(xs), max(ys)), lay["canvas"])
    shifted = [(x - qbox[0], y - qbox[1]) for x, y in quad]
    screen = Image.fromarray(app).convert("RGBA").transform(
        (qbox[2] - qbox[0], qbox[3] - qbox[1]), Image.Transform.PERSPECTIVE,
        perspective(shifted, (app.shape[1], app.shape[0])),
        Image.Resampling.BICUBIC, fillcolor=(0, 0, 0, 0))
    _over(frame, qbox, screen)

    _, (k, cos, sin, cx, cy, tx, ty) = _pose(lay, t)
    hbox = _clip_box(box, lay["canvas"])
    # Inverse of the forward map, from the clipped box's pixels into hand.png.
    ox, oy = hbox[0] - tx, hbox[1] - ty
    a, b = cos / k, sin / k
    d, e = -sin / k, cos / k
    affine = (a, b, a * ox + b * oy + cx, d, e, d * ox + e * oy + cy)
    hand = hand_img.transform(
        (hbox[2] - hbox[0], hbox[3] - hbox[1]), Image.Transform.AFFINE, affine,
        Image.Resampling.BICUBIC, fillcolor=(0, 0, 0, 0))
    _over(frame, hbox, hand)
    return np.clip(frame, 0, 255).astype(np.uint8)


def _duration(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
        check=True, capture_output=True, text=True).stdout
    return float(out)


def _size(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0", path],
        check=True, capture_output=True, text=True).stdout
    w, h = out.strip().split(",")[:2]
    return int(w), int(h)


def _decode(path, vf, frames, start=0.0):
    return subprocess.Popen(
        ["ffmpeg", "-v", "error", "-ss", f"{start:.3f}", "-i", path, "-vf", vf,
         "-frames:v", str(frames), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        stdout=subprocess.PIPE)


def _frames(proc, size, count, name, repeat_last):
    import numpy as np

    w, h = size
    nbytes = w * h * 3
    last = None
    try:
        for i in range(count):
            buf = proc.stdout.read(nbytes)
            if len(buf) < nbytes:
                if last is None or not repeat_last:
                    raise SystemExit(f"{name} ran out after {i} of {count} frames")
                yield last
                continue
            last = np.frombuffer(buf, np.uint8).reshape(h, w, 3)
            yield last
    finally:
        proc.stdout.close()
        proc.kill()
        proc.wait()


def _ground_filter(canvas, fps):
    w, h = canvas
    return (f"scale={w}:{h}:force_original_aspect_ratio=increase,crop={w}:{h},"
            f"gblur=sigma={BLUR * h:.2f},fps={fps}")


def missing(locale, inputs):
    want = [os.path.join(inputs, n) for n in ("background.mp4", "hand.png", "hand.json")]
    want.append(os.path.join(inputs, locale, "app.mp4"))
    return [p for p in want if not os.path.exists(p)]


def render(locale, inputs, out, formats, seconds=WALK_SECONDS, fps=FPS):
    from PIL import Image

    gone = missing(locale, inputs)
    if gone:
        raise SystemExit("walk inputs missing: " + ", ".join(gone))
    background = os.path.join(inputs, "background.mp4")
    app_path = os.path.join(inputs, locale, "app.mp4")
    hand = load_hand(os.path.join(inputs, "hand.png"))
    hand_img = Image.open(hand["path"]).convert("RGBA")
    app_size = _size(app_path)
    app_seconds = _duration(app_path)
    speed = app_speed(app_seconds, seconds)
    count = seconds * fps

    for name, spec in formats.items():
        canvas = spec["size"]
        lay = layout(hand, canvas)
        folder, filename = spec["out"]
        path = os.path.join(out, folder, locale, filename)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        ground = _frames(_decode(background, _ground_filter(canvas, fps), count),
                         canvas, count, "background.mp4", repeat_last=False)
        app = _frames(_decode(app_path, f"setpts=PTS/{speed:.6f},fps={fps}", count),
                      app_size, count, "app.mp4", repeat_last=True)
        encoder = subprocess.Popen(
            ["ffmpeg", "-v", "error", "-y",
             "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{canvas[0]}x{canvas[1]}",
             "-r", str(fps), "-i", "-",
             "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-shortest",
             "-c:v", "libx264", "-preset", "slow", "-crf", "16",
             "-profile:v", "high", "-pix_fmt", "yuv420p",
             "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", path],
            stdin=subprocess.PIPE)
        for i, (g, a) in enumerate(zip(ground, app)):
            encoder.stdin.write(compose(lay, i / fps, g, a, hand_img).tobytes())
        ground.close()
        app.close()
        encoder.stdin.close()
        if encoder.wait():
            raise RuntimeError(f"ffmpeg failed for {path}")
        print(f"  {os.path.relpath(path, out)}")

        if spec["still"]:
            filename, still_size = spec["still"]
            still_lay = layout(hand, still_size)
            t = STILL_AT * seconds
            (g,) = _frames(_decode(background, _ground_filter(still_size, fps), 1, t),
                           still_size, 1, "background.mp4", repeat_last=False)
            (a,) = _frames(_decode(app_path, "null", 1, STILL_AT * app_seconds),
                           app_size, 1, "app.mp4", repeat_last=False)
            still = os.path.join(out, folder, locale, filename)
            Image.fromarray(compose(still_lay, t, g, a, hand_img)).save(still)
            print(f"  {os.path.relpath(still, out)}")


if __name__ == "__main__":
    import board

    for loc in sys.argv[1:] or list(board.STRINGS):
        print(f"[{loc}] walking video")
        render(loc, INPUTS, board.MANUAL, FORMATS)
