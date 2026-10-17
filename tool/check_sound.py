"""Check that sound really plays in the web build, the way a phone browser
would treat it (audio blocked until the first touch).

Usage: python3 tool/check_sound.py URL

Opens URL as a touch phone with the strict autoplay policy, checks that
nothing plays before the first touch, taps the screen once, then counts every
Web Audio buffer that starts playing (and which sound it was) while the game
plays itself (use ?demo in URL).
"""
import json
import sys

from playwright.sync_api import sync_playwright

url = sys.argv[1]

INIT = """
(() => {
  window.__bp = {starts: [], states: []};
  const AC = window.AudioContext || window.webkitAudioContext;
  const origStart = AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start = function (...a) {
    const b = this.buffer;
    window.__bp.starts.push({t: performance.now(), dur: b ? b.duration : 0, ch: b ? b.length : 0,
      state: this.context.state, peak: b ? Math.max(...b.getChannelData(0).slice(0, 4000).map(Math.abs)) : 0});
    return origStart.apply(this, a);
  };
  const origDecode = BaseAudioContext.prototype.decodeAudioData;
  window.__bp.decoded = 0;
  BaseAudioContext.prototype.decodeAudioData = function (...a) {
    const p = origDecode.apply(this, a);
    if (p && p.then) p.then(() => window.__bp.decoded++);
    return p;
  };
})();
"""

with sync_playwright() as p:
    b = p.chromium.launch(args=["--enable-unsafe-swiftshader", "--autoplay-policy=user-gesture-required"])
    ctx = b.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=3, is_mobile=True, has_touch=True,
                        user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1")
    ctx.add_init_script(INIT)
    pg = ctx.new_page()
    errors = []
    pg.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
    pg.on("pageerror", lambda e: errors.append(str(e)))
    pg.goto(url, wait_until="load")
    pg.wait_for_timeout(6000)
    before = pg.evaluate("window.__bp.starts.filter(s => s.dur > 0.001).length")
    pg.touchscreen.tap(195, 700)
    pg.wait_for_timeout(8000)
    res = pg.evaluate("window.__bp")
    b.close()

real = [s for s in res["starts"] if s["dur"] > 0.001]
durs = {}
for s in real:
    k = round(s["dur"] * 1000)
    durs[k] = durs.get(k, 0) + 1
print(json.dumps({
    "sounds_before_first_touch": before,
    "decoded_sound_files": res["decoded"],
    "sounds_started_after_touch": len(real),
    "started_while_context_running": sum(1 for s in real if s["state"] == "running"),
    "sounds_with_audible_samples": sum(1 for s in real if s["peak"] > 0.01),
    "by_length_ms": durs,
    "errors": errors,
}, indent=1))
