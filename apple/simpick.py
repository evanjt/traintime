"""Pick the simulator sim.sh runs on.

Reads `xcrun simctl list devices available -j` on stdin and prints the udid and the name of the
picked device, separated by a tab:

    xcrun simctl list devices available -j | python3 simpick.py phone|duo|watch

`SIM_UDID` names the device outright. Otherwise the device is picked by its type on the newest
installed runtime that carries one, never by a model name, so a runtime update that replaces the
models leaves the pick working.
"""

import json
import os
import re
import sys

DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType."


def is_duo(kind):
    return re.match(r"iPhone-Duo(-|$)", kind) is not None


def is_standard_iphone(kind):
    return kind.startswith("iPhone-") and not is_duo(kind)


def is_ipad(kind):
    return kind.startswith("iPad-")


def is_watch(kind):
    return kind.startswith("Apple-Watch-")


def newest_generation_largest_model(kind):
    generation = re.match(r"iPhone-(\d+)", kind)
    return (int(generation.group(1)) if generation else 0, kind.endswith("-Pro-Max"))


def first_listed(_kind):
    return 0


# Per target: the runtime platform, then the device classes in the order they are tried, each
# with the rank that chooses among the devices of that class on one runtime.
TARGETS = {
    "phone": ("iOS", [
        (is_standard_iphone, newest_generation_largest_model),
        (is_duo, first_listed),
        (is_ipad, first_listed),
    ]),
    "duo": ("iOS", [(is_duo, first_listed)]),
    "watch": ("watchOS", [(is_watch, first_listed)]),
}


def runtime_version(runtime):
    """("iOS", (27, 1)) for com.apple.CoreSimulator.SimRuntime.iOS-27-1."""
    platform, *numbers = runtime.rsplit(".", 1)[-1].split("-")
    return platform, tuple(int(number) for number in numbers if number.isdigit())


def kind_of(device):
    return device.get("deviceTypeIdentifier", "").replace(DEVICE_TYPE, "", 1)


def available(listing):
    """(runtime, devices) pairs with the unavailable devices left out."""
    for runtime, devices in listing.get("devices", {}).items():
        yield runtime, [device for device in devices if device.get("isAvailable", True)]


def pick(listing, target, udid=None):
    """The (udid, name) of the simulator for `target`; LookupError when there is none."""
    if udid:
        for _runtime, devices in available(listing):
            for device in devices:
                if device["udid"] == udid:
                    return device["udid"], device["name"]
        raise LookupError("SIM_UDID " + udid + " is not an available simulator")

    if target not in TARGETS:
        raise LookupError("unknown target " + target)
    platform, classes = TARGETS[target]
    runtimes = sorted(
        (
            (runtime_version(runtime)[1], devices)
            for runtime, devices in available(listing)
            if runtime_version(runtime)[0] == platform
        ),
        key=lambda pair: pair[0],
        reverse=True,
    )
    for in_class, rank in classes:
        for _version, devices in runtimes:
            candidates = [device for device in devices if in_class(kind_of(device))]
            if candidates:
                # max keeps the first listed among equals
                device = max(candidates, key=lambda device: rank(kind_of(device)))
                return device["udid"], device["name"]
    raise LookupError("no available " + platform + " simulator for the " + target + " target")


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: simpick.py phone|duo|watch < devices.json")
    try:
        udid, name = pick(json.load(sys.stdin), sys.argv[1], os.environ.get("SIM_UDID"))
    except LookupError as error:
        sys.exit(str(error.args[0]))
    print(udid + "\t" + name)


if __name__ == "__main__":
    main()
