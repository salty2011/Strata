#!/usr/bin/env python3
"""lk_check.py - correctness checks for the lookup-draft port in upstream strata-dsv41 (local-lookup branch).

    lk_check.py URL ENGINE_LOG OUT.jsonl MODE [--key-file F]
MODE: t0 | sampled | edge | ab
  t0      edit task E and review task C at temperature 0: plain (strata_tune lookup 0) vs lookup (engine default),
          E plain once and lookup three times, C once each; the texts must be byte-identical
  sampled E at default sampling with lookup, then a follow-up turn on the answer (cache reuse, coherence)
  edge    max_tokens inside a lookup run, a cancel mid-answer (client closes the stream), then E at temp 0 again
  ab      one A/B round: E and C at default sampling, plain then lookup (per-request switch, same load)
Engine lines (decode, lookup stats, reuse) are read off ENGINE_LOG.  The key, if any, is never printed.
"""
import json, os, re, sys, time, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import h2h_client as H  # noqa: E402

def eng(log, off):
    with open(log, "rb") as f:
        f.seek(off)
        txt = f.read().decode("utf-8", "replace")
    out = {"lookup": [], "serve": [], "slots": []}
    for ln in txt.splitlines():
        if "ds4 serve: lookup" in ln:
            out["lookup"].append(ln.strip())
        elif "maya ds4 serve: prompt" in ln:
            out["serve"].append(ln.strip())
        elif "ds4 slots:" in ln:
            out["slots"].append(ln.strip())
        elif "ds4:" in ln and ("error" in ln.lower() or "fail" in ln.lower()):
            out.setdefault("errors", []).append(ln.strip())
    return out

def size(log):
    try:
        return os.path.getsize(log)
    except OSError:
        return 0

