#!/usr/bin/env python3
"""Run from store/: python3 -m unittest test_site"""

import os
import re
import unittest

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")

IMAGE_LIMIT = 400 * 1024


def page():
    with open(os.path.join(DOCS, "index.html"), encoding="utf-8") as f:
        return f.read()


def band(html, platform):
    match = re.search(rf'<div class="gallery-band[^"]*" id="band-{platform}">(.*?)\n        </div>\n',
                      html, re.S)
    return match.group(1)


class UnfoldedGalleryTest(unittest.TestCase):
    def test_iphone_band_ends_with_the_unfolded_shot(self):
        shots = re.findall(r'<img src="(img/[^"]+)"', band(page(), "iphone"))
        self.assertEqual(len(shots), 4)
        self.assertEqual(shots[-1], "img/iphone/04-unfolded.png")
        self.assertIn('<div class="watch-label">Unfolded</div>', band(page(), "iphone"))

    def test_unfolded_shot_is_small_and_as_tall_as_the_phones(self):
        path = os.path.join(DOCS, "img", "iphone", "04-unfolded.png")
        self.assertLess(os.path.getsize(path), IMAGE_LIMIT)
        unfolded = Image.open(path)
        phone = Image.open(os.path.join(DOCS, "img", "iphone", "01-station-view.png"))
        self.assertEqual(unfolded.height, phone.height)
        self.assertGreater(unfolded.width, unfolded.height)

    def test_no_new_tab(self):
        tabs = re.findall(r'data-platform="(\w+)"', page())
        self.assertEqual(tabs, ["apple", "wear", "garmin", "iphone"])

    def test_compatibility_note_under_the_gallery(self):
        gallery = re.search(r'<section class="gallery-section">(.*?)</section>', page(), re.S).group(1)
        self.assertIn("Also adapts to iPhone Duo and Android foldables", gallery)


if __name__ == "__main__":
    unittest.main()
