#!/usr/bin/env python3
"""ab_sum.py RESULTS.jsonl [...]: median server decode tok/s (and TTFT) per (task, arm) over rounds; E exactness."""
import json, re, statistics, sys, os
ref = open(os.path.expanduser("~/code/ds41e/local/prompts/lookup/score.rs")).read().replace("winner_side", "pick_winner")
rows = {}
for path in sys.argv[1:]:
    for l in open(path):
        r = json.loads(l)
        n = r.get("name", "")
        m = re.match(r"(short|E|C)_(plain|lookup|ds41e)_r(\d)", n)
        if not m:
            continue
        tps = (r.get("timings") or {}).get("predicted_per_second")
        k = (m[1], m[2])
        d = rows.setdefault(k, {"tps": [], "ttft": [], "exact": [], "out": []})
        if tps:
            d["tps"].append(tps)
        d["ttft"].append(r.get("ttft"))
        d["out"].append((r.get("usage") or {}).get("completion_tokens"))
        if m[1] == "E":
            mm = re.search(r"```rust\n(.*?)```", r.get("content", ""), re.S)
            d["exact"].append(bool(mm) and mm.group(1).strip() == ref.strip())
for k in sorted(rows):
    d = rows[k]
    med = statistics.median(d["tps"]) if d["tps"] else None
    print(f"{k[0]:5s} {k[1]:6s} median {med} range {min(d['tps'], default=None)}-{max(d['tps'], default=None)} "
          f"n {len(d['tps'])} ttft {d['ttft']} out {d['out']} exact {d['exact']}")
