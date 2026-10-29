"""Fits a damped spring to the motion curves the spike records (S2, S6).

Run: nix-shell -p 'python3.withPackages(ps: [ps.numpy ps.scipy])' --run 'python3 fit_spring.py <evidence-dir>'
      python3 fit_spring.py --selftest   (recovers known constants from synthetic data)

Model: unit-mass spring released at t0 with displacement d = x0 - xf and initial velocity v0,
  x(t) = xf + displacement(t - t0; d, v0, omega, zeta), x = x0 for t < t0.
Reported per segment: SwiftUI-style response = 2*pi/omega and dampingFraction = zeta,
CASpringAnimation-style stiffness = omega^2 and damping = 2*zeta*omega (mass 1),
settle time to within 1% of |d| (model and data), and the RMS fit error in points and % of |d|.
"""
import glob
import json
import math
import os
import sys

import numpy as np
from scipy.optimize import least_squares


def displacement(tau, d, v0, omega, zeta):
    tau = np.maximum(tau, 0.0)
    if zeta < 1.0 - 1e-6:
        wd = omega * math.sqrt(1 - zeta * zeta)
        return np.exp(-zeta * omega * tau) * (d * np.cos(wd * tau) + (v0 + zeta * omega * d) / wd * np.sin(wd * tau))
    if zeta <= 1.0 + 1e-6:
        return np.exp(-omega * tau) * (d + (v0 + omega * d) * tau)
    s = math.sqrt(zeta * zeta - 1)
    r1, r2 = -omega * (zeta - s), -omega * (zeta + s)
    b = (v0 - r1 * d) / (r2 - r1)
    return (d - b) * np.exp(r1 * tau) + b * np.exp(r2 * tau)


def model(p, t):
    t0, x0, xf, v0, omega, zeta = p
    return np.where(t < t0, x0, xf + displacement(t - t0, x0 - xf, v0, omega, zeta))


def fit(t, x):
    """Least-squares spring fit; several damping starts to avoid local minima."""
    t = np.asarray(t, float)
    x = np.asarray(x, float)
    moving = np.nonzero(np.abs(np.diff(x)) > 0.5)[0]
    t0g = t[moving[0]] if len(moving) else t[0]
    best = None
    for zeta0 in (0.5, 0.8, 1.0, 1.5):
        for omega0 in (8.0, 15.0, 30.0):
            p0 = [t0g, x[0], x[-1], 0.0, omega0, zeta0]
            lo = [t[0] - 0.2, -1e5, -1e5, -1e6, 1.0, 0.05]
            hi = [t[-1], 1e5, 1e5, 1e6, 200.0, 5.0]
            r = least_squares(lambda p: model(p, t) - x, p0, bounds=(lo, hi), loss="soft_l1", f_scale=2.0)
            if best is None or r.cost < best.cost:
                best = r
    p = best.x
    resid = model(p, t) - x
    d = abs(p[1] - p[2])
    t0, omega, zeta = p[0], p[4], p[5]
    dense = np.linspace(t0, t0 + 5, 5001)
    out = np.abs(model(p, dense) - p[2]) > 0.01 * max(d, 1e-9)
    settle_model = dense[np.nonzero(out)[0][-1]] - t0 if out.any() else 0.0
    out_data = np.abs(x - p[2]) > max(0.01 * d, 1.0)
    settle_data = t[np.nonzero(out_data)[0][-1]] - t0 if out_data.any() else 0.0
    rms = float(np.sqrt(np.mean(resid ** 2)))
    return {
        "t0": float(t0), "from": float(p[1]), "to": float(p[2]), "v0": float(p[3]),
        "response": 2 * math.pi / omega, "dampingFraction": float(zeta),
        "stiffness": float(omega * omega), "damping": float(2 * zeta * omega),
        "settle1pctModelS": float(settle_model), "settle1pctDataS": float(settle_data),
        "rmsPts": rms, "rmsPctOfTravel": 100 * rms / max(d, 1e-9), "samples": int(len(t)),
    }


def left_edge(samples, screen_w):
    """Marker left edge, reconstructed when the marker is clipped by a screen edge."""
    full = [s["x1"] - s["x0"] for s in samples if s.get("n") and s["x0"] > 1 and s["x1"] < screen_w - 2]
    width = float(np.median(full)) if full else None
    ts, xs = [], []
    for s in samples:
        if not s.get("n") or width is None:
            continue
        x = s["x1"] - width if s["x0"] <= 1 else s["x0"]
        ts.append(s["t"])
        xs.append(x)
    return ts, xs


def window(ts, xs, start, end):
    keep = [(t, x) for t, x in zip(ts, xs) if start <= t <= end]
    return [k[0] for k in keep], [k[1] for k in keep]


def segments(path):
    doc = json.load(open(path))
    m, s = doc["meta"], doc["samples"]
    name = os.path.basename(path)
    screen_w = max((x.get("x1", 0) for x in s), default=0) + 2
    segs = []
    if name.startswith("s6-magnification"):
        ts = [x["t"] for x in s if x.get("top", -1) >= 0]
        ys = [x["top"] for x in s if x.get("top", -1) >= 0]
        segs.append(("magnify-in", *window(ts, ys, m["tIn"] - 0.05, m["tOut"])))
        segs.append(("magnify-out", *window(ts, ys, m["tOut"] - 0.05, m["tOut"] + 1.2)))
    elif name.startswith("s6-mission-control"):
        ts = [x["t"] for x in s if x.get("n")]
        ws = [x["x1"] - x["x0"] for x in s if x.get("n")]
        segs.append(("mc-enter-width", *window(ts, ws, m["tEnter"] - 0.05, m["tExit"])))
        segs.append(("mc-exit-width", *window(ts, ws, m["tExit"] - 0.05, m["tExit"] + 1.6)))
    else:  # Space slides (S2 runs, S6 Ctrl+Arrow): fit the return, where the marker lands on screen
        ts, xs = left_edge(s, screen_w)
        back = m.get("tBackEvents") or m.get("tBack")
        if back:
            segs.append(("slide-back", *window(ts, xs, back - 0.05, back + 1.4)))
    return segs


def selftest():
    t = np.arange(0, 1.2, 1 / 60)
    truth = [0.1, 0.0, 600.0, 0.0, 2 * math.pi / 0.35, 0.86]
    x = model(truth, t) + np.random.default_rng(1).normal(0, 0.5, t.size)
    r = fit(t, x)
    assert abs(r["response"] - 0.35) < 0.01, r
    assert abs(r["dampingFraction"] - 0.86) < 0.03, r
    print("selftest ok", json.dumps({k: round(v, 4) for k, v in r.items()}))


def main():
    if sys.argv[1:] == ["--selftest"]:
        selftest()
        return
    rows = []
    for path in sorted(glob.glob(os.path.join(sys.argv[1], "s[26]-*.json"))):
        for label, t, x in segments(path):
            if len(t) < 8 or max(x) - min(x) < 4:
                rows.append({"file": os.path.basename(path), "segment": label, "skipped": "too few moving samples", "samples": len(t)})
                continue
            rows.append({"file": os.path.basename(path), "segment": label, **fit(t, x)})
    print(json.dumps(rows, indent=1))


if __name__ == "__main__":
    main()
