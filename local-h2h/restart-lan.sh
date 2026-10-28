#!/bin/sh
# Restart the upstream LAN server: stop it (SIGTERM: the server sends QUIT, the engine writes its conversation slots),
# stop ds41e too if it runs, wait for VRAM < 1 GB and MemAvailable > 110 GB, start run-lan.sh with inherited fds closed,
# wait until a keyed request answers. Use under: flock ~/bigrig-gpu.lock ~/code/strata-up/local-h2h/restart-lan.sh
H="$(cd "$(dirname "$0")" && pwd)"
LOG="$H/prod-server.log"
stop_upstream() {
    pkill -TERM -f "[s]trata-up/serve/server.py" 2>/dev/null || return 0
    i=0
    while pgrep -f "[s]trata-up/serve/server.py|[s]trata-up/build-dsv41-hip/strata-dsv41" >/dev/null && [ $i -lt 60 ]; do
        sleep 2; i=$((i + 1))
    done
    pkill -KILL -f "[s]trata-up/serve/server.py|[s]trata-up/build-dsv41-hip/strata-dsv41" 2>/dev/null
    return 0
}
stop_upstream
if pgrep -f "[s]erve_ds41.py" >/dev/null; then (cd "$HOME/code/ds41e" && ./stop.sh --force >/dev/null 2>&1); fi
i=0
while [ $i -lt 180 ]; do
    used=$(rocm-smi --showmeminfo vram 2>/dev/null | awk "/Used Memory/ {print \$NF; exit}")
    avail=$(awk "/MemAvailable/ {print int(\$2/1048576)}" /proc/meminfo)
    [ "${used:-0}" -lt 1000000000 ] && [ "$avail" -gt 110 ] && break
    sleep 2; i=$((i + 1))
done
[ $i -ge 180 ] && echo "WARN: memory not free after 360 s (vram $used B, MemAvailable $avail GiB); starting anyway"
# close inherited fds > 2 first: under `flock ~/bigrig-gpu.lock` the server would otherwise hold the lock while it runs
( for fd in $(ls /proc/self/fd); do [ "$fd" -gt 2 ] && eval "exec $fd>&-" 2>/dev/null; done
  setsid nohup "$H/run-lan.sh" > "$LOG" 2>&1 < /dev/null & )
KEY=$(cat "$HOME/.config/ds41e/api-key")
t0=$(date +%s)
while :; do
    if ! pgrep -f "[s]trata-up/serve/server.py" >/dev/null; then echo "upstream server died:"; tail -20 "$LOG"; exit 1; fi
    out=$(curl -s -m 600 http://127.0.0.1:8150/v1/chat/completions -H "Authorization: Bearer $KEY" \
        -H 'Content-Type: application/json' \
        -d '{"model":"local","messages":[{"role":"user","content":"Say OK."}],"max_tokens":4,"reasoning_effort":"none"}' 2>/dev/null)
    echo "$out" | grep -q '"choices"' && break
    [ $(( $(date +%s) - t0 )) -gt 1800 ] && { echo "upstream not ready after 30 min"; exit 1; }
    sleep 5
done
echo "ready: upstream strata-dsv41 on 0.0.0.0:8150 after $(( $(date +%s) - t0 )) s"
