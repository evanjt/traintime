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

    def test_duo_set_is_all_opened_landscape(self):
        for stem, _, _, _, device, canvas in board.duo_shots(board.STRINGS["en-AU"]):
            self.assertEqual((device, canvas), ("iphone-duo-inner-landscape", board.DUO), stem)

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

    def test_render_writes_every_duo_shot_in_every_locale_opened_landscape(self):
        self.assertEqual(board.duo_missing(), [])
        with tempfile.TemporaryDirectory() as out, mock.patch.object(board, "STORE", out), \
                mock.patch.object(board, "_framed", {}):
            for locale, strings in board.STRINGS.items():
                board.build_locale(locale, strings, board.DUO, "appstore-duo", "swiss")
                for i in range(1, board.SHOT_COUNT + 1):
                    image = Image.open(os.path.join(out, "appstore-duo", locale, f"{i:02d}.png"))
                    self.assertEqual(image.size, (2853, 2007), (locale, i))

    def test_duo_hero_pairs_the_open_phone_with_its_folded_front(self):
        self.assertEqual(sorted(board.DUO_FRONTS), ["01"])
        _, _, w, h = frame.screen_rect(board.FRONT_DEVICE)
        for stem, capture in board.DUO_FRONTS.items():
            self.assertEqual(os.path.dirname(capture), os.path.join(board.CAPTURES, "iphone-duo"))
            self.assertEqual(Image.open(capture).size, (w, h), stem)

    def test_duo_missing_names_an_absent_folded_front(self):
        absent = os.path.join(board.CAPTURES, "iphone-duo", "absent-outer-raw.png")
        with mock.patch.object(board, "DUO_FRONTS", {"01": absent}):
            self.assertEqual(board.duo_missing(), [absent])

    def test_hero_open_phone_runs_off_one_edge_with_the_folded_front_overlapping(self):
        canvas = board.DUO
        open_art, front_art = (3093, 2247), (1574, 2194)
        lay = board.hero_layout(canvas, 458, 97, open_art, front_art)
        ox, oy, ow, oh = lay["open"]
        fx, fy, fw, fh = lay["front"]
        width, height = canvas
        self.assertGreater(ox + ow, width)
        self.assertGreaterEqual(ox, 0)
        self.assertEqual((oy, oy + oh), (458, height - 97))
        self.assertAlmostEqual(fh / front_art[1], oh / open_art[1], places=2)
        self.assertLess(fx, ox)
        self.assertGreater(fx + fw, ox)
        self.assertGreaterEqual(fx, 97)
        self.assertGreater(fy + fh, oy + oh)
        self.assertLessEqual(fy + fh, height)

    def test_render_builds_duo_shot_one_from_inner_and_outer_captures(self):
        used = []
        real = board.framed

        def spy(device, capture):
            used.append((device, capture))
            return real(device, capture)

        with tempfile.TemporaryDirectory() as out, mock.patch.object(board, "STORE", out), \
                mock.patch.object(board, "_framed", {}), mock.patch.object(board, "framed", spy):
            for locale, strings in board.STRINGS.items():
                used.clear()
                board.build_locale(locale, strings, board.DUO, "appstore-duo", "swiss")
                self.assertIn(("iphone-duo-inner-landscape", board.duo_shots(strings)[0][1]), used)
                self.assertIn((board.FRONT_DEVICE, board.DUO_FRONTS["01"]), used)
                image = Image.open(os.path.join(out, "appstore-duo", locale, "01.png"))
                self.assertEqual((image.size, image.mode), ((2853, 2007), "RGB"), locale)

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


APPLE_SHOTS = os.path.join(board.REPO, "apple", "fastlane", "screenshots")
PLAY_META = os.path.join(board.REPO, "android", "fastlane", "metadata", "android")
INSTALLED_APPLE_LOCALES = ["en-AU", "en-GB", "de-DE", "fr-FR", "it"]
INSTALLED_PLAY_LOCALES = ["en-AU", "en-GB", "de-DE", "fr-FR", "it-IT"]
# The Duo set still mixes postures until it is recaptured open like a book.
MIXED_SETS = {"duo"}


