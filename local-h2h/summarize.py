#!/usr/bin/env python3
"""summarize.py RESULTS.jsonl [...] - one line per (arm, request): n, TTFT, prompt tok/s, decode tok/s (server timings),
completion tokens, finish reasons; then the sampler files' peaks during each arm."""
import glob, json, os, re, statistics as st, sys
from collections import defaultdict

H = os.path.dirname(os.path.abspath(__file__))
rows = defaultdict(list)
for p in sys.argv[1:]:
    for ln in open(p):
        r = json.loads(ln)
        arm = re.sub(r"-r\d$", "", r["tag"])
        rows[(arm, r["name"])].append(r)

def med(xs):
    xs = [x for x in xs if x is not None]
    return round(st.median(xs), 2) if xs else None

print(f"{'arm':10} {'req':18} {'n':>2} {'ttft':>7} {'pp tps':>7} {'dec tps':>8} {'dec range':>12} {'out':>6} finish")
for (arm, name), rs in sorted(rows.items(), key=lambda kv: (kv[0][1], kv[0][0])):
    tim = [r.get("timings") or {} for r in rs]
    pt = [(r.get("usage") or {}).get("prompt_tokens") for r in rs]
    cached = [((r.get("usage") or {}).get("prompt_tokens_details") or {}).get("cached_tokens") for r in rs]
    pp = []
    for r, t, p, c in zip(rs, tim, pt, cached):
        if r.get("ttft") and p and (c or 0) < p * 0.5:
            pp.append((p - (c or 0)) / r["ttft"])
    dec = [t.get("predicted_per_second") or r.get("client_tps") for r, t in zip(rs, tim)]
    decv = [d for d in dec if d]
    rng = f"{min(decv):.1f}-{max(decv):.1f}" if decv else "-"
    outs = [(r.get("usage") or {}).get("completion_tokens") for r in rs]
    print(f"{arm:10} {name:18} {len(rs):>2} {str(med([r.get('ttft') for r in rs])):>7} {str(med(pp)):>7} "
          f"{str(med(dec)):>8} {rng:>12} {str(med(outs)):>6} {','.join(str(r.get('finish')) for r in rs)}"
          f"{' ERR ' + str([r['error'] for r in rs if r.get('error')]) if any(r.get('error') for r in rs) else ''}")

print("\nsampler peaks (power W max/median during busy>50%, edge/junction C max, VRAM MiB max, MemAvailable GiB min, engine RSS GiB max)")
for f in sorted(glob.glob(f"{H}/samp-*.txt")):
    L = [l.split() for l in open(f).read().splitlines()[1:] if len(l.split()) == 8]
    if not L:
        continue
    busy = [l for l in L if l[4].isdigit() and int(l[4]) > 50] or L
    pw = [int(l[1]) for l in busy]
    print(f"{os.path.basename(f):24} power max {max(pw)} med {int(st.median(pw))}  temp {max(int(l[2]) for l in L)}/"
          f"{max(int(l[3]) for l in L)}  vram {max(int(l[5]) for l in L)}  memavail min {min(float(l[6]) for l in L)}  "
          f"rss {max(float(l[7]) for l in L)}")
