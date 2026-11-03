#!/usr/bin/env python3
"""Run from store/: python3 -m unittest test_board"""

import os
import unittest

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


if __name__ == "__main__":
    unittest.main()
