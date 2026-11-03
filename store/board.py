#!/usr/bin/env python3
"""Departure-board store screenshots: captioned device composites per palette.

Renders an HTML template per shot with headless Chromium at exact store sizes:
Play phone (1080x2160), App Store 6.9" (1320x2868), App Store iPhone Duo
(2007x2853), the App Store header (3840x1646) and search results (3840x2560)
stills and videos, the Play feature graphic (1024x500) and the Connect IQ hero
(1440x720), tiles and cover (500x500).

Layout of store/:
  captures/  raw screen captures per device, as taken
  frames/    device frame templates
  framed/    captures in their device frames (frame.py, frame_wear())
  manual/    assets uploaded by hand: App Store header and search, Garmin
             listing text, hero, tiles and cover
  out/       renders before install (gitignored)
Store renders are mirrored into the fastlane upload trees by install(); the
Duo set renders from the inner-display captures in captures/iphone-duo and
ships only from DUO_FROM on.

Usage: board.py [--palette board|swiss|signal] [--install] [--video] [locale ...]
--install mirrors the existing renders without re-rendering; --video also
renders the App Store header and search videos (minutes per locale). Set
TT_STORE_DIR to redirect the renders (palette comparisons); such runs never
touch fastlane, manual/ or the website, though frame_wear() still refreshes
framed/wear-os from the same captures.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile

import frame

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(SCRIPT_DIR, "..")
FONTS = os.path.join(SCRIPT_DIR, "fonts")
CAPTURES = os.path.join(SCRIPT_DIR, "captures")
FRAMED = os.path.join(SCRIPT_DIR, "framed")
# Renders land in out/ (gitignored) and install() mirrors them into the fastlane
# trees; what is uploaded by hand lands in manual/, which is committed.
STORE = os.environ.get("TT_STORE_DIR", os.path.join(SCRIPT_DIR, "out"))
MANUAL = os.path.join(STORE, "manual") if "TT_STORE_DIR" in os.environ else os.path.join(SCRIPT_DIR, "manual")
SITE = os.path.join(REPO, "docs", "img")

CHROMIUM = os.environ.get("CHROMIUM", "chromium")

# Palettes. "board" is the departure-board dark set; "swiss" is the
# poster-tradition light set built around the red brand mark; "signal" keeps
# the dark ground but swaps the accent to brand red.
PALETTES = {
    "board": dict(
        bg="#14161a", edge="#0b0c0e",
        cap="#f0b429", sub="#a6abb3", ink="#f4f5f6",
        rule_base="#99880055", seg="#f0b429",
        dev_shadow="0 0 var(--glow) rgba(240, 180, 66, 0.13), "
                   "0 26px 90px rgba(0, 0, 0, 0.55)",
    ),
    "swiss": dict(
        bg="#f5f4f0", edge="#e6e4de",
        cap="#191b1f", sub="#5c6068", ink="#191b1f",
        rule_base="#eb000030", seg="#eb0000",
        dev_shadow="0 22px 70px rgba(20, 22, 26, 0.28)",
    ),
    "signal": dict(
        bg="#14161a", edge="#0b0c0e",
        cap="#f4f5f6", sub="#a6abb3", ink="#f4f5f6",
        rule_base="#eb000040", seg="#eb0000",
        dev_shadow="0 0 var(--glow) rgba(235, 0, 0, 0.14), "
                   "0 26px 90px rgba(0, 0, 0, 0.55)",
    ),
}


def drop_shadow(box_shadow):
    """A box-shadow list as drop-shadow filters, which follow the device art's
    alpha instead of its rectangle."""
    return " ".join(f"drop-shadow({part.strip()})"
                    for part in re.split(r",\s*(?![^()]*\))", box_shadow))


_framed = {}


def framed(device, capture):
    """The capture in its manufacturer's device art, as a PNG under out/framed,
    with the art's size and the screen's rect inside it."""
    # Captures from a 1440-wide phone go in the 1440-wide Pixel art.
    if device == "android" and frame.Image.open(capture).width == 1440:
        device = "android-qhd"
    key = (device, capture)
    if key not in _framed:
        image = frame.frame_device(device, capture)
        stem = os.path.splitext(os.path.basename(capture))[0]
        path = os.path.join(STORE, "framed", f"{device}-{stem}.png")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        image.save(path)
        _framed[key] = (path, image.size, frame.screen_rect(device))
    return _framed[key]


def make_css(p):
    return f"""
  @font-face {{
    font-family: 'Board';
    src: url('file://{FONTS}/BarlowSemiCondensed-Bold.ttf');
    font-weight: 700;
  }}
  @font-face {{
    font-family: 'Board';
    src: url('file://{FONTS}/BarlowSemiCondensed-SemiBold.ttf');
    font-weight: 600;
  }}
  @font-face {{
    font-family: 'BoardText';
    src: url('file://{FONTS}/Barlow-Regular.ttf');
    font-weight: 400;
  }}
  @font-face {{
    font-family: 'BoardText';
    src: url('file://{FONTS}/Barlow-Medium.ttf');
    font-weight: 500;
  }}
  * {{ margin: 0; padding: 0; box-sizing: border-box; }}
  html, body {{ width: 100%; height: 100%; overflow: hidden; }}
  body {{
    background: radial-gradient(140% 100% at 50% 0%, {p['bg']} 55%, {p['edge']} 100%);
    font-family: 'BoardText', sans-serif;
  }}
  .canvas {{
    width: 100%; height: 100%;
    display: flex; flex-direction: column;
    padding: var(--pad);
  }}
  .caption {{
    font-family: 'Board', sans-serif;
    font-weight: 700;
    font-size: var(--cap);
    line-height: 1.04;
    letter-spacing: 0.045em;
    text-transform: uppercase;
    color: {p['cap']};
    white-space: pre-line;
  }}
  .sub {{
    margin-top: calc(var(--cap) * 0.34);
    font-size: var(--sub);
    line-height: 1.2;
    font-weight: 400;
    color: {p['sub']};
    letter-spacing: 0.01em;
  }}
  /* Fixed so the rule lands at the same height on every shot. Without it the
     rule rides on the text: a subcaption that wraps to two lines (French and
     German need it) pushes it down and the set looks misaligned side by side.
     Sized for the worst case, two caption lines over two subcaption lines. */
  .head {{ height: var(--headh); }}
  /* The favourites separator from the app, as the board's dividing line. The
     bright segment is the position indicator: it travels left to right across
     the set, and its width is one shot's share of the bar (see seg_positions). */
  .rule {{
    margin-top: calc(var(--cap) * 0.52);
    height: var(--rule);
    background: {p['rule_base']};
    position: relative;
  }}
  .rule::before {{
    content: '';
    position: absolute; left: var(--seg, 0%); top: 0; bottom: 0;
    width: var(--segw, 27%);
    background: {p['seg']};
  }}
  .stage {{
    flex: 1;
    position: relative;
    margin-top: calc(var(--cap) * 0.62);
  }}
  .device {{
    position: absolute;
    left: 50%;
    transform: translateX(-50%);
    top: 0;
    width: var(--devw);
    filter: {drop_shadow(p['dev_shadow'])};
  }}
