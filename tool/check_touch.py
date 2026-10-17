"""Play the first round by touch on an emulated 3x phone, to check that taps
land where the buttons are drawn (the build caps phones at 2x).

Usage: python3 tool/check_touch.py URL

Taps the menu's play button (found through Flutter's accessibility tree),
then taps the middle of the play area. Counts the press and clear sounds
(press = a button was hit, clear = the round was won).
"""
import json
import sys

from playwright.sync_api import sync_playwright

url = sys.argv[1]
INIT = """
(() => {
  window.__bp = [];
  const o = AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start = function (...a) {
    if (this.buffer && this.buffer.duration > 0.001) window.__bp.push(Math.round(this.buffer.duration * 1000));
    return o.apply(this, a);
  };
})();
"""
with sync_playwright() as p:
    b = p.chromium.launch(args=["--enable-unsafe-swiftshader", "--autoplay-policy=user-gesture-required"])
    ctx = b.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=3, is_mobile=True, has_touch=True)
    ctx.add_init_script(INIT)
    pg = ctx.new_page()
    pg.goto(url, wait_until="load")
    pg.wait_for_timeout(6000)
    dpr = pg.evaluate("window.devicePixelRatio")
    canvas_w = pg.evaluate("(() => { const c = document.querySelector('canvas'); return c ? c.width : null; })()")
    pg.evaluate("document.querySelector('flt-semantics-placeholder') && document.querySelector('flt-semantics-placeholder').click()")
    pg.wait_for_timeout(1500)
    labels = pg.evaluate("""[...document.querySelectorAll('flt-semantics [role=button], flt-semantics[role=button], [role=button]')].map(e => {
        const r = e.getBoundingClientRect(); return {t: (e.getAttribute('aria-label') || e.innerText || '').trim(), x: r.x + r.width / 2, y: r.y + r.height / 2}; })""")
    target = next((l for l in labels if any(k in l["t"].upper() for k in ("PLAY", "ENDLESS", "START"))), None)
    result = {"devicePixelRatio_seen_by_game": dpr, "canvas_width_px": canvas_w, "menu_buttons": [l["t"] for l in labels]}
    if target:
        pg.touchscreen.tap(target["x"], target["y"])
        pg.wait_for_timeout(2500)
        before = len(pg.evaluate("window.__bp"))
        for _ in range(3):
            pg.touchscreen.tap(195, 540)
            pg.wait_for_timeout(700)
        sounds = pg.evaluate("window.__bp")[before:]
        result.update({"tapped": target["t"], "sounds_after_game_taps_ms": sounds,
                       "press_sounds": sounds.count(45), "clear_sounds": sum(1 for s in sounds if 80 <= s <= 400)})
        pg.screenshot(path="/tmp/touch_after.png")
    print(json.dumps(result, indent=1))
    b.close()
