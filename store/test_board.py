#!/usr/bin/env python3
"""Run from store/: python3 -m unittest test_board"""

import os
import re
import tempfile
import unittest
from unittest import mock

from PIL import Image

import board
import frame


class DuoSet(unittest.TestCase):
    def test_duo_sizes_are_the_four_app_store_connect_accepts(self):
        self.assertEqual(board.DUO_SIZES, {(1398, 2034), (2034, 1398), (2007, 2853), (2853, 2007)})
        self.assertIn(board.DUO, board.DUO_SIZES)

    def test_every_duo_shot_canvas_is_an_accepted_size(self):
        for stem, _, _, _, _, canvas in board.duo_shots(board.STRINGS["en-AU"]):
            self.assertIn(canvas, board.DUO_SIZES, stem)

    def test_duo_set_mixes_orientations(self):
        canvases = [canvas for *_, canvas in board.duo_shots(board.STRINGS["en-AU"])]
        self.assertTrue(any(w > h for w, h in canvases))
        self.assertTrue(any(w < h for w, h in canvases))

    def test_duo_set_shows_each_posture_once(self):
        devices = [device for *_, device, _ in board.duo_shots(board.STRINGS["en-AU"])]
        self.assertEqual(devices, ["iphone-duo-inner-landscape", "iphone-duo-inner", "iphone-duo-outer"])

    def test_duo_canvas_matches_its_posture(self):
        for stem, _, _, _, device, canvas in board.duo_shots(board.STRINGS["en-AU"]):
            _, _, w, h = frame.screen_rect(device)
            self.assertEqual(w > h, canvas[0] > canvas[1], stem)

    def test_duo_captures_fill_their_frame_unscaled(self):
        for stem, capture, _, _, device, _ in board.duo_shots(board.STRINGS["en-AU"]):
            _, _, w, h = frame.screen_rect(device)
            self.assertEqual(Image.open(capture).size, (w, h), stem)

    def test_duo_device_fills_the_canvas_below_the_caption(self):
        for stem, capture, _, _, device, canvas in board.duo_shots(board.STRINGS["en-AU"]):
            art = Image.open(os.path.join(frame.FRAMES, frame.DEVICES[device]["art"]))
            _, _, sw, _ = frame.screen_rect(device)
            art_size = art.size[::-1] if frame.DEVICES[device].get("rotate") else art.size
            width, height = canvas
            layout = board.phone_layout(canvas, art_size, sw)
            below = height - layout["stage_top"]
            self.assertGreaterEqual(layout["devh"], 0.8 * below, stem)
            self.assertLessEqual(layout["devw"], width - 2 * layout["pad"], stem)
            self.assertLessEqual(layout["devh"], below - layout["pad"] + 1, stem)

    def test_six_point_nine_layout_is_unchanged(self):
        layout = board.phone_layout((1320, 2868), (1000, 2000), 900)
        self.assertEqual(layout["pad"], int(1320 * 0.078))
        self.assertEqual(layout["devw"], int(1320 * 0.79 * 1000 / 900))

    def test_render_writes_the_duo_set_for_all_four_locales_at_accepted_sizes(self):
        self.assertEqual(board.duo_missing(), [])
        with tempfile.TemporaryDirectory() as out, mock.patch.object(board, "STORE", out), \
                mock.patch.object(board, "_framed", {}):
            for locale, strings in board.STRINGS.items():
                board.build_locale(locale, strings, board.DUO, "appstore-duo", "swiss")
                expected = [canvas for *_, canvas in board.duo_shots(strings)] + [board.DUO]
                for i, canvas in enumerate(expected, 1):
                    image = Image.open(os.path.join(out, "appstore-duo", locale, f"{i:02d}.png"))
                    self.assertEqual(image.size, canvas, (locale, i))

    def test_other_sets_keep_their_frames(self):
        self.assertEqual(board.shot_device("appstore"), "iphone")
        self.assertEqual(board.shot_device("play"), "android")

    def test_duo_shots_use_duo_captures(self):
        for _, capture, _, _, _, _ in board.duo_shots(board.STRINGS["en-AU"]):
            self.assertEqual(os.path.dirname(capture), os.path.join(board.CAPTURES, "iphone-duo"))

    def test_six_point_nine_shots_never_use_duo_captures(self):
        strings = board.STRINGS["en-AU"]
        for _, capture, _, _ in board.shots("en-AU", strings, "appstore"):
            self.assertEqual(os.path.dirname(capture), os.path.join(board.CAPTURES, "iphone"))


