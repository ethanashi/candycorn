#!/usr/bin/env python3
"""Build a static side-by-side gallery: prototype screenshot vs native iOS screenshot per screen.

Usage: build-gallery.py <repo-root> <out-dir>
Copies PNGs into <out-dir>/proto and <out-dir>/ios and writes <out-dir>/index.html.
"""
import html
import pathlib
import re
import shutil
import sys

repo = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
proto_dir = repo / "apps/candycorn-prototype/screenshots"
ios_dir = repo / "apps/candycorn-ios/screenshots"

for sub in ("proto", "ios"):
    (out / sub).mkdir(parents=True, exist_ok=True)


def key(p: pathlib.Path) -> str:
    m = re.match(r"(\d+)", p.stem)
    return m.group(1).zfill(2) if m else p.stem


proto = {key(p): p for p in sorted(proto_dir.glob("*.png"))}
ios = {key(p): p for p in sorted(ios_dir.glob("*.png"))} if ios_dir.exists() else {}
keys = sorted(set(proto) | set(ios))

cards = []
for k in keys:
    p = proto.get(k)
    i = ios.get(k)
    name = (i or p).stem
    title = re.sub(r"^\d+-", "", name).replace("-", " ").capitalize()
    if p:
        shutil.copy(p, out / "proto" / p.name)
    if i:
        shutil.copy(i, out / "ios" / i.name)
    proto_img = f'<img src="proto/{html.escape(p.name)}" alt="Prototype {html.escape(title)}">' if p else '<div class="missing">No prototype frame</div>'
    ios_img = f'<img src="ios/{html.escape(i.name)}" alt="iOS {html.escape(title)}">' if i else '<div class="missing">Not captured yet</div>'
    cards.append(
        f'<section class="card"><h2>{k} {html.escape(title)}</h2>'
        f'<div class="pair"><figure>{proto_img}<figcaption>Prototype (web)</figcaption></figure>'
        f'<figure>{ios_img}<figcaption>Native iOS (simulator)</figcaption></figure></div></section>'
    )

page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Candy Corn: prototype vs native</title>
<style>
:root{{--orange:#f28a3c;--cocoa:#2d2825;--soft:#766d67;--hair:#ebe2d8;--warm:#fff4e8}}
body{{margin:0;background:#fff;color:var(--cocoa);font-family:"Avenir Next",Avenir,-apple-system,system-ui,sans-serif}}
header{{padding:32px 24px 8px;max-width:1200px;margin:0 auto}}
h1{{font-size:28px;margin:0 0 6px;font-weight:700}} header p{{color:var(--soft);margin:0;font-size:15px}}
main{{max-width:1200px;margin:0 auto;padding:16px 24px 64px;display:grid;gap:28px}}
.card{{border:1px solid var(--hair);border-radius:20px;padding:20px}}
.card h2{{font-size:17px;font-weight:600;margin:0 0 14px}}
.pair{{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:20px}}
figure{{margin:0}} figure img{{width:100%;max-width:390px;display:block;border:1px solid var(--hair);border-radius:24px;background:#fff}}
figcaption{{font-size:13px;color:var(--soft);margin-top:8px}}
.missing{{width:100%;max-width:390px;aspect-ratio:390/844;border:1px dashed var(--hair);border-radius:24px;display:grid;place-items:center;color:var(--soft);background:var(--warm);font-size:14px}}
.kernel{{display:inline-block;width:12px;height:16px;background:var(--orange);clip-path:polygon(50% 0,100% 100%,0 100%);border-radius:3px;margin-right:8px;vertical-align:-2px}}
</style></head><body>
<header><h1><span class="kernel"></span>Candy Corn: prototype vs native</h1>
<p>Left: approved Phase 0 web prototype. Right: the SwiftUI app running in the iPhone 17 simulator (iOS 26.5). {len(ios)} of {len(keys)} native screens captured.</p></header>
<main>{''.join(cards)}</main></body></html>"""
(out / "index.html").write_text(page)
print(f"wrote {out/'index.html'}: {len(keys)} screens, {len(ios)} native captures")
