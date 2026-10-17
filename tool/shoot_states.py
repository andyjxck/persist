"""Screenshot the main states of a build (menu, a few rounds, game over) at
desktop and phone sizes, for visual review.

Usage: python3 tool/shoot_states.py BASE_URL OUTDIR [reduce] [desk|lap|phone|small ...]
BASE_URL is the served build (e.g. http://localhost:8123/). Practice links
(?from=N&seed=S) are used so nothing is saved.
"""
import os
import sys

from playwright.sync_api import sync_playwright

base, out = sys.argv[1], sys.argv[2]
reduce = 'reduce' in sys.argv[3:]
only = [a for a in sys.argv[3:] if a != 'reduce']
os.makedirs(out, exist_ok=True)

DEVICES = {
    'desk': dict(viewport={'width': 1440, 'height': 900}, device_scale_factor=1),
    'lap': dict(viewport={'width': 1024, 'height': 640}, device_scale_factor=1),
    'phone': dict(viewport={'width': 390, 'height': 844}, device_scale_factor=2, is_mobile=True, has_touch=True),
    'small': dict(viewport={'width': 320, 'height': 568}, device_scale_factor=2, is_mobile=True, has_touch=True),
}


def press_start(pg, mobile):
    vp = pg.viewport_size
    # The big button sits in the middle of the screen; Space works on desktop.
    if mobile:
        pg.touchscreen.tap(vp['width'] / 2, vp['height'] * 0.55)
    else:
        pg.keyboard.press('Space')


errors = []
with sync_playwright() as p:
    b = p.chromium.launch(args=['--enable-unsafe-swiftshader', '--autoplay-policy=no-user-gesture-required'])
    for name, opts in DEVICES.items():
        if only and name not in only:
            continue
        mobile = opts.get('is_mobile', False)
        ctx = b.new_context(reduced_motion='reduce' if reduce else 'no-preference', **opts)
        pg = ctx.new_page()
        pg.on('console', lambda m: errors.append(f'{name}: {m.text}') if m.type == 'error' else None)
        pg.on('pageerror', lambda e: errors.append(f'{name}: {e}'))
        pg.goto(base, wait_until='load')
        pg.wait_for_timeout(6000)
        pg.screenshot(path=f'{out}/{name}-0-menu.png')
        # Into a practice run from round 6 with a fixed seed.
        pg.goto(base + '?from=6&seed=7', wait_until='load')
        pg.wait_for_timeout(6000)
        press_start(pg, mobile)
        pg.wait_for_timeout(900)
        pg.screenshot(path=f'{out}/{name}-1-round.png')
        pg.wait_for_timeout(1700)
        pg.screenshot(path=f'{out}/{name}-2-round-late.png')
        # Let the clock run out for the game-over screen.
        pg.wait_for_timeout(9000)
        pg.screenshot(path=f'{out}/{name}-3-over.png')
        ctx.close()
    b.close()
print('errors:', errors[:20])
