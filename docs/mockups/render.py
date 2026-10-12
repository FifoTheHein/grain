#!/usr/bin/env python3
"""Render the mockup pages in docs/mockups/ to PNGs in docs/screenshots/.

    pip install playwright && python3 docs/mockups/render.py [name ...]

Uses the Chromium that ships with the container image; override with
CHROME_PATH if yours lives elsewhere.
"""
import os
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "screenshots"
CHROME = os.environ.get("CHROME_PATH", "/opt/pw-browsers/chromium-1194/chrome-linux/chrome")

# page, output name, body class, viewport height[, viewport width]
# Settings shots are wider: on a wide window the real Settings tab puts its
# group sidebar beside the page, so its shell is 1200 px (.shell.wide).
SHOTS = [
    ("recent.html", "recent-light", "grain-light", 1010),
    ("recent.html", "recent-dark", "grain-dark", 1010),
    ("recent-ahead.html", "recent-ahead", "grain-dark", 640),
    ("insights.html", "insights", "grain-light", 760),
    ("log-time.html", "log-time", "grain-dark", 920),
    ("work-item-picker.html", "work-item-picker", "grain-dark", 840),
    ("edit-time.html", "edit-time-timer", "grain-dark", 960),
    ("settings-appearance.html", "settings-appearance", "grain-light", 760, 1200),
    ("settings-rules.html", "settings-rules", "grain-dark", 720, 1200),
    ("settings-calendar.html", "settings-calendar", "grain-dark", 900, 1200),
]


def main(only):
    OUT.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=CHROME)
        for page_file, name, body_class, height, *rest in SHOTS:
            width = rest[0] if rest else 900
            if only and name not in only:
                continue
            src = HERE / page_file
            if not src.exists():
                print(f"skip {name}: {page_file} missing")
                continue
            page = browser.new_page(
                viewport={"width": width, "height": height},
                device_scale_factor=2,
            )
            page.goto(src.as_uri())
            page.eval_on_selector("body", "(b, c) => b.className = c", body_class)
            page.wait_for_timeout(250)
            dest = OUT / f"{name}.png"
            page.locator(".shell").screenshot(path=str(dest))
            page.close()
            print(f"wrote {dest.relative_to(HERE.parent.parent)}")
        browser.close()


if __name__ == "__main__":
    main(set(sys.argv[1:]))
