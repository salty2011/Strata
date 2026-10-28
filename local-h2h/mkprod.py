#!/usr/bin/env python3
"""mkprod.py SSD_GB: write prod.json (the production config run-lan.sh serves) from setup's config.
Context 262144 (Pi's window is 160K; the FP4 KV costs ~0.25 GB of VRAM there), vision off, DSpark auto (not loaded
here), --ssd-cache SSD_GB (the RAM store: free RAM vs speed, see the h2h report), lookup drafts on (K 12, gate 3,
n-gram 4), conversation slots in prod/ds4-slots next to the engine log (cap 8 GB), model id alias "local"."""
import json, os, sys
H = os.path.dirname(os.path.abspath(__file__))
UP = os.path.dirname(H)
ssd = sys.argv[1]
c = json.load(open(os.path.join(UP, "strata-deepseek-v4.1-flash-ist-das-2.00bpw.json")))
args = c["args"]
args[args.index("--max-context") + 1] = "262144"
if "--ssd-cache" in args:
    args[args.index("--ssd-cache") + 1] = ssd
else:
    args += ["--ssd-cache", ssd]
os.makedirs(os.path.join(H, "prod"), exist_ok=True)
c.update({"args": args, "args_written": list(args), "port": 8150, "aliases": ["local"],
          "log": os.path.join(H, "prod", "engine.log"),
          "env": {"STRATA_DSV41_LOOKUP": "12", "STRATA_DSV41_LOOKUP_GATE": "3", "STRATA_DSV41_LOOKUP_NGRAM": "4",
                  "STRATA_DS4_SLOT_GB": "8", "STRATA_DS4_SLOT_DIR": os.path.join(H, "prod", "ds4-slots")}})
json.dump(c, open(os.path.join(H, "prod.json"), "w"), indent=1)
print("prod.json:", " ".join(args[2:]), c["env"])
