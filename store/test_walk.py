#!/usr/bin/env python3
"""Run from store/: python3 -m unittest test_walk"""

import json
import os
import subprocess
import tempfile
import unittest

from PIL import Image, ImageDraw

import walk

# A hand photo in hand.png pixels: the screen quad, slightly keystoned, and the
# hand running off the bottom of the photo.
HAND_SIZE = (400, 900)
SCREEN = [[100, 120], [300, 130], [295, 560], [105, 565]]


def hand_photo(path, size=HAND_SIZE, screen=SCREEN):
    img = Image.new("RGBA", size, (30, 60, 200, 255))
    ImageDraw.Draw(img).polygon([tuple(p) for p in screen], fill=(0, 0, 0, 0))
    img.save(path)
    with open(os.path.splitext(path)[0] + ".json", "w") as f:
        json.dump({"screen": screen}, f)


def clip(path, colour, size, seconds):
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "lavfi",
         "-i", f"color=c={colour}:s={size[0]}x{size[1]}:r=30:d={seconds}",
         "-pix_fmt", "yuv420p", path],
        check=True,
    )


def probe(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-count_frames",
         "-show_entries", "stream=width,height,nb_read_frames", "-of", "json", path],
        check=True, capture_output=True, text=True,
    ).stdout
    s = json.loads(out)["streams"][0]
    return s["width"], s["height"], int(s["nb_read_frames"])


class Sway(unittest.TestCase):
    def test_sway_returns_to_its_start_when_the_loop_ends(self):
        for name in walk.FORMATS:
            self.assertEqual(
                [round(v, 9) for v in walk.sway(0.0)],
                [round(v, 9) for v in walk.sway(walk.WALK_SECONDS)], name)

    def test_phone_bobs_once_a_step_and_swings_side_to_side_once_a_stride(self):
        step = 1 / walk.CADENCE
        for t in (0.13, 0.4, 1.7):
            dx, dy, angle = walk.sway(t)
            dx2, dy2, angle2 = walk.sway(t + step)
            self.assertAlmostEqual(dy, dy2)
            self.assertAlmostEqual(dx, -dx2)
            self.assertAlmostEqual(angle, -angle2)

    def test_whole_strides_fit_the_loop(self):
        strides = walk.WALK_SECONDS * walk.CADENCE / 2
        self.assertAlmostEqual(strides, round(strides))


class AppTime(unittest.TestCase):
    def test_route_recording_is_compressed_into_the_loop(self):
        self.assertEqual(walk.app_speed(300.0, 20), 15.0)

    def test_recording_shorter_than_the_loop_is_refused(self):
        with self.assertRaises(SystemExit):
            walk.app_speed(12.0, 20)


class Warp(unittest.TestCase):
    def test_perspective_maps_the_app_frame_corners_onto_the_screen_quad(self):
        quad = [(10.0, 20.0), (200.0, 35.0), (190.0, 400.0), (15.0, 380.0)]
        coeffs = walk.perspective(quad, (120, 260))
        a, b, c, d, e, f, g, h = coeffs
        for (x, y), (u, v) in zip(quad, [(0, 0), (120, 0), (120, 260), (0, 260)]):
            w = g * x + h * y + 1
            self.assertAlmostEqual((a * x + b * y + c) / w, u, places=6)
            self.assertAlmostEqual((d * x + e * y + f) / w, v, places=6)


class Layout(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.hand = os.path.join(self.dir, "hand.png")

    def test_screen_stays_inside_the_frame_and_the_hand_runs_off_the_bottom(self):
        hand_photo(self.hand)
        for name, spec in walk.FORMATS.items():
            w, h = spec["size"]
            lay = walk.layout(walk.load_hand(self.hand), (w, h))
            for t in (0.0, 0.21, 0.5, 1.3):
                quad, box = walk.place(lay, t)
                for x, y in quad:
                    self.assertTrue(0 <= x <= w and 0 <= y <= h, (name, t, x, y))
                self.assertGreater(box[3], h, (name, t))

    def test_hand_photo_cut_off_above_the_frame_bottom_is_refused(self):
        hand_photo(self.hand, size=(400, 600))
        with self.assertRaises(SystemExit):
            walk.layout(walk.load_hand(self.hand), (1920, 1080))


class Render(unittest.TestCase):
    def test_render_puts_the_app_in_the_screen_over_the_walk_in_every_format(self):
        inputs = tempfile.mkdtemp()
        out = tempfile.mkdtemp()
        hand_photo(os.path.join(inputs, "hand.png"))
        clip(os.path.join(inputs, "background.mp4"), "red", (320, 180), 2)
        os.makedirs(os.path.join(inputs, "xx-XX"))
        clip(os.path.join(inputs, "xx-XX", "app.mp4"), "lime", (120, 260), 3)
        formats = {
            "header": dict(size=(210, 90), out=("app-store", "walk-header.mp4"), still=None),
            "search": dict(size=(150, 100), out=("app-store", "walk-search.mp4"),
                           still=("walk-search.png", (180, 120))),
        }
        walk.render("xx-XX", inputs, out, formats, seconds=1, fps=10)
        for name, spec in formats.items():
            path = os.path.join(out, spec["out"][0], "xx-XX", spec["out"][1])
            w, h = spec["size"]
            self.assertEqual(probe(path), (w, h, 10), name)
            mid = subprocess.run(
                ["ffmpeg", "-v", "error", "-i", path, "-frames:v", "1",
                 "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                check=True, capture_output=True,
            ).stdout
            frame = Image.frombytes("RGB", (w, h), mid)
            lay = walk.layout(walk.load_hand(os.path.join(inputs, "hand.png")), (w, h))
            quad, _ = walk.place(lay, 0.0)
            cx = sum(x for x, _ in quad) / 4
            cy = sum(y for _, y in quad) / 4
            r, g, b = frame.getpixel((int(cx), int(cy)))
            self.assertTrue(g > 150 and r < 100 and b < 100, (name, r, g, b))
            r, g, b = frame.getpixel((2, 2))
            self.assertTrue(r > 150 and g < 100, (name, r, g, b))
        with Image.open(os.path.join(out, "app-store", "xx-XX", "walk-search.png")) as still:
            self.assertEqual((still.size, still.mode), ((180, 120), "RGB"))

    def test_missing_inputs_are_named(self):
        inputs = tempfile.mkdtemp()
        with self.assertRaises(SystemExit) as caught:
            walk.render("xx-XX", inputs, tempfile.mkdtemp(), walk.FORMATS)
        for name in ("background.mp4", "hand.png", "app.mp4"):
            self.assertIn(name, str(caught.exception))


if __name__ == "__main__":
    unittest.main()