def installed_sets():
    """Installed store sets as {(store, locale, set): [image sizes]}: App Store
    files grouped by their name prefix, Play files by their folder."""
    sets = {}
    for locale in INSTALLED_APPLE_LOCALES:
        folder = os.path.join(APPLE_SHOTS, locale)
        for name in sorted(os.listdir(folder)):
            prefix = name.rsplit("-", 1)[0] if "-" in name else "iphone"
            sets.setdefault(("appstore", locale, prefix), []).append(
                Image.open(os.path.join(folder, name)).size)
    for locale in INSTALLED_PLAY_LOCALES:
        images = os.path.join(PLAY_META, locale, "images")
        for slot in sorted(os.listdir(images)):
            folder = os.path.join(images, slot)
            if os.path.isdir(folder):
                sets[("play", locale, slot)] = [Image.open(os.path.join(folder, name)).size
                                                for name in sorted(os.listdir(folder))]
    return sets


class SingleOrientation(unittest.TestCase):
    def test_every_installed_store_set_keeps_one_orientation(self):
        sets = installed_sets()
        self.assertIn(("appstore", "en-AU", "ipad"), sets)
        for key, sizes in sets.items():
            if key[2] in MIXED_SETS:
                continue
            self.assertEqual(len({w > h for w, h in sizes}), 1, (key, sizes))


class IpadSet(unittest.TestCase):
    def test_ipad_sizes_are_the_thirteen_inch_slot(self):
        self.assertEqual(board.IPAD_SIZES, {(2064, 2752), (2752, 2064)})
        self.assertIn(board.IPAD, board.IPAD_SIZES)

    def test_every_ipad_shot_canvas_is_an_accepted_size_matching_its_frame(self):
        for stem, _, _, _, device, canvas in board.ipad_shots(board.STRINGS["en-AU"]):
            self.assertIn(canvas, board.IPAD_SIZES, stem)
            _, _, w, h = frame.screen_rect(device)
            self.assertEqual(w > h, canvas[0] > canvas[1], stem)

    def test_ipad_set_is_all_landscape(self):
        for locale, strings in board.STRINGS.items():
            for stem, _, _, _, device, canvas in board.ipad_shots(strings):
                self.assertEqual(canvas, board.IPAD, (locale, stem))
                self.assertEqual(device, "ipad-landscape", (locale, stem))

    def test_installed_ipad_shots_are_all_landscape(self):
        for locale in INSTALLED_APPLE_LOCALES:
            folder = os.path.join(APPLE_SHOTS, locale)
            for i in range(1, board.SHOT_COUNT + 1):
                image = Image.open(os.path.join(folder, f"ipad-{i:02d}.png"))
                self.assertEqual(image.size, board.IPAD, (locale, i))

    def test_ipad_captures_fill_their_frame_unscaled(self):
        self.assertEqual(board.ipad_missing(), [])
        for stem, capture, _, _, device, _ in board.ipad_shots(board.STRINGS["en-AU"]):
            self.assertEqual(os.path.dirname(capture), os.path.join(board.CAPTURES, "ipad"))
            _, _, w, h = frame.screen_rect(device)
            self.assertEqual(Image.open(capture).size, (w, h), stem)

    def test_ipad_device_fills_the_canvas_below_the_caption(self):
        for stem, _, _, _, device, canvas in board.ipad_shots(board.STRINGS["en-AU"]):
            art = Image.open(os.path.join(frame.FRAMES, frame.DEVICES[device]["art"]))
            _, _, sw, _ = frame.screen_rect(device)
            art_size = art.size[::-1] if frame.DEVICES[device].get("rotate") else art.size
            layout = board.phone_layout(canvas, art_size, sw)
            below = canvas[1] - layout["stage_top"]
            self.assertGreaterEqual(layout["devh"], 0.8 * below, stem)
            self.assertLessEqual(layout["devw"], canvas[0] - 2 * layout["pad"], stem)

    def test_render_writes_the_ipad_set_for_all_four_locales_at_accepted_sizes_in_rgb(self):
        with tempfile.TemporaryDirectory() as out, mock.patch.object(board, "STORE", out), \
                mock.patch.object(board, "_framed", {}):
            for locale, strings in board.STRINGS.items():
                board.build_locale(locale, strings, board.IPAD, "appstore-ipad", "swiss")
                expected = [canvas for *_, canvas in board.ipad_shots(strings)] + [board.IPAD]
                for i, canvas in enumerate(expected, 1):
                    image = Image.open(os.path.join(out, "appstore-ipad", locale, f"{i:02d}.png"))
                    self.assertEqual(image.size, canvas, (locale, i))
                    self.assertEqual(image.mode, "RGB", (locale, i))


