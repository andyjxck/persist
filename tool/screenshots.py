"""Take a burst of screenshots of a running build, for review.

Usage: python3 tool/screenshots.py URL OUTPREFIX WIDTH HEIGHT [count] [gap_ms] [scale]
"""
import sys

from playwright.sync_api import sync_playwright

url, out = sys.argv[1], sys.argv[2]
w, h = int(sys.argv[3]), int(sys.argv[4])
count = int(sys.argv[5]) if len(sys.argv) > 5 else 8
gap = int(sys.argv[6]) if len(sys.argv) > 6 else 400
scale = float(sys.argv[7]) if len(sys.argv) > 7 else 2

with sync_playwright() as p:
    b = p.chromium.launch(args=["--enable-unsafe-swiftshader", "--autoplay-policy=no-user-gesture-required"])
    pg = b.new_page(viewport={"width": w, "height": h}, device_scale_factor=scale)
    errors = []
    pg.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
    pg.goto(url, wait_until="load")
    pg.wait_for_timeout(7000)
    for i in range(count):
        pg.screenshot(path=f"{out}-{i:02d}.png")
        pg.wait_for_timeout(gap)
    b.close()
print("console errors:", errors)
