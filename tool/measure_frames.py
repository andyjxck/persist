"""Measure frame pacing of the web build in headless Chromium.

Usage: python3 tool/measure_frames.py URL [width height seconds]

Opens URL (use ?demo so the game plays itself), waits for the game to
start, then records requestAnimationFrame intervals and prints the mean
frame time, p50/p95/p99 and the share of frames slower than 33 ms.
Headless Chromium renders in software, so frame rates are worse than on a
real machine and mostly limited by the rasteriser; main_thread_ms_per_frame
(CPU time the page spends per frame) is the number to compare between builds.
"""
import json
import sys

from playwright.sync_api import sync_playwright

url = sys.argv[1]
w = int(sys.argv[2]) if len(sys.argv) > 2 else 1440
h = int(sys.argv[3]) if len(sys.argv) > 3 else 900
secs = float(sys.argv[4]) if len(sys.argv) > 4 else 12

JS = """(secs) => new Promise(res => {
  const d = []; let last = performance.now(); const end = last + secs * 1000;
  function f(t) { d.push(t - last); last = t; if (t < end) requestAnimationFrame(f); else res(d); }
  requestAnimationFrame(f);
})"""

with sync_playwright() as p:
    b = p.chromium.launch(args=["--enable-unsafe-swiftshader", "--autoplay-policy=no-user-gesture-required"])
    pg = b.new_page(viewport={"width": w, "height": h}, device_scale_factor=1)
    pg.goto(url, wait_until="load")
    pg.wait_for_timeout(9000)  # engine + fonts + demo start
    cdp = pg.context.new_cdp_session(pg)
    cdp.send("Performance.enable")
    m0 = {m["name"]: m["value"] for m in cdp.send("Performance.getMetrics")["metrics"]}
    d = pg.evaluate(JS, secs)
    m1 = {m["name"]: m["value"] for m in cdp.send("Performance.getMetrics")["metrics"]}
    b.close()

d = sorted(x for x in d[1:] if x > 0)
n = len(d)
q = lambda f: d[min(n - 1, int(f * n))]
print(json.dumps({
    "url": url, "size": f"{w}x{h}", "frames": n,
    "mean_ms": round(sum(d) / n, 1), "fps": round(1000 * n / sum(d), 1),
    "p50": round(q(.5), 1), "p95": round(q(.95), 1), "p99": round(q(.99), 1),
    "slow_over_33ms_pct": round(100 * sum(1 for x in d if x > 33.4) / n, 1),
    # Main-thread CPU per frame: what the game itself costs, independent of
    # the software rasteriser.
    "main_thread_ms_per_frame": round(1000 * (m1["TaskDuration"] - m0["TaskDuration"]) / n, 2),
    "script_ms_per_frame": round(1000 * (m1["ScriptDuration"] - m0["ScriptDuration"]) / n, 2),
}))
