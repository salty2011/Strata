#!/bin/bash
# s0: first light of upstream (DSpark auto, setup defaults) - decode + prefill, then production back.
. ~/code/strata-up/local-h2h/lib.sh
log "=== s0 start"
ds_stop
if up_start auto; then
  samp_start up-auto-s0
  CL $UPURL up-auto results-s0.jsonl decode 2>&1 | tee -a $H/session.log
  CL $UPURL up-auto results-s0.jsonl prefill 2>&1 | tee -a $H/session.log
  samp_stop
fi
up_stop
ds_start
log "=== s0 end"