"""


PHONE_HTML = """<!doctype html>
<html><head><meta charset="utf-8"><style>
{css}
:root {{
  --pad: {pad}px; --cap: {cap}px; --sub: {sub}px; --rule: {rule}px; --seg: {seg}; --segw: {segw}; --headh: {headh}px;
  --devw: {devw}px; --glow: {glow}px;
}}
</style></head>
<body>
  <div class="canvas">
    <div class="head">
      <div class="caption">{caption}</div>
      <div class="sub">{sub_text}</div>
    </div>
    <div class="rule"></div>
    <div class="stage">
      <img class="device" src="file://{device}">
    </div>
  </div>
</body></html>
"""

WATCHES_HTML = """<!doctype html>
<html><head><meta charset="utf-8"><style>
{css}
:root {{
  --pad: {pad}px; --cap: {cap}px; --sub: {sub}px; --rule: {rule}px; --seg: {seg}; --segw: {segw}; --headh: {headh}px;
  --glow: {glow}px;
}}
.trio {{
  flex: 1;
  display: flex; flex-direction: column;
  justify-content: space-evenly;
  align-items: center;
}}
.watch {{ display: flex; flex-direction: column; align-items: center; gap: {gap}px; }}
.watch img {{ filter: drop-shadow(0 {shadow}px {blur}px rgba(0, 0, 0, 0.5)); }}
.framed img {{ height: {framedh}px; }}
.label {{
  font-family: 'Board', sans-serif;
  font-weight: 600;
  font-size: {label}px;
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: {grey};
}}
</style></head>
<body>
  <div class="canvas">
    <div class="head">
      <div class="caption">{caption}</div>
      <div class="sub">{sub_text}</div>
    </div>
    <div class="rule"></div>
    <div class="trio">
      {items}
    </div>
  </div>
</body></html>
"""

FEATURE_HTML = """<!doctype html>
<html><head><meta charset="utf-8"><style>
{css}
:root {{ --pad: 0px; --cap: 86px; --sub: 30px; --rule: 5px; --glow: 70px; }}
.canvas {{ flex-direction: row; align-items: center; padding: 0 64px; gap: 56px; }}
.left {{ flex: 1; }}
.wordmark {{
  font-family: 'Board', sans-serif;
  font-weight: 700;
  font-size: 86px;
  letter-spacing: 0.03em;
  color: {ink};
}}
.wordmark span {{ color: {seg}; }}
.left .rule {{ margin: 26px 0 22px; }}
.tagline {{ font-size: 31px; color: {grey}; }}
.right {{ height: 100%; position: relative; width: 360px; flex: none; }}
.right img {{ position: absolute; }}
.phone {{
  width: {devw}px; left: 0; top: 56px;
  filter: {dev_shadow};
}}
.wearfg {{
  width: 190px; right: -14px; bottom: 8px;
  filter: drop-shadow(0 14px 36px rgba(0, 0, 0, 0.35));
}}
</style></head>
<body>
  <div class="canvas">
    <div class="left">
      <div class="wordmark">Train<span>Time</span></div>
      <div class="rule"></div>
      <div class="tagline">{tagline}</div>
    </div>
    <div class="right">
      <img class="phone" src="file://{screen}">
      <img class="wearfg" src="file://{wear}">
    </div>
  </div>
</body></html>
"""


GARMIN_HERO_HTML = """<!doctype html>
<html><head><meta charset="utf-8"><style>
{css}
:root {{ --pad: 0px; --cap: 110px; --sub: 40px; --rule: 6px; --glow: 90px; }}
.canvas {{ flex-direction: row; align-items: center; padding: 0 96px; gap: 72px; }}
.left {{ flex: 1; }}
.wordmark {{
  font-family: 'Board', sans-serif;
  font-weight: 700;
  font-size: 110px;
  letter-spacing: 0.03em;
  color: {ink};
}}
.wordmark span {{ color: {seg}; }}
.left .rule {{ margin: 34px 0 28px; }}
.tagline {{ font-size: 42px; color: {grey}; }}
.right {{ height: 100%; position: relative; width: 460px; flex: none; }}
.right img {{
  position: absolute; height: 660px; left: 50%; top: 50%;
  transform: translate(-50%, -50%);
  filter: drop-shadow(0 22px 50px rgba(20, 22, 26, 0.35));
}}
</style></head>
<body>
  <div class="canvas">
    <div class="left">
      <div class="wordmark">Train<span>Time</span></div>
      <div class="rule"></div>
      <div class="tagline">{tagline}</div>
    </div>
    <div class="right">
      <img src="file://{watch}">
    </div>
  </div>
