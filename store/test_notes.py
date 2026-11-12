#!/usr/bin/env python3
"""Run from store/: python3 -m unittest test_notes"""

import glob
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPLE = os.path.join(ROOT, "apple", "fastlane", "metadata")
PLAY = os.path.join(ROOT, "android", "fastlane", "metadata", "android")

PLAY_LIMIT = 500
APP_STORE_LIMIT = 4000

LANGUAGES = {"en", "de", "fr", "it"}


def version_code(module):
    with open(os.path.join(ROOT, "android", module, "build.gradle.kts"), encoding="utf-8") as f:
        return re.search(r"versionCode = (\d+)", f.read()).group(1)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def language(locale):
    return locale.split("-")[0]


class PlayChangelogs(unittest.TestCase):
    def test_every_changelog_fits_the_play_limit(self):
        paths = glob.glob(os.path.join(PLAY, "*", "changelogs", "*.txt"))
        self.assertTrue(paths)
        for path in paths:
            self.assertLessEqual(len(read(path)), PLAY_LIMIT, path)

    def test_every_locale_has_phone_and_wear_notes(self):
        for locale in os.listdir(PLAY):
            for module in ("app", "wear"):
                path = os.path.join(PLAY, locale, "changelogs", version_code(module) + ".txt")
                self.assertTrue(os.path.isfile(path), path)


class PhoneNotes(unittest.TestCase):
    def phone_notes(self):
        code = version_code("app")
        for locale in os.listdir(APPLE):
            path = os.path.join(APPLE, locale, "release_notes.txt")
            if os.path.isfile(path):
                yield locale, path
        for locale in os.listdir(PLAY):
            yield locale, os.path.join(PLAY, locale, "changelogs", code + ".txt")

    def test_phone_notes_cover_every_language_within_the_store_limit(self):
        notes = list(self.phone_notes())
        self.assertEqual({language(l) for l, _ in notes}, LANGUAGES)
        for _, path in notes:
            text = read(path).strip()
            self.assertTrue(text, path)
            limit = APP_STORE_LIMIT if path.startswith(APPLE) else PLAY_LIMIT
            self.assertLessEqual(len(read(path)), limit, path)

    def test_no_em_dashes(self):
        for _, path in self.phone_notes():
            self.assertNotIn("—", read(path), path)

    def test_english_locales_match(self):
        code = version_code("app")
        self.assertEqual(read(os.path.join(APPLE, "en-AU", "release_notes.txt")),
                         read(os.path.join(APPLE, "en-GB", "release_notes.txt")))
        self.assertEqual(read(os.path.join(PLAY, "en-AU", "changelogs", code + ".txt")),
                         read(os.path.join(PLAY, "en-GB", "changelogs", code + ".txt")))


class AppStoreNotes(unittest.TestCase):
    def test_every_locale_names_ipad_within_the_limit(self):
        locales = sorted(l for l in os.listdir(APPLE)
                         if os.path.isfile(os.path.join(APPLE, l, "release_notes.txt")))
        self.assertEqual({language(l) for l in locales}, LANGUAGES)
        for locale in locales:
            text = read(os.path.join(APPLE, locale, "release_notes.txt"))
            self.assertIn("iPad", text, locale)
            self.assertLessEqual(len(text), APP_STORE_LIMIT, locale)


if __name__ == "__main__":
    unittest.main()
