#!/usr/bin/env python3
"""make_prompts.py - fixed long code prompts (8K, 17K, 60K tokens of C++/Python source) for the engine A/B.
Token counts use ds41e's tokenizer read from the model's GGUF (the same vocabulary both engines use)."""
import glob, os, sys
sys.path.insert(0, os.path.expanduser("~/code/strata-up/tools"))
import strata_tokenizer as ST

GGUF = "/srv/models/ds41e/rco-iq2xxs/DeepSeek-V4.1-Flash-1017-GSQ-RCO-IQ2_XXS-00001-of-00004.gguf"
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.expanduser("~/code/strata-up")
FILES = sorted(glob.glob(f"{SRC}/serve/*.py")) + sorted(glob.glob(f"{SRC}/src/dsv41/*.hpp")) + \
        sorted(glob.glob(f"{SRC}/src/dsv41/*.cpp"))

def main():
    tok = ST.Tokenizer.from_gguf(GGUF)
    os.makedirs(f"{HERE}/prompts", exist_ok=True)
    for name, target in (("8k", 8000), ("17k", 17000), ("60k", 60000)):
        out, n = [], 0
        for f in FILES:
            rel = os.path.relpath(f, SRC)
            lines = open(f, errors="replace").read().splitlines(True)
            block_lines = []
            head = f"File `{rel}`:\n```\n"
            for ln in lines:
                block_lines.append(ln)
            text = head + "".join(block_lines) + "```\n\n"
            t = len(tok.encode(text))
            if n + t <= target:
                out.append(text); n += t
                continue
            # trim this file to fit
            lo, hi = 0, len(lines)
            while lo < hi:
                mid = (lo + hi + 1) // 2
                tt = len(tok.encode(head + "".join(lines[:mid]) + "```\n\n"))
                if n + tt <= target:
                    lo = mid
                else:
                    hi = mid - 1
            if lo > 0:
                text = head + "".join(lines[:lo]) + "```\n\n"
                out.append(text); n += len(tok.encode(text))
            break
        open(f"{HERE}/prompts/code{name}.txt", "w").write("".join(out))
        print(name, n, "tokens,", len("".join(out)), "chars")

if __name__ == "__main__":
    main()
