#!/usr/bin/env python3
"""Run from store/: python3 -m unittest test_frame"""

import unittest

from PIL import Image, ImageChops, ImageDraw

import frame


class DeviceArt(unittest.TestCase):
    def test_screen_never_shows_outside_the_device_art(self):
        for device, spec in frame.DEVICES.items():
            if "art" not in spec:
                continue
            _, _, w, h = frame.screen_rect(device)
            framed = frame.frame_device(device, Image.new("RGB", (w, h), "white"))
            art = frame._art(spec)
            outside = art.getchannel("A").point(lambda a: 255 if a == 0 else 0)
            ImageDraw.floodfill(outside, (0, 0), 128)
            outside = outside.point(lambda v: 255 if v == 128 else 0)
            shown = framed.getchannel("A").point(lambda a: 255 if a else 0)
            self.assertIsNone(ImageChops.multiply(outside, shown).getbbox(), device)