class IpadRelease(unittest.TestCase):
    def test_ipad_ships_from_its_release_on(self):
        self.assertFalse(board.ipad_enabled("0.9.1"))
        self.assertTrue(board.ipad_enabled(board.IPAD_FROM))
        self.assertTrue(board.ipad_enabled("1.0.0"))

    def test_apple_set_holds_ipad_back_before_its_release(self):
        names = [dest for _, dest in board.apple_set("en-AU", "0.9.1")]
        self.assertFalse([name for name in names if name.startswith("ipad-")])

    def test_apple_set_carries_ipad_from_its_release(self):
        files = board.apple_set("en-AU", board.IPAD_FROM)
        ipad = [(src, dest) for src, dest in files if dest.startswith("ipad-")]
        self.assertEqual([dest for _, dest in ipad],
                         [f"ipad-{i:02d}.png" for i in range(1, board.SHOT_COUNT + 1)])
        for src, _ in ipad:
            self.assertEqual(os.path.dirname(src), os.path.join(board.STORE, "appstore-ipad", "en-AU"))

    def test_install_puts_the_ipad_set_in_the_apple_locale_folder(self):
        with tempfile.TemporaryDirectory() as repo:
            out = os.path.join(repo, "out")
            for subdir in ("appstore", "appstore-duo", "appstore-ipad", "play", "play-large"):
                os.makedirs(os.path.join(out, subdir, "it-IT"))
                for i in range(1, board.SHOT_COUNT + 1):
                    Image.new("RGB", (8, 8)).save(os.path.join(out, subdir, "it-IT", f"{i:02d}.png"))
            os.makedirs(os.path.join(out, "feature", "it-IT"))
            Image.new("RGB", (8, 8)).save(os.path.join(out, "feature", "it-IT", "featureGraphic.png"))
            with mock.patch.object(board, "STORE", out), mock.patch.object(board, "REPO", repo), \
                    mock.patch.object(board, "SITE", os.path.join(repo, "site")), \
                    mock.patch.object(board, "marketing_version", return_value=board.IPAD_FROM), \
                    mock.patch.object(board, "duo_missing", return_value=[]), \
                    mock.patch.object(board, "ipad_missing", return_value=[]):
                board.install(["it-IT"])
            shots = os.path.join(repo, "apple", "fastlane", "screenshots", "it")
            for i in range(1, board.SHOT_COUNT + 1):
                self.assertTrue(os.path.exists(os.path.join(shots, f"ipad-{i:02d}.png")), i)

    def test_install_refuses_an_ipad_release_without_its_captures(self):
        with mock.patch.object(board, "marketing_version", return_value=board.IPAD_FROM), \
                mock.patch.object(board, "duo_missing", return_value=[]), \
                mock.patch.object(board, "ipad_missing", return_value=["x.png"]):
            with self.assertRaises(SystemExit):
                board.install(["en-AU"])


if __name__ == "__main__":
    unittest.main()
