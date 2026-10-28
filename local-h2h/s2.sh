#!/bin/bash
# s2: upstream knobs, each a fresh start from setup's config (--dspark auto) plus one change; warm-up, decode, prefill.
. ~/code/strata-up/local-h2h/lib.sh
OUT=$H/results-s2.jsonl
log "=== s2 start"
ds_stop
run_knob() {   # tag, engine args...
  local tag=$1; shift
  if up_start $tag "$@"; then
    samp_start $tag
    for m in warm decode prefill; do CL $UPURL $tag $OUT $m 2>&1 | tee -a $H/session.log; done
    samp_stop
  fi
  up_stop
}
run_knob k-chunk8192 --prefill-chunk 8192
run_knob k-chunk16384 --prefill-chunk 16384
run_knob k-experts5 --experts 5
run_knob k-threads24 --cpu-threads 24
run_knob k-ssd108 --ssd-cache 108
ds_start
log "=== s2 end"
