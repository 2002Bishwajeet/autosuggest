#!/usr/bin/env python3
"""Fetch the latin-subset woff2 for the faces AutoSuggest's site uses, save them
locally, and emit a self-hosted @font-face stylesheet. Removes the Google Fonts
runtime dependency (a privacy/perf win for a privacy-branded product).

Variable faces (one woff2 covering a weight range) are stored once and declared
with a `font-weight: min max` range rather than duplicated per weight."""
import re
import os
import urllib.request

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

# family -> (css api spec, [(weight, style)] wanted)
JOBS = {
    "Instrument Serif": ("Instrument+Serif:ital@0;1",
                         [(400, "normal"), (400, "italic")]),
    "DM Sans": ("DM+Sans:wght@400;500;600;700",
                [(400, "normal"), (500, "normal"), (600, "normal"), (700, "normal")]),
    "JetBrains Mono": ("JetBrains+Mono:wght@400;500",
                       [(400, "normal"), (500, "normal")]),
}
STEM = {"Instrument Serif": "instrument-serif", "DM Sans": "dm-sans",
        "JetBrains Mono": "jetbrains-mono"}

os.makedirs("fonts", exist_ok=True)
BLOCK_RE = re.compile(r"/\*\s*([\w-]+)\s*\*/\s*(@font-face\s*\{[^}]*\})", re.S)


def fetch_css(spec):
    url = f"https://fonts.googleapis.com/css2?family={spec}&display=swap"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read().decode("utf-8")


def field(block, name):
    m = re.search(name + r":\s*([^;]+);", block)
    return m.group(1).strip() if m else None


def download(url, dest):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=20) as r:
        data = r.read()
    with open(dest, "wb") as f:
        f.write(data)
    return len(data)


face_css = []
for family, (spec, wanted) in JOBS.items():
    css = fetch_css(spec)
    latin = {}
    for subset, block in BLOCK_RE.findall(css):
        if subset != "latin":
            continue
        style = field(block, "font-style")
        weight = int(field(block, "font-weight"))
        src = re.search(r"url\((https://[^)]+\.woff2)\)", block)
        if src and style:
            latin[(weight, style)] = src.group(1)
    for w, s in wanted:
        if (w, s) not in latin:
            raise SystemExit(f"MISSING {family} {w} {s}; have {sorted(latin)}")
    # group wanted faces by (url, style) -> set of weights (variable => one url, many weights)
    groups = {}
    for w, s in wanted:
        url = latin[(w, s)]
        groups.setdefault((url, s), []).append(w)
    idx = 0
    for (url, style), weights in groups.items():
        weights.sort()
        suffix = "" if style == "normal" else "-italic"
        # if multiple weights collapse to one url -> variable, single file + range
        if len(groups) > 2:  # not expected; keep deterministic
            suffix += f"-{idx}"
        stem = STEM[family] + suffix
        dest = f"fonts/{stem}.woff2"
        size = download(url, dest)
        wval = str(weights[0]) if len(weights) == 1 else f"{weights[0]} {weights[-1]}"
        print(f"  {dest} ({size}B) weight={wval} style={style}")
        face_css += [
            "@font-face {",
            f"    font-family: '{family}';",
            f"    font-style: {style};",
            f"    font-weight: {wval};",
            "    font-display: swap;",
            f"    src: url('fonts/{stem}.woff2') format('woff2');",
            "}",
        ]
        idx += 1

header = [
    "/* ═══════════════════════════════════════",
    "   Self-hosted fonts (latin subset)",
    "   No third-party (Google) requests — privacy/perf for a privacy-first app.",
    "   Variable faces use a weight range + a single file.",
    "   Regenerate with scripts/fetch-fonts.py.",
    "   ═══════════════════════════════════════ */",
]
with open("css/fonts.css", "w") as f:
    f.write("\n".join(header + face_css) + "\n")
print("wrote css/fonts.css")