</body></html>
"""


def render(html, width, height, out_path, transparent=False):
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as f:
        f.write(html)
        page = f.name
    try:
        subprocess.run(
            [
                CHROMIUM, "--headless", "--disable-gpu", "--no-sandbox",
                "--force-device-scale-factor=1", "--hide-scrollbars",
                f"--window-size={width},{height}",
                f"--screenshot={out_path}",
                *(["--default-background-color=00000000"] if transparent else []),
                f"file://{page}",
            ],
            check=True, capture_output=True,
        )
    finally:
        os.unlink(page)
    print(f"  {os.path.relpath(out_path, STORE)}")


# Fresh raw Wear capture staged for the Play wear listing; reused here.
WEAR_TRACKING = os.path.join(CAPTURES, "wear-os", "02.png")
WEAR_FRAMED = os.path.join(FRAMED, "wear-os", "02-focused-tracking-framed.png")


def frame_wear():
    frame.frame_wear_os()


# Shot list: (output stem, screen capture, caption, subcaption). Captions are
# pre-broken with \n so the line break lands where the board wants it.
# Each store shows its own platform's app: Play gets the Android captures, the
# App Store gets the iOS ones.
def shots(locale, strings, out_subdir):
    if out_subdir == "appstore-duo":
        duo = os.path.join(CAPTURES, "iphone-duo")
        track = os.path.join(duo, "02-focused-tracking-inner-raw.png")
        fav = os.path.join(duo, "04-station-favourites-inner-raw.png")
        widget = os.path.join(duo, "04-widget-inner-raw.png")
    elif out_subdir == "play":
        track = os.path.join(CAPTURES, "android", "01-tracking.png")
        fav = os.path.join(CAPTURES, "android", "02-station-fav.png")
        widget = os.path.join(CAPTURES, "android", "03-widget.png")
    else:
        track = os.path.join(CAPTURES, "iphone", "02-focused-tracking-raw.png")
        fav = os.path.join(CAPTURES, "iphone", "04-station-favourites-raw.png")
        widget = os.path.join(CAPTURES, "iphone", "04-widget-raw.png")
    return [
        ("01", track, strings["track_cap"], strings["track_sub"]),
        ("02", fav, strings["fav_cap"], strings["fav_sub"]),
        ("03", widget, strings["widget_cap"], strings["widget_sub"]),
    ]


def shot_device(out_subdir):
    """The device art a set's phone shots sit in."""
    return {"play": "android", "appstore-duo": "iphone-duo-inner"}.get(out_subdir, "iphone")


def duo_missing():
    """Inner-display captures the Duo set still lacks."""
    return [capture for _, capture, _, _ in shots("en-AU", STRINGS["en-AU"], "appstore-duo")
            if not os.path.exists(capture)]


# Phone shots plus the closing watch frame.
SHOT_COUNT = 4


def head_height(cap, sub):
    """Height of the caption block, matching the CSS in make_css.

    Two caption lines at line-height 1.04, the subcaption's 0.34em top margin,
    then two subcaption lines at 1.2. Two of each is the worst case any locale
    needs, so reserving it keeps the rule at one height across the whole set."""
    return round(2 * cap * 1.04 + cap * 0.34 + 2 * sub * 1.2)


def seg_positions(count):
    """Left offsets and width for the rule's position indicator, as CSS percents.

    The segment is one shot's share of the bar, minus the same visual breathing
    room the three-shot set was drawn with (27% rather than a full third), and
    the last one ends flush with the right edge."""
    width = 81.0 / count
    step = (100.0 - width) / (count - 1)
    return [f"{i * step:.4g}%" for i in range(count)], f"{width:.4g}%"


