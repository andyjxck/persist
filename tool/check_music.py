"""Check the soundtrack in the web build the way a phone would play it: it
must start once per run and carry on without a break across every round
change, building as the rounds go up.

Usage: python3 tool/check_music.py URL [seconds]

Opens URL (use ?demo so the game plays itself) as a touch phone with the
strict autoplay policy, taps once to unlock audio, then every 100 ms reads
the soundtrack's state (bpSound.music.stats()) and the loudness of what it is
playing (an analyser tapped off its output). A round change shows up as a
new target tempo. Fails if the soundtrack started more than once, if its step
counter ever went backwards or stalled across a round change, or if it went
silent around a round change (or for more than half a second at any
point while it should be playing).
"""
import json
import sys

from playwright.sync_api import sync_playwright

url = sys.argv[1]
secs = float(sys.argv[2]) if len(sys.argv) > 2 else 30

INIT = """
(() => {
  window.__an = null;
  const orig = DynamicsCompressorNode.prototype.connect;
  DynamicsCompressorNode.prototype.connect = function (dest, ...a) {
    try {
      const an = this.context.createAnalyser();
      an.fftSize = 2048;
      orig.call(this, an);
      window.__an = an;
    } catch (e) {}
    return orig.call(this, dest, ...a);
  };
  window.__rms = () => {
    const an = window.__an;
    if (!an) return 0;
    const d = new Float32Array(an.fftSize);
    an.getFloatTimeDomainData(d);
    let s = 0;
    for (const v of d) s += v * v;
    return Math.sqrt(s / d.length);
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
    pg.wait_for_timeout(500)
    pg.touchscreen.tap(195, 140)  # unlock audio, away from the buttons
    samples = []
    for _ in range(int(secs * 10)):
        pg.wait_for_timeout(100)
        s = pg.evaluate("(() => { const m = window.bpSound && bpSound.music; if (!m) return null; const s = m.stats(); s.rms = window.__rms(); s.wall = performance.now(); return s; })()")
        if s:
            samples.append(s)
    b.close()

playing = [s for s in samples if s["playing"] and s["state"] == "running"]
changes = []
for i in range(1, len(playing)):
    if abs(playing[i]["targetBpm"] - playing[i - 1]["targetBpm"]) > 0.01:
        changes.append(i)

backwards = sum(1 for i in range(1, len(playing)) if playing[i]["step"] < playing[i - 1]["step"])
# Around each round change (0.5 s either side) the step counter must keep
# moving and the music must stay audible.
stalls, silent = 0, 0
for i in changes:
    win = playing[max(0, i - 5): i + 6]
    if win[-1]["step"] <= win[0]["step"]:
        stalls += 1
    if not any(w["ducked"] for w in win) and max(w["rms"] for w in win) < 0.003:
        silent += 1

# Longest stretch the music was near-silent while it should be playing.
longest, run = 0, 0
for s in playing:
    run = run + 1 if (s["rms"] < 0.003 and not s["ducked"]) else 0
    longest = max(longest, run)

result = {
    "samples_while_playing": len(playing),
    "soundtrack_starts": samples[-1]["starts"] if samples else None,
    "round_changes_seen": len(changes),
    "tempo_first_last": [round(playing[0]["bpm"], 1), round(playing[-1]["bpm"], 1)] if playing else None,
    "tier_first_last": [playing[0]["tier"], playing[-1]["tier"]] if playing else None,
    "steps_played": playing[-1]["step"] if playing else 0,
    "step_counter_went_backwards": backwards,
    "stalls_at_round_change": stalls,
    "silent_at_round_change": silent,
    "longest_quiet_stretch_ms": longest * 100,
    "mean_rms_while_playing": round(sum(s["rms"] for s in playing) / max(1, len(playing)), 4),
    "peak_urgency": round(max((s["urgency"] for s in playing), default=0), 2),
    "errors": errors,
}
result["ok"] = bool(playing) and result["soundtrack_starts"] == 1 and len(changes) >= 3 and backwards == 0 and stalls == 0 and silent == 0 and longest <= 5 and not errors
print(json.dumps(result, indent=1))
sys.exit(0 if result["ok"] else 1)
