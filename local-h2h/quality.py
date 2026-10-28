#!/usr/bin/env python3
"""quality.py RESULTS.jsonl - checks the agent answers: E (rename) = the code block compared with score.rs after a
plain textual rename (exact match, line diff count, leftover `winner_side`); C (review + tests) = has a tests module,
how many #[test] functions, finish reason. Also the reasoning length."""
import difflib, json, os, re, sys
SRC = open(os.path.expanduser("~/code/ds41e/local/prompts/lookup/score.rs")).read()
WANT = SRC.replace("winner_side", "pick_winner")
for p in sys.argv[1:]:
    for ln in open(p):
        r = json.loads(ln)
        if r["name"] not in ("E", "C"):
            continue
        c = r["content"]
        blocks = re.findall(r"```rust\n(.*?)```", c, re.S)
        info = f"{r['tag']:14} {r['name']} out {r['usage'].get('completion_tokens')} finish {r['finish']} reasoning {len(r['reasoning'])} ch"
        if r["name"] == "E":
            b = blocks[0] if blocks else ""
            diff = [d for d in difflib.unified_diff(WANT.splitlines(), b.splitlines(), lineterm="", n=0)
                    if d[:1] in "+-" and not d.startswith(("+++", "---"))]
            info += f" | block {'yes' if blocks else 'NO'}, exact {b.strip() == WANT.strip()}, diff lines {len(diff)}, leftover winner_side {b.count('winner_side')}"
        else:
            info += f" | tests mod {'#[cfg(test)]' in c}, #[test] {c.count('#[test]')}"
        print(info)