# Wording follows apple/fastlane/metadata/: DE is informal du with Swiss ss,
# FR is vous, IT is tu. Play's Italian locale is it-IT; Apple's folder is it.
STRINGS = {
    "en-AU": {
        "track_cap": "Know exactly\nwhen to leave",
        "track_sub": "Live countdown, platform and walking time.",
        "fav_cap": "Favourites first,\nat every station",
        "fav_sub": "Star a connection to pin it to the top of that station's board.",
        "widget_cap": "Departures on your\nhome screen",
        "widget_sub": "A live board without opening the app.",
        "watch_cap": "On every\nwrist",
        "watch_sub_play": "Wear OS and Garmin, phone optional.",
        "watch_sub_appstore": "Apple Watch and Garmin, iPhone optional.",
        "garmin_tag": "Swiss departures, live on your watch.",
        "tagline": "Swiss departures, live on your phone and watch.",
    },
    "de-DE": {
        "track_cap": "Genau wissen,\nwann du losmusst",
        "track_sub": "Live-Countdown, Gleis und Gehdistanz.",
        "fav_cap": "Favoriten zuerst,\nan jeder Station",
        "fav_sub": "Mit einem Stern bleibt eine Verbindung an ihrer Haltestelle ganz oben.",
        "widget_cap": "Abfahrten auf dem\nStartbildschirm",
        "widget_sub": "Ein Live-Board, ohne die App zu öffnen.",
        "watch_cap": "An jedem\nHandgelenk",
        "watch_sub_play": "Wear OS und Garmin, auch ohne Handy.",
        "watch_sub_appstore": "Apple Watch und Garmin, auch ohne iPhone.",
        "garmin_tag": "Schweizer Abfahrten, live auf deiner Uhr.",
        "tagline": "Schweizer Abfahrten, live auf Handy und Uhr.",
    },
    "fr-FR": {
        "track_cap": "Savoir exactement\nquand partir",
        "track_sub": "Compte à rebours en direct, quai et distance à pied.",
        "fav_cap": "Vos favoris d'abord,\nà chaque arrêt",
        "fav_sub": "Ajoutez une étoile à une liaison pour l'épingler en haut du tableau de cet arrêt.",
        "widget_cap": "Vos départs sur\nl'écran d'accueil",
        "widget_sub": "Un tableau en direct sans ouvrir l'app.",
        "watch_cap": "À chaque\npoignet",
        "watch_sub_play": "Wear OS et Garmin, téléphone facultatif.",
        "watch_sub_appstore": "Apple Watch et Garmin, iPhone facultatif.",
        "garmin_tag": "Départs suisses, en direct sur votre montre.",
        "tagline": "Départs suisses, en direct sur votre téléphone et votre montre.",
    },
    "it-IT": {
        "track_cap": "Sai esattamente\nquando uscire",
        "track_sub": "Conto alla rovescia live, binario e distanza a piedi.",
        "fav_cap": "Preferiti in cima,\na ogni fermata",
        "fav_sub": "Aggiungi una stella a un collegamento per fissarlo in cima al tabellone di quella fermata.",
        "widget_cap": "Partenze sulla tua\nschermata Home",
        "widget_sub": "Un tabellone live senza aprire l'app.",
        "watch_cap": "Su ogni\npolso",
        "watch_sub_play": "Wear OS e Garmin, telefono facoltativo.",
        "watch_sub_appstore": "Apple Watch e Garmin, iPhone facoltativo.",
        "garmin_tag": "Partenze svizzere, live sul tuo orologio.",
        "tagline": "Partenze svizzere, live su telefono e orologio.",
    },
}


