# lib.sh - sourced by the h2h session scripts (run under: flock ~/bigrig-gpu.lock ...)
H=~/code/strata-up/local-h2h
UP=~/code/strata-up
BASECFG=$UP/strata-deepseek-v4.1-flash-ist-das-2.00bpw.json
log() { echo "[$(date +%T)] $*" | tee -a $H/session.log; }

wait_free() {   # VRAM used < 1 GB and MemAvailable > 110 GB
  local i=0
  while [ $i -lt 180 ]; do
    used=$(rocm-smi --showmeminfo vram 2>/dev/null | awk '/Used Memory/ {print $NF; exit}')
    avail=$(awk '/MemAvailable/ {print int($2/1048576)}' /proc/meminfo)
    [ "${used:-0}" -lt 1000000000 ] && [ "$avail" -gt 110 ] && { log "free: vram ${used} B, MemAvailable ${avail} GiB"; return 0; }
    sleep 2; i=$((i + 1))
  done
  log "WARN: memory not free after 360 s (vram $used, avail $avail)"; return 1
}

ds_stop() { log "ds41e stop"; (cd ~/code/ds41e && ./stop.sh --force >/dev/null 2>&1); sleep 2; wait_free; }
ds_start() {   # production, exactly as restart-lan.sh does it
  log "ds41e start (restart-lan.sh)"; local t0=$(date +%s)
  ~/code/ds41e/local/restart-lan.sh | tee -a $H/session.log
  log "ds41e ready after $(( $(date +%s) - t0 )) s"
}

# up_start TAG [engine args...]: a copy of setup's config with extra engine args (env via UPENV="K=V K=V")
up_start() {
  local tag=$1; shift
  local cfg=$H/cfg-$tag.json
  python3 - "$BASECFG" "$cfg" "$tag" "$UPENV" "$@" <<'EOF'
import json, sys
src, dst, tag, env = sys.argv[1:5]
extra = sys.argv[5:]
c = json.load(open(src))
args = c["args"]
# an extra flag replaces the same flag in the base args
i = 0
while i < len(extra):
    f = extra[i]; v = extra[i + 1] if i + 1 < len(extra) and not extra[i + 1].startswith("--") else None
    if f in args:
        j = args.index(f)
        if v is not None and j + 1 < len(args) and not args[j + 1].startswith("--"):
            args[j + 1] = v
    else:
        args += [f] + ([v] if v is not None else [])
    i += 2 if v is not None else 1
c["args"] = args
c["log"] = c["log"].replace(".log", f"-{tag}.log")
if env.strip():
    c["env"] = dict(kv.split("=", 1) for kv in env.split())
json.dump(c, open(dst, "w"), indent=1)
print("engine args:", " ".join(args), "env:", c.get("env"))
EOF
  log "upstream start $tag: $(python3 -c "import json;c=json.load(open('$cfg'));print(' '.join(c['args'][2:]), c.get('env',''))")"
  local t0=$(date +%s)
  ( for fd in $(ls /proc/self/fd); do [ "$fd" -gt 2 ] && eval "exec $fd>&-" 2>/dev/null; done
    cd $UP && setsid nohup $UP/.venv/bin/python $UP/serve/server.py --engine strata --config $cfg --port 8160 \
      > $H/server-$tag.log 2>&1 < /dev/null & )
  local i=0
  until [ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8160/v1/models)" = 200 ]; do
    sleep 3; i=$((i + 1))
    if ! pgrep -f "[s]trata-up/serve/server.py" >/dev/null; then log "upstream server died"; tail -20 $H/server-$tag.log | tee -a $H/session.log; return 1; fi
    [ $i -gt 1200 ] && { log "upstream not ready after 60 min"; return 1; }
  done
  # /v1/models can answer before the engine is loaded: wait for a real answer
  until curl -s -m 1800 http://127.0.0.1:8160/v1/chat/completions -H 'Content-Type: application/json' \
      -d '{"model":"x","messages":[{"role":"user","content":"Say OK."}],"max_tokens":4,"chat_template_kwargs":{"enable_thinking":false}}' \
      | grep -q '"choices"'; do
    sleep 5; pgrep -f "[s]trata-up/serve/server.py" >/dev/null || { log "upstream server died"; tail -20 $H/server-$tag.log | tee -a $H/session.log; return 1; }
  done
  log "upstream $tag ready after $(( $(date +%s) - t0 )) s"
  grep -aE "planned|experts in|ssd|DSpark|dspark|VRAM|vram|RAM store|chunk" $(python3 -c "import json;print(json.load(open('$cfg'))['log'])") 2>/dev/null | head -30 >> $H/session.log
}
up_stop() {
  log "upstream stop"
  pkill -f "[s]trata-up/serve/server.py"; sleep 3
  pkill -f "[s]trata-up/build-dsv41-hip/strata-dsv41"; sleep 2
  pkill -9 -f "[s]trata-up/build-dsv41-hip/strata-dsv41" 2>/dev/null
  wait_free
}
samp_start() { ( for fd in $(ls /proc/self/fd); do [ "$fd" -gt 2 ] && eval "exec $fd>&-" 2>/dev/null; done
                 setsid nohup $H/sampler.sh $H/samp-$1.txt > /dev/null 2>&1 < /dev/null & ); }
samp_stop() { touch $H/STOP-sampler; sleep 3; }
CL() { ~/code/ds41e/.venv/bin/python $H/h2h_client.py "$@"; }
DSURL=http://127.0.0.1:8150; DSKEY="--key-file ~/.config/ds41e/api-key"
UPURL=http://127.0.0.1:8160
