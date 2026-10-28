#!/usr/bin/env python3
"""h2h_client.py - identical requests against an OpenAI-compatible server for the ds41e vs upstream strata-dsv41 A/B.

    h2h_client.py URL TAG OUT.jsonl MODE [--key-file F]
MODE: decode | prefill | prefill60 | agent | all
Streams every request: TTFT = first delta (reasoning or content); decode = the server's final-chunk timings
(predicted_per_second) and a client-side rate (completion_tokens over first-to-last delta).  The API key, if any,
is read from --key-file and never printed.  Prompts live in ./prompts (made by make_prompts.py) and the agent tasks
are the ones in ds41e local/bench-v41/lookup-client.py (imported, so both engines get the same bytes).
"""
import importlib.util, json, os, sys, time, uuid, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
P = os.path.join(HERE, "prompts")
LC = os.path.expanduser("~/code/ds41e/local/bench-v41/lookup-client.py")

def load_lookup():
    spec = importlib.util.spec_from_file_location("lookup_client", LC)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

def rd(n):
    return open(os.path.join(P, n)).read()

SHORT = ("Write a Python function `parse_duration(s: str) -> int` that converts an ISO 8601 duration such as "
         "`P3DT4H5M6S` into seconds. Include a docstring, raise ValueError on bad input, and show three example calls.")
ASK = "\n\nSummarize what the code above does in ten bullet points, then name one likely bug and how to fix it."
FOLLOW = "Now write one unit test for the first function you mentioned. Keep it under 20 lines."
NOTHINK = {"chat_template_kwargs": {"enable_thinking": False}}

class Client:
    def __init__(self, url, key):
        self.url, self.key = url.rstrip("/") + "/v1/chat/completions", key

    def req(self, name, messages, max_tokens, extra=None):
        body = {"model": "x", "messages": messages, "max_tokens": max_tokens, "stream": True}
        body.update(extra or {})
        h = {"Content-Type": "application/json"}
        if self.key:
            h["Authorization"] = "Bearer " + self.key
        r = urllib.request.Request(self.url, data=json.dumps(body).encode(), method="POST", headers=h)
        t0 = time.time()
        t_first = t_last = None
        content, reasoning, last, n_deltas, err = [], [], None, 0, None
        try:
            with urllib.request.urlopen(r, timeout=3600) as resp:
                for raw in resp:
                    line = raw.decode("utf-8", "replace").strip()
                    if not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if data == "[DONE]":
                        break
                    try:
                        c = json.loads(data)
                    except ValueError:
                        continue
                    if c.get("error"):
                        err = c["error"]
                    ch = (c.get("choices") or [{}])[0]
                    d = ch.get("delta") or {}
                    txt = (d.get("content") or "") + (d.get("reasoning_content") or d.get("reasoning") or "")
                    if txt:
                        now = time.time()
                        t_first = t_first or now
                        t_last = now
                        n_deltas += 1
                    content.append(d.get("content") or "")
                    reasoning.append(d.get("reasoning_content") or d.get("reasoning") or "")
                    last = c
        except Exception as e:  # noqa: BLE001 - record and go on
            err = repr(e)
        wall = time.time() - t0
        usage = (last or {}).get("usage") or {}
        tim = (last or {}).get("timings") or {}
        ct = usage.get("completion_tokens")
        span = (t_last - t_first) if (t_first and t_last) else None
        rec = {"name": name, "wall": round(wall, 2), "ttft": round(t_first - t0, 3) if t_first else None,
               "finish": ((last or {}).get("choices") or [{}])[0].get("finish_reason"),
               "usage": usage, "timings": tim, "deltas": n_deltas,
               "client_tps": round((ct - 1) / span, 2) if (ct and span and span > 0 and ct > 1) else None,
               "content": "".join(content), "reasoning": "".join(reasoning), "error": err}
        pt = usage.get("prompt_tokens")
        cached = (usage.get("prompt_tokens_details") or {}).get("cached_tokens")
        print(f"{name}: ttft {rec['ttft']} s, wall {wall:.1f} s, prompt {pt} (cached {cached}), out {ct}, "
              f"server tps {tim.get('predicted_per_second')}, client tps {rec['client_tps']}, "
              f"prompt tps {tim.get('prompt_per_second')}, finish {rec['finish']}, err {err}", flush=True)
        return rec

def nonce_sys():
    return {"role": "system", "content": f"Request {uuid.uuid4().hex}. You are a careful senior software engineer."}

def run(cl, mode):
    recs = []
    if mode == "warm":
        recs.append(cl.req("warm", [{"role": "user", "content": "Reply with one short sentence: what is a Rust trait?"}],
                           60, dict(NOTHINK)))
    if mode in ("decode", "all"):
        m = [{"role": "user", "content": SHORT}]
        g = dict(NOTHINK, temperature=0)
        recs.append(cl.req("short_t0_a", m, 300, g))
        recs.append(cl.req("short_t0_b", m, 300, g))        # prompt cached: pure decode
        recs.append(cl.req("short_default", m, 300, dict(NOTHINK)))   # the server's default sampling
    if mode in ("prefill", "all"):
        g = dict(NOTHINK, temperature=0)
        for size in ("8k", "17k"):
            m = [nonce_sys(), {"role": "user", "content": rd(f"code{size}.txt") + ASK}]
            r1 = cl.req(f"cold_{size}", m, 300, g)
            recs.append(r1)
            if size == "17k":
                recs.append(cl.req("decode_17k_cached", m, 300, g))   # same prompt again: decode at 17K context
                m2 = m + [{"role": "assistant", "content": r1["content"]}, {"role": "user", "content": FOLLOW}]
                recs.append(cl.req("followup_17k", m2, 200, g))
    if mode in ("prefill60",):
        g = dict(NOTHINK, temperature=0)
        m = [nonce_sys(), {"role": "user", "content": rd("code60k.txt") + ASK}]
        recs.append(cl.req("cold_60k", m, 200, g))
    if mode in ("agent", "agentnt"):
        lc = load_lookup()
        for task, mt, tname in ((lc.TASK_E, 3000, "E"), (lc.TASK_C, 1500, "C")):
            recs.append(cl.req(tname, lc.msgs(task), mt, NOTHINK if mode == "agentnt" else None))
    return recs

def main():
    url, tag, out, mode = sys.argv[1:5]
    key = None
    if "--key-file" in sys.argv:
        key = open(os.path.expanduser(sys.argv[sys.argv.index("--key-file") + 1])).read().strip()
    recs = run(Client(url, key), mode)
    with open(out, "a") as f:
        for r in recs:
            r["tag"], r["mode"], r["t"] = tag, mode, time.strftime("%H:%M:%S")
            f.write(json.dumps(r) + "\n")

if __name__ == "__main__":
    main()