def build_locale(locale, strings, target, out_subdir, palette):
    p = PALETTES[palette]
    css = make_css(p)
    width, height = target
    # Type and device scale from the 6.9" proportions, so a wider canvas (the
    # Duo inner display) keeps the same board and gains side margin instead of
    # a phone too tall for the frame.
    base = width if width <= height * 0.55 else int(height * 0.46)
    pad = int(base * 0.078)
    cap = int(base * 0.082)
    # One rule position per shot: the bright segment travels with the swipe.
    segs, segw = seg_positions(SHOT_COUNT)
    sub = int(cap * 0.42)
    headh = head_height(cap, sub)
    sizes = dict(
        css=css, pad=pad, cap=cap, sub=sub, rule=max(4, base // 270),
        glow=int(base * 0.16), segw=segw, headh=headh,
    )
    device = shot_device(out_subdir)
    for i, (stem, screen, caption, sub_text) in enumerate(shots(locale, strings, out_subdir)):
        path, (aw, _), (_, _, sw, _) = framed(device, screen)
        # The screen keeps the width it had in the drawn bezel; the art's own
        # body adds the rest.
        html = PHONE_HTML.format(
            device=path, caption=caption, sub_text=sub_text, seg=segs[i],
            devw=int(base * 0.79 * aw / sw), **sizes,
        )
        render(html, width, height, os.path.join(STORE, out_subdir, locale, f"{stem}.png"))

    # Watch pairings differ per store: the iOS app links Apple Watch + Garmin,
    # the Android app links Wear OS + Garmin. Never show a watch the store's
    # phone platform cannot pair with.
    garmin = os.path.join(FRAMED, "garmin", "03-focused-tracking-framed.png")
    if out_subdir.startswith("appstore"):
        watches = [
            (os.path.join(FRAMED, "apple-watch", "02-focused-tracking.png"), "Apple Watch"),
            (garmin, "Garmin"),
        ]
        watch_sub = strings["watch_sub_appstore"]
    else:
        watches = [
            (WEAR_FRAMED, "Wear OS"),
            (garmin, "Garmin"),
        ]
        watch_sub = strings["watch_sub_play"]

    items = "\n      ".join(
        f'<div class="watch framed"><img src="file://{src}">'
        f'<div class="label">{label}</div></div>'
        for src, label in watches
    )
    html = WATCHES_HTML.format(
        css=css, pad=pad, cap=cap, sub=sub, rule=max(4, base // 270),
        seg=segs[-1], segw=segw, headh=headh, grey=p["sub"], glow=int(base * 0.16),
        gap=int(base * 0.022), shadow=int(base * 0.016), blur=int(base * 0.055),
        framedh=int(min(width * 0.46, height * 0.3)), label=int(base * 0.026),
        caption=strings["watch_cap"], sub_text=watch_sub, items=items,
    )
    render(html, width, height, os.path.join(STORE, out_subdir, locale, f"{SHOT_COUNT:02d}.png"))


GARMIN_TILE_HTML = """<!doctype html>
<html><head><meta charset="utf-8"><style>
{css}
:root {{ --pad: 0px; --cap: 10px; --sub: 10px; --rule: 4px; --glow: 40px; }}
.canvas {{ align-items: center; justify-content: center; }}
.canvas img {{
  height: 440px;
  filter: drop-shadow(0 10px 26px rgba(20, 22, 26, 0.3));
}}
</style></head>
<body>
  <div class="canvas">
    <img src="file://{watch}">
  </div>
</body></html>
"""


def build_garmin_tiles(palette):
    """Language-neutral 500x500 store screenshots: framed watch on the paper
    ground. The Connect IQ dashboard caps uploads at 500x500 and 150 KB."""
    p = PALETTES[palette]
    for i, name in enumerate(
        ["01-station-view", "02-train-selection", "03-focused-tracking"], 1
    ):
        html = GARMIN_TILE_HTML.format(
            css=make_css(p),
            watch=os.path.join(FRAMED, "garmin", f"{name}-framed.png"),
        )
        png = os.path.join(MANUAL, "garmin", "tiles", f"{i:02d}.png")
        render(html, 500, 500, png)
        # PNG lands just over the dashboard's 150 KB cap; JPEG stays well under.
        subprocess.run(
            ["magick", png, "-quality", "92", png.replace(".png", ".jpg")], check=True,
        )
        os.unlink(png)


GARMIN_COVER_HTML = """<!doctype html>
<html><head><meta charset="utf-8"><style>
{css}
:root {{ --pad: 0px; --cap: 10px; --sub: 10px; --rule: 4px; --glow: 40px; }}
.canvas {{ align-items: center; justify-content: center; gap: 14px; padding-top: 22px; }}
.wordmark {{
  font-family: 'Board', sans-serif;
  font-weight: 700;
  font-size: 58px;
  letter-spacing: 0.03em;
  line-height: 1;
  color: {ink};
}}
.wordmark span {{ color: {seg}; }}
.canvas .rule {{ width: 150px; margin: 0; }}
.canvas img {{
  height: 350px;
  filter: drop-shadow(0 10px 26px rgba(20, 22, 26, 0.3));
}}
</style></head>
<body>
  <div class="canvas">
    <div class="wordmark">Train<span>Time</span></div>
    <div class="rule"></div>
    <img src="file://{watch}">
  </div>
</body></html>
"""


def build_garmin_cover(palette):
    """Language-neutral 500x500 cover image (the dashboard's web and mobile
    listing card): wordmark over the tracking screen, same caps as the tiles."""
    p = PALETTES[palette]
    html = GARMIN_COVER_HTML.format(
        css=make_css(p), ink=p["ink"], seg=p["seg"],
        watch=os.path.join(FRAMED, "garmin", "03-focused-tracking-framed.png"),
    )
    png = os.path.join(MANUAL, "garmin", "cover.png")
    render(html, 500, 500, png)
    subprocess.run(["magick", png, "-quality", "92", png.replace(".png", ".jpg")], check=True)
    os.unlink(png)


def build_garmin_hero(locale, strings, palette):
    p = PALETTES[palette]
    html = GARMIN_HERO_HTML.format(
        css=make_css(p), ink=p["ink"], seg=p["seg"], grey=p["sub"],
        tagline=strings["garmin_tag"],
        watch=os.path.join(FRAMED, "garmin", "03-focused-tracking-framed.png"),
    )
    render(html, 1440, 720, os.path.join(MANUAL, "garmin", locale, "hero.png"))


def build_feature_graphic(locale, strings, palette):
    p = PALETTES[palette]
    phone, (aw, _), (_, _, sw, _) = framed("android", os.path.join(CAPTURES, "android", "01-tracking.png"))
    html = FEATURE_HTML.format(
        css=make_css(p), ink=p["ink"], seg=p["seg"], grey=p["sub"],
        dev_shadow=drop_shadow(p["dev_shadow"]),
        tagline=strings["tagline"],
        screen=phone, devw=int(214 * aw / sw),
        wear=os.path.join(FRAMED, "garmin", "03-focused-tracking-framed.png"),
    )
    render(html, 1024, 500, os.path.join(STORE, "feature", locale, "featureGraphic.png"))


CREATIVE_HTML = """<!doctype html>
<html><head><meta charset="utf-8"><style>
{css}
:root {{ --pad: 0px; --cap: 10px; --sub: 10px; --rule: {rule}px; --glow: {glow}px; }}
.left {{
  position: absolute; left: {lx}px; width: {lw}px; top: {cy}px;
  transform: translateY(-50%);
}}
.wordmark {{
  font-family: 'Board', sans-serif;
  font-weight: 700;
  font-size: {word}px;
  line-height: 1;
  letter-spacing: 0.03em;
  color: {ink};
}}
.wordmark span {{ color: {seg}; }}
.left .rule {{ margin: {rulegap}px 0; width: 100%; }}
/* The rule runs on to both edges, so a wide crop of the bleed still reads
   as one line through the art instead of empty margins. */
.left .rule::after {{
  content: ''; position: absolute; top: 0; bottom: 0;
  left: -{width}px; right: -{width}px;
  background: {rule_base}; z-index: -1;
}}
.tagline {{ font-size: {tag}px; line-height: 1.22; color: {grey}; }}
.phone {{
  position: absolute; left: {dx}px; top: {dy}px; width: {dw}px;
  filter: {dev_shadow};
}}
.watch {{
  position: absolute; left: {wx}px; top: {wy}px; height: {wh}px;
  filter: drop-shadow(0 {wshadow}px {wblur}px rgba(20, 22, 26, 0.35));
}}
/* Video layers: each part renders alone, on a transparent page or on the bare
   background, and the compositor animates the rule itself. */
body.bg .left, body.bg .phone, body.bg .watch {{ visibility: hidden; }}
body.layer {{ background: none; }}
body.layer .left, body.layer .phone, body.layer .watch {{ visibility: hidden; }}
body.layer .rule {{ background: none; }}
body.layer .rule::before, body.layer .rule::after {{ display: none; }}
body.only-text .left, body.only-phone .phone, body.only-watch .watch {{ visibility: visible; }}
body.probe .rule {{ visibility: visible; background: #000; }}
</style></head>
<body class="{layer}">
  <div class="left">
    <div class="wordmark">Train<span>Time</span></div>
    <div class="rule"></div>
    <div class="tagline">{tagline}</div>
  </div>
  <img class="phone" src="file://{phone}">
  {watch_img}
</body></html>
"""

# App Store creative assets (iOS 27+): canvas size, the art safe area from
# Apple's Photoshop templates as (x, y, w, h), and the video size. Each device
# crops the bleed outside the safe area differently, so the wordmark, tagline
# and countdown sit inside it. The iPhone search card shows the whole 3:2
# frame, so the search phone runs off the bottom edge instead of showing its
# empty lower screen. 3840x2560 is past H.264 level 5.1, so the search video
# is the same frame at 2880x1920, inside Apple's 1920x1280 to 3840x2560 range.
CREATIVE = {
    "header": dict(size=(3840, 1646), safe=(1097, 493, 1646, 661), video=(3840, 1646)),
    "search": dict(size=(3840, 2560), safe=(836, 765, 2168, 1030), video=(2880, 1920)),
}

# The tracking capture's content ends 61% of the way down its screen; the rest
# is empty.
TRACKING_CONTENT = 0.61

CREATIVE_SCREENS = {
    "tracking": (os.path.join(CAPTURES, "iphone", "02-focused-tracking-raw.png"),
                 os.path.join(FRAMED, "apple-watch", "02-focused-tracking.png")),
    "board": (os.path.join(CAPTURES, "iphone", "01-station-view-raw.png"),
              os.path.join(FRAMED, "apple-watch", "01-station-view.png")),
}


def creative_layout(name):
    spec = CREATIVE[name]
    width, height = spec["size"]
    sx, sy, sw, sh = spec["safe"]
    cy = sy + sh // 2
    inset = int(sw * 0.04)
    lay = dict(width=width, height=height, cy=cy, lx=sx + inset, sh=sh)
    if name == "header":
        # Phone content spans the safe area's height, so its empty lower screen
        # falls in the bleed below; the watch sits hard against the right edge,
        # overlapping the phone a little.
        ph = int(sh / TRACKING_CONTENT)
        pw = int(ph * 1320 / 2868)
        bezel = max(6, pw // 45)
        wh = int(sh * 0.8)
        ww = int(wh * 560 / 880)
        wx = sx + sw - inset - ww
        px = wx + int(ww * 0.14) - pw - 2 * bezel
        py = cy - int(ph * TRACKING_CONTENT / 2) - bezel
        lay.update(watch=(wx, cy - wh // 2, wh))
        cap = 0.2
    else:
        # One phone, cut by the bottom edge just below its buttons, its
        # countdown inside the safe area and its right edge a little past it.
        px = sx + int(sw * 0.57)
        pw = sx + sw + int(sw * 0.14) - px
        ph = int(pw * 2868 / 1320)
        bezel = max(6, pw // 45)
        py = height - int(ph * (TRACKING_CONTENT + 0.05))
        lay.update(watch=None)
        cap = 0.24
    lw = px - int(sw * 0.05) - lay["lx"]
    # The wordmark's advance is 4.3 em in the bundled face.
    word = min(int(sh * cap), int(lw / 4.3))
    lay.update(px=px, py=py, ph=ph, pw=pw, bezel=bezel, lw=lw, word=word)
    return lay


def creative_html(p, strings, lay, layer="", capture="tracking"):
    phone, watch = CREATIVE_SCREENS[capture]
    sh = lay["sh"]
    # The layout places the screen; the device art is scaled and shifted so
    # its screen hole lands there.
    phone, (aw, _), (hx, hy, hw, _) = framed("iphone", phone)
    scale = lay["pw"] / hw
    dx = lay["px"] + lay["bezel"] - int(hx * scale)
    dy = lay["py"] + lay["bezel"] - int(hy * scale)
    watch_img = ""
    if lay["watch"]:
        watch_img = f'<img class="watch" src="file://{watch}">'
    wx, wy, wh = lay["watch"] or (0, 0, 0)
    return CREATIVE_HTML.format(
        css=make_css(p), ink=p["ink"], seg=p["seg"], grey=p["sub"],
        rule_base=p["rule_base"], dev_shadow=drop_shadow(p["dev_shadow"]), layer=layer,
        # No lone last word when the tagline wraps.
        tagline=" ".join(strings["tagline"].rsplit(" ", 1)), width=lay["width"],
        cy=lay["cy"], lx=lay["lx"], lw=lay["lw"], word=lay["word"],
        tag=int(lay["word"] * 0.4), rule=max(6, sh // 110),
        rulegap=int(sh * 0.05), glow=int(sh * 0.1),
        dx=dx, dy=dy, dw=int(aw * scale), wx=wx, wy=wy, wh=wh,
        wshadow=int(sh * 0.02), wblur=int(sh * 0.05),
        phone=phone, watch_img=watch_img,
    )


def build_creative(locale, strings, palette):
    p = PALETTES[palette]
    for name in CREATIVE:
        lay = creative_layout(name)
        render(creative_html(p, strings, lay), lay["width"], lay["height"],
               os.path.join(MANUAL, "app-store", locale, f"{name}.png"))


# The creative videos loop in this many seconds: tracking, a crossfade to the
# departure board, the board, and a crossfade back, while a soft light passes
# over the ground and the rule's bright segment runs its length like a train.
VIDEO_SECONDS = 16
VIDEO_FPS = 30


def build_creative_video(locale, strings, palette):
    import numpy as np
    from PIL import Image

    p = PALETTES[palette]
    for name, spec in CREATIVE.items():
        lay = creative_layout(name)
        width, height = lay["width"], lay["height"]
        work = tempfile.mkdtemp()

        def layer(cls, capture="tracking"):
            path = os.path.join(work, f"{cls.replace(' ', '-')}-{capture}.png")
            render(creative_html(p, strings, lay, cls, capture), width, height, path,
                   transparent=cls != "bg")
            return np.asarray(Image.open(path).convert("RGBA" if cls != "bg" else "RGB"))

        ground = layer("bg").astype(np.float32)
        text = layer("layer only-text")
        phones = [layer("layer only-phone", c) for c in CREATIVE_SCREENS]
        watches = [layer("layer only-watch", c) for c in CREATIVE_SCREENS] if lay["watch"] else []
        x0, y0, x1, y1 = Image.fromarray(layer("layer probe")).getbbox()
        segw = int((x1 - x0) * 0.27)

        def sprite(rgba, box=None):
            box = box or Image.fromarray(rgba).getbbox()
            cut = rgba[box[1]:box[3], box[0]:box[2]].astype(np.float32)
            return box, cut[..., :3], cut[..., 3:] / 255.0

        def over(frame, box, rgb, alpha):
            region = frame[box[1]:box[3], box[0]:box[2]]
            region *= 1 - alpha
            region += rgb * alpha

        text_sprite = sprite(text)
        # The board capture crossfades inside the tracking capture's frame.
        phone_sprites = [sprite(phones[0])]
        phone_sprites.append(sprite(phones[1], phone_sprites[0][0]))
        watch_sprites = [sprite(watches[0])] if watches else []
        if watches:
            watch_sprites.append(sprite(watches[1], watch_sprites[0][0]))

        def colour(hexa):
            v = [int(hexa[i:i + 2], 16) for i in (1, 3, 5, 7 if len(hexa) > 7 else 5)]
            return np.array(v[:3], np.float32), (v[3] / 255.0 if len(hexa) > 7 else 1.0)

        base, base_a = colour(p["rule_base"])
        seg, _ = colour(p["seg"])
        # One soft hump of light per two widths, so the pattern repeats exactly
        # when it has moved two widths in one loop.
        period = 2 * width
        u = np.arange(period + width, dtype=np.float32)
        hump = ((1 + np.cos(2 * np.pi * u / period)) / 2) ** 3
        rows = np.exp(-((np.arange(height) - height * 0.35) / (height * 0.6)) ** 2)
        warm = np.array([7.0, 6.0, 4.0], np.float32)

        frames = VIDEO_SECONDS * VIDEO_FPS
        vw, vh = spec["video"]
        out = os.path.join(MANUAL, "app-store", locale, f"{name}.mp4")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        ffmpeg = subprocess.Popen(
            ["ffmpeg", "-v", "error", "-y",
             "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{width}x{height}",
             "-r", str(VIDEO_FPS), "-i", "-",
             "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
             "-vf", f"scale={vw}:{vh}:flags=lanczos", "-shortest",
             "-c:v", "libx264", "-preset", "slow", "-crf", "16",
             "-profile:v", "high", "-pix_fmt", "yuv420p",
             "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", out],
            stdin=subprocess.PIPE,
        )
        for i in range(frames):
            t = i / frames
            shift = int(period * t)
            light = hump[period - shift:period - shift + width]
            frame = ground + (rows[:, None, None] * light[None, :, None]) * warm
            band = frame[y0:y1]
            band *= 1 - base_a
            band += base * base_a
            sx0 = int(-segw + (width + segw) * t)
            frame[y0:y1, max(0, sx0):max(0, min(width, sx0 + segw))] = seg
            over(frame, *text_sprite)
            # Tracking first, then the board, each crossfade a second long.
            k = min(max((t * VIDEO_SECONDS - 7), 0), 1) - min(max((t * VIDEO_SECONDS - 15), 0), 1)
            k = k * k * (3 - 2 * k)
            for sprites in (phone_sprites, watch_sprites):
                if sprites:
                    (box, a_rgb, a_alpha), (_, b_rgb, _) = sprites
                    over(frame, box, a_rgb * (1 - k) + b_rgb * k, a_alpha)
            ffmpeg.stdin.write(np.clip(frame, 0, 255).astype(np.uint8).tobytes())
        ffmpeg.stdin.close()
        if ffmpeg.wait():
            raise RuntimeError(f"ffmpeg failed for {out}")
        shutil.rmtree(work)
        print(f"  {os.path.relpath(out, STORE)}")


# iPhone Duo, inner display portrait. One display class covers inner and outer,
# so the larger size serves both.
DUO = (2007, 2853)

# The first release whose IPA is built with the iOS 27.1 SDK. Uploading any Duo
# screenshot badges the listing as optimised for the Duo, so the set ships only
# with a build that runs on it. Move this if the SDK switch moves.
DUO_FROM = "0.10.0"

PBXPROJ = os.path.join(REPO, "apple", "TrainTimeWatch.xcodeproj", "project.pbxproj")


def version_tuple(version):
    return tuple(int(part) for part in version.split("."))


def duo_enabled(version):
    return version_tuple(version) >= version_tuple(DUO_FROM)


def marketing_version():
    with open(PBXPROJ) as f:
        return re.search(r"MARKETING_VERSION = ([\d.]+);", f.read()).group(1)


def apple_set(locale, version):
    """(source, file name) for one App Store locale. deliver sorts by file name
    within a device class and detects the class from resolution (1320x2868
    iPhone 6.9", 2007x2853 iPhone Duo, 416x496 Apple Watch)."""
    files = [(os.path.join(STORE, "appstore", locale, f"{i:02d}.png"), f"{i:02d}.png")
             for i in range(1, SHOT_COUNT + 1)]
    files += [(os.path.join(CAPTURES, "apple-watch", f"store-{i:02d}.png"), f"watch-{i:02d}.png")
              for i in (1, 2)]
    if duo_enabled(version):
        files += [(os.path.join(STORE, "appstore-duo", locale, f"{i:02d}.png"), f"duo-{i:02d}.png")
                  for i in range(1, SHOT_COUNT + 1)]
    return files

# App Store Connect uses the bare "it" locale where Play uses "it-IT".
APPLE_LOCALE = {"it-IT": "it"}

# Byte-identical locale mirrors on both stores. en-GB is the English the Swiss
# storefronts index for search; en-AU is what English readers see via fallback.
MIRRORS = {"en-AU": ["en-GB"]}


# The framed shots the website gallery and README show, as (device, file).
SITE_IMAGES = [
    ("apple-watch", "01-station-view.png"),
    ("apple-watch", "02-focused-tracking.png"),
    ("apple-watch", "03-station-picker.png"),
    ("wear-os", "01-station-view-framed.png"),
    ("wear-os", "02-focused-tracking-framed.png"),
    ("garmin", "01-station-view-framed.png"),
    ("garmin", "03-focused-tracking-framed.png"),
    ("garmin", "04-station-picker-framed.png"),
    ("iphone", "01-station-view.png"),
    ("iphone", "02-focused-tracking.png"),
    ("iphone", "03-station-picker.png"),
]


def install(locales):
    """Mirror rendered assets into the fastlane upload trees so a tag release
    ships exactly what was last rendered. Whole per-locale sets are replaced,
    never merged: supply and deliver clobber the store set on upload, so the
    repo is the single source of truth. Garmin has no upload API; its assets
    stay in manual/garmin for the dashboard. The website's gallery gets its
    framed shots copied into docs/img."""
    from PIL import Image

    version = marketing_version()
    if duo_enabled(version) and duo_missing():
        raise SystemExit(f"{version} ships the Duo set but captures are missing: {duo_missing()}")
    play_meta = os.path.join(REPO, "android", "fastlane", "metadata", "android")
    apple_shots = os.path.join(REPO, "apple", "fastlane", "screenshots")
    targets = []
    for locale in locales:
        targets.append(locale)
        targets.extend(MIRRORS.get(locale, []))
    for locale in targets:
        source = next((s for s, ms in MIRRORS.items() if locale in ms), locale)
        images = os.path.join(play_meta, locale, "images")
        phone = os.path.join(images, "phoneScreenshots")
        shutil.rmtree(phone, ignore_errors=True)
        os.makedirs(phone)
        for i in range(1, SHOT_COUNT + 1):
            shutil.copy(os.path.join(STORE, "play", source, f"{i:02d}.png"), phone)
        shutil.copy(
            os.path.join(STORE, "feature", source, "featureGraphic.png"),
            os.path.join(images, "featureGraphic.png"),
        )

        # Wear raws carry alpha from the capture pipeline; Play rejects it.
        wear = os.path.join(images, "wearScreenshots")
        shutil.rmtree(wear, ignore_errors=True)
        os.makedirs(wear)
        for i in (1, 2, 3):
            src = os.path.join(CAPTURES, "wear-os", f"{i:02d}.png")
            Image.open(src).convert("RGB").save(os.path.join(wear, f"{i:02d}.png"))

        adir = os.path.join(apple_shots, APPLE_LOCALE.get(locale, locale))
        shutil.rmtree(adir, ignore_errors=True)
        os.makedirs(adir)
        for src, name in apple_set(source, version):
            shutil.copy(src, os.path.join(adir, name))
        print(f"[{locale}] installed into fastlane trees")
    for device, name in SITE_IMAGES:
        os.makedirs(os.path.join(SITE, device), exist_ok=True)
        shutil.copy(os.path.join(FRAMED, device, name), os.path.join(SITE, device, name))
    print("website gallery copied into docs/img")


if __name__ == "__main__":
    args = sys.argv[1:]
    palette = "swiss"
    if "--palette" in args:
        i = args.index("--palette")
        palette = args[i + 1]
        del args[i:i + 2]
    install_only = "--install" in args
    if install_only:
        args.remove("--install")
    video = "--video" in args
    if video:
        args.remove("--video")
    locales = args or list(STRINGS)
    if install_only:
        install(locales)
        sys.exit(0)
    frame_wear()
    print(f"[{palette}] Garmin tiles 500x500")
    build_garmin_tiles(palette)
    print(f"[{palette}] Garmin cover 500x500")
    build_garmin_cover(palette)
    for locale in locales:
        strings = STRINGS[locale]
        print(f"[{locale}/{palette}] Play phone 1080x2160")
        build_locale(locale, strings, (1080, 2160), "play", palette)
        print(f"[{locale}/{palette}] App Store 1320x2868")
        build_locale(locale, strings, (1320, 2868), "appstore", palette)
        if duo_missing():
            print(f"[{locale}/{palette}] App Store iPhone Duo skipped, no inner-display captures")
        else:
            print(f"[{locale}/{palette}] App Store iPhone Duo {DUO[0]}x{DUO[1]}")
            build_locale(locale, strings, DUO, "appstore-duo", palette)
        print(f"[{locale}/{palette}] App Store header and search results")
        build_creative(locale, strings, palette)
        if video:
            print(f"[{locale}/{palette}] App Store header and search videos")
            build_creative_video(locale, strings, palette)
        print(f"[{locale}/{palette}] Feature graphic 1024x500")
        build_feature_graphic(locale, strings, palette)
        print(f"[{locale}/{palette}] Garmin hero 1440x720")
        build_garmin_hero(locale, strings, palette)
    # Palette-comparison runs (TT_STORE_DIR) never touch the release trees.
    if "TT_STORE_DIR" not in os.environ:
        install(locales)
    print("Done.")