class DuoUpload(unittest.TestCase):
    def test_pinned_deliver_files_every_duo_size_under_the_duo_display_type(self):
        lock = os.path.join(board.REPO, "apple", "fastlane", "Gemfile.lock")
        with open(lock) as f:
            pinned = re.search(r"^    fastlane \(([\d.]+)\)$", f.read(), re.M).group(1)
        self.assertGreaterEqual(board.version_tuple(pinned), board.version_tuple(board.DELIVER_DUO_FROM))


class DuoRelease(unittest.TestCase):
    def test_duo_ships_from_its_release_on(self):
        self.assertFalse(board.duo_enabled("0.9.0"))
        self.assertFalse(board.duo_enabled("0.9.12"))
        self.assertTrue(board.duo_enabled(board.DUO_FROM))
        self.assertTrue(board.duo_enabled("0.10.1"))
        self.assertTrue(board.duo_enabled("1.0.0"))

    def test_apple_set_holds_duo_back_before_its_release(self):
        names = [dest for _, dest in board.apple_set("en-AU", "0.9.0")]
        self.assertEqual(names, ["01.png", "02.png", "03.png", "04.png",
                                 "watch-01.png", "watch-02.png"])

    def test_apple_set_carries_duo_from_its_release(self):
        files = board.apple_set("en-AU", board.DUO_FROM)
        duo = [(src, dest) for src, dest in files if dest.startswith("duo-")]
        self.assertEqual([dest for _, dest in duo],
                         [f"duo-{i:02d}.png" for i in range(1, board.SHOT_COUNT + 1)])
        for src, _ in duo:
            self.assertEqual(os.path.dirname(src), os.path.join(board.STORE, "appstore-duo", "en-AU"))

    def test_marketing_version_reads_the_project(self):
        self.assertRegex(board.marketing_version(), r"^\d+\.\d+\.\d+$")


class PlayLargeScreenSet(unittest.TestCase):
    def test_large_shots_use_unfolded_foldable_captures(self):
        strings = board.STRINGS["en-AU"]
        for _, capture, _, _ in board.shots("en-AU", strings, "play-large"):
            self.assertEqual(os.path.dirname(capture), os.path.join(board.CAPTURES, "android-fold"))
            self.assertTrue(os.path.exists(capture), capture)

    def test_large_shots_fill_the_foldable_frame_unscaled(self):
        device = board.shot_device("play-large")
        self.assertEqual(device, "android-fold")
        _, _, w, h = frame.screen_rect(device)
        for _, capture, _, _ in board.shots("en-AU", board.STRINGS["en-AU"], "play-large"):
            self.assertEqual(Image.open(capture).size, (w, h))

    def test_large_canvas_meets_the_tablet_rule(self):
        self.assertEqual(board.tablet_problems(board.LARGE, "RGB", 1_000_000), [])

    def test_tablet_rule_rejects_what_play_refuses(self):
        self.assertTrue(board.tablet_problems((2076, 2152), "RGB", 1))
        self.assertTrue(board.tablet_problems((960, 540), "RGB", 1))
        self.assertTrue(board.tablet_problems((7700, 4331), "RGB", 1))
        self.assertTrue(board.tablet_problems(board.LARGE, "RGBA", 1))
        self.assertTrue(board.tablet_problems(board.LARGE, "RGB", 9 * 1024 * 1024))

    def test_large_set_ships_from_its_release(self):
        self.assertEqual(board.play_large_set("en-AU", "0.9.0"), [])
        files = board.play_large_set("en-AU", board.LARGE_FROM)
        for slot in board.TABLET_SLOTS:
            names = [name for src, (s, name) in files if s == slot]
            self.assertEqual(names, [f"{i:02d}.png" for i in range(1, board.SHOT_COUNT + 1)])
        for src, _ in files:
            self.assertEqual(os.path.dirname(src), os.path.join(board.STORE, "play-large", "en-AU"))

    def test_render_writes_the_set_for_all_four_locales_at_a_size_play_accepts(self):
        with tempfile.TemporaryDirectory() as out, mock.patch.object(board, "STORE", out), \
                mock.patch.object(board, "_framed", {}):
            for locale, strings in board.STRINGS.items():
                board.build_large(locale, strings, "swiss")
                for i in range(1, board.SHOT_COUNT + 1):
                    path = os.path.join(out, "play-large", locale, f"{i:02d}.png")
                    image = Image.open(path)
                    self.assertEqual(image.size, board.LARGE)
                    self.assertEqual(board.tablet_problems(image.size, image.mode, os.path.getsize(path)), [])


if __name__ == "__main__":
    unittest.main()
