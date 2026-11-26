"""Run from apple/: python3 -m unittest test_sim"""

import json
import os
import shutil
import stat
import subprocess
import tempfile
import unittest

import simpick

HERE = os.path.dirname(os.path.abspath(__file__))

IOS_OLD = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
IOS_NEW = "com.apple.CoreSimulator.SimRuntime.iOS-27-1"
WATCH_OLD = "com.apple.CoreSimulator.SimRuntime.watchOS-9-4"
WATCH_NEW = "com.apple.CoreSimulator.SimRuntime.watchOS-10-0"


def device(udid, name, kind, *, available=True):
    return {
        "udid": udid,
        "name": name,
        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType." + kind,
        "isAvailable": available,
        "state": "Shutdown",
    }


PRO = device("UDID-PRO", "iPhone 18 Pro", "iPhone-18-Pro")
PRO_MAX = device("UDID-PRO-MAX", "iPhone 18 Pro Max", "iPhone-18-Pro-Max")
OLDER_PRO_MAX = device("UDID-OLDER-PRO-MAX", "iPhone 17 Pro Max", "iPhone-17-Pro-Max")
DUO = device("UDID-DUO", "iPhone Duo", "iPhone-Duo")
DUO_COPY = device("UDID-DUO-COPY", "scratch copy", "iPhone-Duo")
IPAD = device("UDID-IPAD", "iPad Pro 13-inch (M5)", "iPad-Pro-13-inch-M5-16GB")
WATCH = device("UDID-WATCH", "Apple Watch Series 12 (46mm)", "Apple-Watch-Series-12-46mm")
WATCH_ULTRA = device("UDID-WATCH-ULTRA", "Apple Watch Ultra 4 (49mm)", "Apple-Watch-Ultra-4-49mm")
WATCH_ON_OLD = device("UDID-WATCH-OLD", "Apple Watch Series 8 (45mm)", "Apple-Watch-Series-8-45mm")

# The newest iOS runtime is listed first and carries the Duo only, as simctl prints it.
LISTING = {
    "devices": {
        IOS_NEW: [DUO, DUO_COPY],
        WATCH_OLD: [WATCH_ON_OLD],
        WATCH_NEW: [WATCH, WATCH_ULTRA],
        IOS_OLD: [PRO, PRO_MAX],
    }
}


def listing(**runtimes):
    return {"devices": runtimes}


class Pick(unittest.TestCase):
    def test_phone_takes_the_standard_iphone_over_the_duo_on_a_newer_runtime(self):
        self.assertEqual(simpick.pick(LISTING, "phone"), ("UDID-PRO-MAX", "iPhone 18 Pro Max"))

    def test_phone_takes_the_newest_generation_before_the_larger_model(self):
        devices = listing(**{IOS_OLD: [OLDER_PRO_MAX, PRO]})
        self.assertEqual(simpick.pick(devices, "phone")[0], "UDID-PRO")

    def test_phone_takes_the_newest_runtime_that_carries_a_standard_iphone(self):
        devices = listing(**{IOS_NEW: [PRO], IOS_OLD: [PRO_MAX]})
        self.assertEqual(simpick.pick(devices, "phone")[0], "UDID-PRO")

    def test_phone_falls_back_to_the_duo_when_no_standard_iphone_is_installed(self):
        devices = listing(**{IOS_NEW: [DUO_COPY, DUO], WATCH_NEW: [WATCH]})
        self.assertEqual(simpick.pick(devices, "phone"), ("UDID-DUO-COPY", "scratch copy"))

    def test_phone_falls_back_to_an_ipad_when_no_iphone_is_installed(self):
        devices = listing(**{IOS_NEW: [IPAD], WATCH_NEW: [WATCH]})
        self.assertEqual(simpick.pick(devices, "phone")[0], "UDID-IPAD")

    def test_duo_takes_the_duo_only(self):
        self.assertEqual(simpick.pick(LISTING, "duo")[0], "UDID-DUO")
        with self.assertRaises(LookupError):
            simpick.pick(listing(**{IOS_OLD: [PRO, IPAD]}), "duo")

    def test_watch_takes_the_first_watch_on_the_newest_runtime_by_number(self):
        self.assertEqual(simpick.pick(LISTING, "watch"), ("UDID-WATCH", "Apple Watch Series 12 (46mm)"))

    def test_unavailable_devices_are_passed_over(self):
        gone = device("UDID-GONE", "iPhone 18 Pro Max", "iPhone-18-Pro-Max", available=False)
        devices = listing(**{IOS_OLD: [gone, PRO]})
        self.assertEqual(simpick.pick(devices, "phone")[0], "UDID-PRO")

    def test_no_device_of_the_platform_is_an_error(self):
        with self.assertRaises(LookupError):
            simpick.pick(listing(**{IOS_OLD: [PRO]}), "watch")
        with self.assertRaises(LookupError):
            simpick.pick(listing(**{WATCH_NEW: [WATCH]}), "phone")

    def test_a_given_udid_wins_over_the_default(self):
        self.assertEqual(simpick.pick(LISTING, "phone", "UDID-DUO-COPY"), ("UDID-DUO-COPY", "scratch copy"))

    def test_a_given_udid_that_is_not_available_is_an_error(self):
        with self.assertRaises(LookupError):
            simpick.pick(LISTING, "phone", "UDID-NOWHERE")

    def test_unknown_target_is_an_error(self):
        with self.assertRaises(LookupError):
            simpick.pick(LISTING, "tv")


