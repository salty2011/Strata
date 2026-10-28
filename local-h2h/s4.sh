#!/bin/bash
# s4: production candidates. Context 262144, lookup on, slot cap 8 GB, --ssd-cache 120 and 116 (RAM headroom vs speed).
# Each: decode, cold 8K/17K + follow-up, cold 60K, agent E/C, the shared-start test; then a graceful restart (SIGTERM:
# the server sends QUIT, the engine writes its slots) with the same config and E again (the restart cache).
. ~/code/strata-up/local-h2h/lib.sh
OUT=$H/results-s4.jsonl
PY=~/code/ds41e/.venv/bin/python
up_stop_graceful() {
  log "upstream graceful stop (SIGTERM)"
  pkill -TERM -f "[s]trata-up/serve/server.py"
  local i=0
  while pgrep -f "[s]trata-up/serve/server.py|[s]trata-up/build-dsv41-hip/strata-dsv41" >/dev/null && [ $i -lt 60 ]; do sleep 2; i=$((i + 1)); done
  log "stopped after $((i * 2)) s"
  pkill -9 -f "[s]trata-up/serve/server.py|[s]trata-up/build-dsv41-hip/strata-dsv41" 2>/dev/null
  wait_free
}
log "=== s4 start"
ds_stop
for X in 120 116; do
  ENVP="STRATA_DSV41_LOOKUP=12 STRATA_DS4_SLOT_GB=8 STRATA_DS4_SLOT_DIR=$UP/ds4-slots-p$X"
  LG=$UP/strata-deepseek-v4.1-flash-ist-das-2.00bpw-p$X.log
  UPENV="$ENVP" up_start p$X --max-context 262144 --ssd-cache $X
  samp_start p$X
  for m in warm decode prefill prefill60 agent; do CL $UPURL p$X $OUT $m 2>&1 | tee -a $H/session.log; done
  $PY $H/lk_check.py $UPURL $LG $OUT prime 2>&1 | tee -a $H/session.log
  samp_stop
  grep -a "ds4 slots" $LG | tail -3 | tee -a $H/session.log
  up_stop_graceful
  grep -a "ds4 slots" $LG | tail -2 | tee -a $H/session.log
  UPENV="$ENVP" up_start p$X --max-context 262144 --ssd-cache $X
  samp_start p$X-restart
  $PY $H/lk_check.py $UPURL $LG $OUT restart 2>&1 | tee -a $H/session.log
  samp_stop
  up_stop_graceful
done
ds_start
log "=== s4 end"