def main():
    url, log, out, mode = sys.argv[1:5]
    key = None
    if "--key-file" in sys.argv:
        key = open(os.path.expanduser(sys.argv[sys.argv.index("--key-file") + 1])).read().strip()
    cl = H.Client(url, key)
    lc = H.load_lookup()
    recs = []

    def run(name, msgs, mt, extra):
        off = size(log)
        r = cl.req(name, msgs, mt, extra)
        time.sleep(0.5)
        r["engine"] = eng(log, off)
        for ln in r["engine"]["lookup"] + r["engine"]["serve"] + r["engine"].get("errors", []):
            print("   ", ln[:220], flush=True)
        recs.append(r)
        return r

    PLAIN = {"strata_tune": {"lookup": 0}}
    if mode == "t0":
        E, C = lc.msgs(lc.TASK_E), lc.msgs(lc.TASK_C)
        p = run("E_t0_plain", E, 3000, dict(PLAIN, temperature=0))
        ls = [run(f"E_t0_lookup{i}", E, 3000, {"temperature": 0}) for i in (1, 2, 3)]
        cp = run("C_t0_plain", C, 1500, dict(PLAIN, temperature=0))
        cl_ = run("C_t0_lookup", C, 1500, {"temperature": 0})
        def same(a, b):
            return a["content"] == b["content"] and a["reasoning"] == b["reasoning"]
        for i, l in enumerate(ls, 1):
            print(f"E lookup{i} identical to plain: {same(p, l)} (out {l['usage'].get('completion_tokens')} vs "
                  f"{p['usage'].get('completion_tokens')})", flush=True)
        print(f"C lookup identical to plain: {same(cp, cl_)}", flush=True)
    elif mode == "sampled":
        E = lc.msgs(lc.TASK_E)
        r1 = run("E_sampled_lookup", E, 3000, None)
        m2 = E + [{"role": "assistant", "content": r1["content"]},
                  {"role": "user", "content": "Good. Now in one short paragraph, say which lines you changed and why "
                                              "nothing else changed."}]
        run("E_followup_lookup", m2, 600, None)
    elif mode == "edge":
        E = lc.msgs(lc.TASK_E)
        r = run("E_max700_lookup", E, 700, {"temperature": 0})
        print(f"max_tokens 700: completion {r['usage'].get('completion_tokens')}, finish {r['finish']}", flush=True)
        # a cancel: stream, read until ~300 deltas, close the connection
        body = {"model": "x", "messages": E, "max_tokens": 3000, "stream": True, "temperature": 0}
        h = {"Content-Type": "application/json"}
        if key:
            h["Authorization"] = "Bearer " + key
        off = size(log)
        rq = urllib.request.Request(url.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(),
                                    method="POST", headers=h)
        n = 0
        with urllib.request.urlopen(rq, timeout=3600) as resp:
            for raw in resp:
                if raw.startswith(b"data:"):
                    n += 1
                if n >= 300:
                    break
        print(f"cancelled after {n} chunks", flush=True)
        time.sleep(3)
        recs.append({"name": "E_cancel", "engine": eng(log, off), "chunks": n})
        for ln in recs[-1]["engine"]["lookup"] + recs[-1]["engine"]["serve"]:
            print("   ", ln[:220], flush=True)
        run("short_after_cancel", [{"role": "user", "content": "Say OK."}], 8, dict(H.NOTHINK))
        run("E_t0_after_cancel", E, 3000, {"temperature": 0})
    elif mode == "det":
        # temperature 0 determinism: E (300 tokens) read once, then plain / lookup alternating three times each
        E = lc.msgs(lc.TASK_E)
        run("det_fresh", E, 300, dict(PLAIN, temperature=0))
        rs = []
        for i in (1, 2, 3):
            rs.append(run(f"det_plain{i}", E, 300, dict(PLAIN, temperature=0)))
            rs.append(run(f"det_lookup{i}", E, 300, {"temperature": 0}))
        txt = [r["reasoning"] + "\x00" + r["content"] for r in rs]
        for i in range(len(rs)):
            row = []
            for j in range(len(rs)):
                k = 0
                while k < min(len(txt[i]), len(txt[j])) and txt[i][k] == txt[j][k]:
                    k += 1
                row.append("same" if txt[i] == txt[j] else str(k))
            print(f"{rs[i]['name']:12s}", " ".join(f"{c:>5s}" for c in row), flush=True)
    elif mode == "single":
        # one arm only (ds41e production: its own lookup, no per-request switch): short decode, E, C at its defaults
        rnd = sys.argv[sys.argv.index("--round") + 1] if "--round" in sys.argv else "1"
        S = [{"role": "user", "content": H.SHORT}]
        run(f"short_warm_r{rnd}", S, 300, dict(H.NOTHINK))
        run(f"short_ds41e_r{rnd}", S, 300, dict(H.NOTHINK))
        for task, mt, tn in ((lc.TASK_E, 3000, "E"), (lc.TASK_C, 1500, "C")):
            run(f"{tn}_ds41e_r{rnd}", lc.msgs(task), mt, None)
    elif mode == "prime":
        # cross-session shared start (Pi-style: the same ~12.5K system prompt, new sessions): A cold, B right after A,
        # an unrelated request X, then B2.  The engine lines say how much of each prompt was reused.
        import uuid
        sys_m = {"role": "system", "content": f"Session {uuid.uuid4().hex}. " + lc.SYSTEM + "\n\nContext files:\n\n" + lc.CTX}
        def ask(q):
            return [sys_m, {"role": "user", "content": lc.TARGET + q}]
        run("prime_A_cold", ask("In two sentences, what does `winner_side` return?"), 120, None)
        run("prime_B_after_A", ask("List the public functions in score.rs, one line each."), 120, None)
        run("prime_X_other", [{"role": "user", "content": "Say OK."}], 8, dict(H.NOTHINK))
        run("prime_B2_after_X", ask("Which function decides the winner, and on what?"), 120, None)
    elif mode == "restart":
        # the first agent request after a restart: E as before the restart (the slot folder should serve its prompt)
        run("E_after_restart", lc.msgs(lc.TASK_E), 3000, None)
    elif mode == "ab":
        rnd = sys.argv[sys.argv.index("--round") + 1] if "--round" in sys.argv else "1"
        arms = [("plain", PLAIN), ("lookup", {})]
        if int(rnd) % 2 == 0:
            arms.reverse()   # (alternate which arm goes first)
        S = [{"role": "user", "content": H.SHORT}]
        run(f"short_warm_r{rnd}", S, 300, dict(H.NOTHINK))   # (the short prompt read once: the pair below is decode)
        for arm, ex in arms:
            run(f"short_{arm}_r{rnd}", S, 300, dict(H.NOTHINK, **ex))
        for task, mt, tn in ((lc.TASK_E, 3000, "E"), (lc.TASK_C, 1500, "C")):
            for arm, ex in arms:
                run(f"{tn}_{arm}_r{rnd}", lc.msgs(task), mt, ex or None)
    with open(out, "a") as f:
        for r in recs:
            r["mode"], r["t"] = mode, time.strftime("%H:%M:%S")
            f.write(json.dumps(r) + "\n")

if __name__ == "__main__":
    main()