STUB = """#!/bin/bash
printf '%s' "$(basename "$0")" >> "$CALLS"
printf '\\t%s' "$@" >> "$CALLS"
printf '\\n' >> "$CALLS"
"""

XCRUN = STUB + """
if [ "$1 $2" = "simctl list" ]; then
    case "$*" in
        *" -j"*) cat "$LISTING" ;;
        *booted*) cat "$BOOTED" ;;
    esac
fi
"""

XCODEBUILD = STUB + """
while [ $# -gt 0 ]; do
    if [ "$1" = "-derivedDataPath" ]; then
        derived="$2"
    fi
    if [ "$1" = "-scheme" ]; then
        scheme="$2"
    fi
    shift
done
case "$scheme" in
    TrainTimeWatch) mkdir -p "$derived/Build/Products/Debug-watchsimulator/TrainTimeWatch.app" ;;
    *) mkdir -p "$derived/Build/Products/Debug-iphonesimulator/TrainTimePhone.app" ;;
esac
"""

XCODE_SELECT = STUB + """
echo "$DEVELOPER"
"""


class Script(unittest.TestCase):
    """Scenario: sim.sh runs against stand-ins for xcrun, xcodebuild, xcode-select and open that
    record their arguments.
    Expected behaviour: every step addresses the picked simulator by udid."""

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir)
        apple = os.path.join(self.dir, "apple")
        os.makedirs(os.path.join(apple, "TrainTimeWatch"))
        for name in ("sim.sh", "simpick.py"):
            shutil.copy(os.path.join(HERE, name), apple)
        with open(os.path.join(apple, "TrainTimeWatch", "Secrets.swift"), "w", encoding="utf-8"):
            pass
        self.script = os.path.join(apple, "sim.sh")

        self.developer = os.path.join(self.dir, "Xcode.app", "Contents", "Developer")
        os.makedirs(self.developer)
        self.device_hub = os.path.join(self.dir, "Xcode.app", "Contents", "Applications", "DeviceHub.app")

        self.bin = os.path.join(self.dir, "bin")
        os.makedirs(self.bin)
        for name, body in (
            ("xcrun", XCRUN),
            ("xcodebuild", XCODEBUILD),
            ("xcode-select", XCODE_SELECT),
            ("open", STUB),
        ):
            path = os.path.join(self.bin, name)
            with open(path, "w", encoding="utf-8") as f:
                f.write(body)
            os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)

        self.calls = os.path.join(self.dir, "calls")
        self.listing = os.path.join(self.dir, "listing.json")
        with open(self.listing, "w", encoding="utf-8") as f:
            json.dump(LISTING, f)
        self.booted = os.path.join(self.dir, "booted")
        self.boot()

    def boot(self, *udids):
        with open(self.booted, "w", encoding="utf-8") as f:
            f.write("== Devices ==\n" + "".join("    a name (" + udid + ") (Booted)\n" for udid in udids))

    def run_script(self, *args, **env):
        environment = {
            "PATH": self.bin + os.pathsep + os.environ["PATH"],
            "CALLS": self.calls,
            "LISTING": self.listing,
            "BOOTED": self.booted,
            "DEVELOPER": self.developer,
        }
        environment.update(env)
        result = subprocess.run(
            ["bash", self.script, *args],
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            encoding="utf-8",
            check=False,
        )
        calls = []
        if os.path.exists(self.calls):
            with open(self.calls, encoding="utf-8") as f:
                calls = [line.split("\t") for line in f.read().splitlines()]
        return result, calls

    def assert_runs_on(self, result, calls, udid, name, platform):
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout.splitlines()[-1], "Running on " + name + "!")
        build = next(call for call in calls if call[0] == "xcodebuild")
        destination = build[build.index("-destination") + 1]
        self.assertEqual(destination, "platform=" + platform + ",id=" + udid)
        steps = [call[2:] for call in calls if call[:2] == ["xcrun", "simctl"] and call[2] != "list"]
        self.assertEqual([step[0] for step in steps], ["boot", "location", "install", "launch"])
        for step in steps:
            self.assertEqual(step[1], udid, step)
        self.assertFalse([call for call in calls if name in call[1:]], "a step names the device")

    def test_phone_addresses_the_picked_iphone_by_udid(self):
        result, calls = self.run_script("phone")
        self.assert_runs_on(result, calls, "UDID-PRO-MAX", "iPhone 18 Pro Max", "iOS Simulator")

    def test_no_argument_is_the_phone(self):
        result, calls = self.run_script()
        self.assert_runs_on(result, calls, "UDID-PRO-MAX", "iPhone 18 Pro Max", "iOS Simulator")

    def test_duo_addresses_the_duo_by_udid(self):
        result, calls = self.run_script("duo")
        self.assert_runs_on(result, calls, "UDID-DUO", "iPhone Duo", "iOS Simulator")

    def test_watch_addresses_the_picked_watch_by_udid(self):
        result, calls = self.run_script("watch")
        self.assert_runs_on(result, calls, "UDID-WATCH", "Apple Watch Series 12 (46mm)", "watchOS Simulator")
        build = next(call for call in calls if call[0] == "xcodebuild")
        self.assertEqual(build[build.index("-scheme") + 1], "TrainTimeWatch")

    def test_a_given_udid_is_the_device(self):
        result, calls = self.run_script("watch", SIM_UDID="UDID-WATCH-ULTRA")
        name = "Apple Watch Ultra 4 (49mm)"
        self.assert_runs_on(result, calls, "UDID-WATCH-ULTRA", name, "watchOS Simulator")

    def test_a_booted_simulator_is_not_booted_again(self):
        self.boot("UDID-DUO", "UDID-PRO-MAX")
        result, calls = self.run_script("phone")
        self.assertEqual(result.returncode, 0, result.stdout)
        steps = [call[2:] for call in calls if call[:2] == ["xcrun", "simctl"] and call[2] != "list"]
        self.assertEqual([step[0] for step in steps], ["location", "install", "launch"])

    def test_a_udid_that_is_not_installed_stops_before_the_build(self):
        result, calls = self.run_script("phone", SIM_UDID="UDID-NOWHERE")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("UDID-NOWHERE", result.stdout)
        self.assertFalse([call for call in calls if call[0] == "xcodebuild"])

    def test_the_selected_xcode_s_device_hub_is_opened_when_it_ships_one(self):
        os.makedirs(self.device_hub)
        result, calls = self.run_script("phone")
        self.assertEqual(result.returncode, 0, result.stdout)
        opened = [call[1:] for call in calls if call[0] == "open"]
        self.assertEqual(len(opened), 1)
        self.assertTrue(os.path.samefile(opened[0][-1], self.device_hub))

    def test_nothing_is_opened_when_the_selected_xcode_ships_no_device_hub(self):
        result, calls = self.run_script("phone")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse([call for call in calls if call[0] == "open"])

    def test_help_names_no_model(self):
        result, calls = self.run_script("--help")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(calls)
        for word in ("Pro Max", "Ultra", "Series"):
            self.assertNotIn(word, result.stdout)
        for word in ("phone", "duo", "watch", "SIM_UDID"):
            self.assertIn(word, result.stdout)


if __name__ == "__main__":
    unittest.main()
