#!/usr/bin/env python3
"""Departure-board store screenshots: captioned device composites per palette.

Renders an HTML template per shot with headless Chromium at exact store sizes.
Outputs Play phone (1080x2160), App Store 6.9" (1320x2868) and the Play
feature graphic (1024x500). Raw captures come from screenshots/ and
docs/screenshots/; fonts are bundled in docs/screenshots/fonts/.

Usage: board.py [--palette board|swiss|signal] [locale ...]
Set TT_STORE_DIR to redirect output (used for palette comparisons).
"""

import os
import subprocess
import sys
import tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(SCRIPT_DIR, "..", "..")
FONTS = os.path.join(SCRIPT_DIR, "fonts")
STORE = os.environ.get("TT_STORE_DIR", os.path.join(SCRIPT_DIR, "store"))

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
    font-weight: 400;
    color: {p['sub']};
    letter-spacing: 0.01em;
  }}
  /* The favourites separator from the app, as the board's dividing line.
     The bright segment travels across the set: shot 1 left, 2 centre, 3 right. */
  .rule {{
    margin-top: calc(var(--cap) * 0.52);
    height: var(--rule);
    background: {p['rule_base']};
    position: relative;
  }}
  .rule::before {{
    content: '';
    position: absolute; left: var(--seg, 0%); top: 0; bottom: 0;
    width: 27%;
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
    border-radius: var(--devr);
    padding: var(--bezel);
    background: linear-gradient(160deg, #33343a, #1c1d21 40%);
    box-shadow: {p['dev_shadow']};
  }}
  .screen {{
    display: block;
    width: 100%;
    border-radius: calc(var(--devr) - var(--bezel));
  }}
"""


PHONE_HTML = """<!doctype html>
<html><head><meta charset="utf-8"><style>
{css}
:root {{
  --pad: {pad}px; --cap: {cap}px; --sub: {sub}px; --rule: {rule}px; --seg: {seg};
  --devw: {devw}px; --devr: {devr}px; --bezel: {bezel}px; --glow: {glow}px;
}}
</style></head>
<body>
  <div class="canvas">
    <div class="caption">{caption}</div>
    <div class="sub">{sub_text}</div>
    <div class="rule"></div>
    <div class="stage">
      <div class="device">
        <img class="screen" src="file://{screen}">
      </div>
    </div>
  </div>
</body></html>
"""

WATCHES_HTML = """<!doctype html>
<html><head><meta charset="utf-8"><style>
{css}
:root {{
  --pad: {pad}px; --cap: {cap}px; --sub: {sub}px; --rule: {rule}px; --seg: {seg};
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
    <div class="caption">{caption}</div>
    <div class="sub">{sub_text}</div>
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
  width: 230px; left: 0; top: 56px;
  border-radius: 30px;
  border: 8px solid #26272c;
  box-shadow: {dev_shadow};
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


def render(html, width, height, out_path):
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
                f"file://{page}",
            ],
            check=True, capture_output=True,
        )
    finally:
        os.unlink(page)
    print(f"  {os.path.relpath(out_path, STORE)}")


# Fresh raw Wear capture staged for the Play wear listing; reused here.
WEAR_TRACKING = os.path.join(
    REPO, "android", "fastlane", "metadata", "android", "en-AU",
    "images", "wearScreenshots", "02.png",
)
WEAR_FRAMED = os.path.join(SCRIPT_DIR, "android", "wear-framed.png")


def frame_wear():
    """Composite the fresh Wear capture into the product frame (case + strap)
    from screenshots/watch_wear.png, replacing its stale screen content."""
    from PIL import Image, ImageDraw

    frame = Image.open(os.path.join(REPO, "screenshots", "watch_wear.png")).convert("RGBA")
    shot = Image.open(WEAR_TRACKING).convert("RGBA")
    size, cx, cy = 404, 220, 300
    shot = shot.resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size * 4 - 1, size * 4 - 1], fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)
    out = frame.copy()
    out.paste(shot, (cx - size // 2, cy - size // 2), mask)
    out.save(WEAR_FRAMED)
    print(f"  {os.path.relpath(WEAR_FRAMED, STORE)}")


# Shot list: (output stem, screen capture, caption, subcaption). Captions are
# pre-broken with \n so the line break lands where the board wants it.
# Each store shows its own platform's app: Play gets the Android captures
# (docs/screenshots/android/, see capture recipe in CLAUDE.md), the App Store
# gets the iOS ones.
def shots(locale, strings, out_subdir):
    if out_subdir == "play":
        track = os.path.join(SCRIPT_DIR, "android", "01-tracking.png")
        fav = os.path.join(SCRIPT_DIR, "android", "02-station-fav.png")
    else:
        track = os.path.join(SCRIPT_DIR, "iphone", "02-focused-tracking-raw.png")
        fav = os.path.join(REPO, "screenshots", "04-station-light-fav.png")
    return [
        ("01", track, strings["track_cap"], strings["track_sub"]),
        ("02", fav, strings["fav_cap"], strings["fav_sub"]),
    ]


# Wording follows apple/fastlane/metadata/: DE is informal du with Swiss ss,
# FR is vous, IT is tu. Play's Italian locale is it-IT; Apple's folder is it.
STRINGS = {
    "en-AU": {
        "track_cap": "Know exactly\nwhen to leave",
        "track_sub": "Live countdown, platform and walking time.",
        "fav_cap": "Favourites first,\nat every station",
        "fav_sub": "Star a connection to pin it to the top of that station's board.",
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
    pad = int(width * 0.078)
    cap = int(width * 0.082)
    # Three shots, three rule positions: the amber segment travels with the swipe.
    segs = ["0%", "36.5%", "73%"]
    sizes = dict(
        css=css, pad=pad, cap=cap, sub=int(cap * 0.42), rule=max(4, width // 270),
        devw=int(width * 0.86), devr=int(width * 0.115), bezel=max(8, width // 108),
        glow=int(width * 0.16),
    )
    for i, (stem, screen, caption, sub_text) in enumerate(shots(locale, strings, out_subdir)):
        html = PHONE_HTML.format(
            screen=screen, caption=caption, sub_text=sub_text, seg=segs[i], **sizes,
        )
        render(html, width, height, os.path.join(STORE, out_subdir, locale, f"{stem}.png"))

    # Watch pairings differ per store: the iOS app links Apple Watch + Garmin,
    # the Android app links Wear OS + Garmin. Never show a watch the store's
    # phone platform cannot pair with.
    garmin = os.path.join(SCRIPT_DIR, "garmin", "03-focused-tracking-framed.png")
    if out_subdir == "appstore":
        watches = [
            (os.path.join(SCRIPT_DIR, "apple", "02-focused-tracking.png"), "Apple Watch"),
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
        css=css, pad=pad, cap=cap, sub=int(cap * 0.42), rule=max(4, width // 270),
        seg=segs[2], grey=p["sub"], glow=int(width * 0.16),
        gap=int(width * 0.022), shadow=int(width * 0.016), blur=int(width * 0.055),
        framedh=int(width * 0.46), label=int(width * 0.026),
        caption=strings["watch_cap"], sub_text=watch_sub, items=items,
    )
    render(html, width, height, os.path.join(STORE, out_subdir, locale, "03.png"))


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
            watch=os.path.join(SCRIPT_DIR, "garmin", f"{name}-framed.png"),
        )
        png = os.path.join(STORE, "garmin", "tiles", f"{i:02d}.png")
        render(html, 500, 500, png)
        # PNG lands just over the dashboard's 150 KB cap; JPEG stays well under.
        subprocess.run(
            ["magick", png, "-quality", "92", png.replace(".png", ".jpg")], check=True,
        )
        os.unlink(png)


def build_garmin_hero(locale, strings, palette):
    p = PALETTES[palette]
    html = GARMIN_HERO_HTML.format(
        css=make_css(p), ink=p["ink"], seg=p["seg"], grey=p["sub"],
        tagline=strings["garmin_tag"],
        watch=os.path.join(SCRIPT_DIR, "garmin", "03-focused-tracking-framed.png"),
    )
    render(html, 1440, 720, os.path.join(STORE, "garmin", locale, "hero.png"))


def build_feature_graphic(locale, strings, palette):
    p = PALETTES[palette]
    html = FEATURE_HTML.format(
        css=make_css(p), ink=p["ink"], seg=p["seg"], grey=p["sub"],
        dev_shadow=p["dev_shadow"],
        tagline=strings["tagline"],
        screen=os.path.join(SCRIPT_DIR, "android", "01-tracking.png"),
        wear=WEAR_FRAMED,
    )
    render(html, 1024, 500, os.path.join(STORE, "feature", locale, "featureGraphic.png"))


if __name__ == "__main__":
    args = sys.argv[1:]
    palette = "swiss"
    if "--palette" in args:
        i = args.index("--palette")
        palette = args[i + 1]
        del args[i:i + 2]
    locales = args or list(STRINGS)
    frame_wear()
    print(f"[{palette}] Garmin tiles 500x500")
    build_garmin_tiles(palette)
    for locale in locales:
        strings = STRINGS[locale]
        print(f"[{locale}/{palette}] Play phone 1080x2160")
        build_locale(locale, strings, (1080, 2160), "play", palette)
        print(f"[{locale}/{palette}] App Store 1320x2868")
        build_locale(locale, strings, (1320, 2868), "appstore", palette)
        print(f"[{locale}/{palette}] Feature graphic 1024x500")
        build_feature_graphic(locale, strings, palette)
        print(f"[{locale}/{palette}] Garmin hero 1440x720")
        build_garmin_hero(locale, strings, palette)
    print("Done.")
