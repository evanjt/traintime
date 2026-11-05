#!/usr/bin/env python3
"""Run from store/: python3 -m unittest test_board"""

import os
import tempfile
import unittest
from unittest import mock

from PIL import Image

import board
import frame


class DuoSet(unittest.TestCase):
    def test_duo_shots_go_in_the_inner_display_frame(self):
        device = board.shot_device("appstore-duo")
        self.assertEqual(device, "iphone-duo-inner")
        _, _, w, h = frame.screen_rect(device)
        self.assertEqual((w, h), board.DUO)

    def test_other_sets_keep_their_frames(self):
        self.assertEqual(board.shot_device("appstore"), "iphone")
        self.assertEqual(board.shot_device("play"), "android")

    def test_duo_shots_use_inner_display_captures(self):
        strings = board.STRINGS["en-AU"]
        for _, capture, _, _ in board.shots("en-AU", strings, "appstore-duo"):
            self.assertEqual(os.path.dirname(capture), os.path.join(board.CAPTURES, "iphone-duo"))
            self.assertTrue(capture.endswith("-inner-raw.png"), capture)

    def test_six_point_nine_shots_never_use_duo_captures(self):
        strings = board.STRINGS["en-AU"]
        for _, capture, _, _ in board.shots("en-AU", strings, "appstore"):
            self.assertEqual(os.path.dirname(capture), os.path.join(board.CAPTURES, "iphone"))


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
    @unittest.skipUnless(os.path.isdir(os.path.join(board.CAPTURES, "android-fold")), "no unfolded foldable captures yet")
    def test_large_shots_use_unfolded_foldable_captures(self):
        strings = board.STRINGS["en-AU"]
        for _, capture, _, _ in board.shots("en-AU", strings, "play-large"):
            self.assertEqual(os.path.dirname(capture), os.path.join(board.CAPTURES, "android-fold"))
            self.assertTrue(os.path.exists(capture), capture)

    @unittest.skipUnless(os.path.isdir(os.path.join(board.CAPTURES, "android-fold")), "no unfolded foldable captures yet")
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

    @unittest.skipUnless(os.path.isdir(os.path.join(board.CAPTURES, "android-fold")), "no unfolded foldable captures yet")
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
