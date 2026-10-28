#!/bin/bash
# ab: lookup A/B. 3 rounds; each: ds41e production fresh (restart-lan.sh: its lookup on, its defaults), then upstream
# fresh (setup config + STRATA_DSV41_LOOKUP=12) with plain (strata_tune lookup 0) and lookup alternating in one load.
# Default sampling throughout (ds41e: temp 0.8, top_p 0.95, rep 1.1; upstream: temp 1.0, top_p 1.0).
. ~/code/strata-up/local-h2h/lib.sh
OUT=$H/results-ab.jsonl
DSLOG=~/code/ds41e/local/serve-engine.log
LKLOG=$UP/strata-deepseek-v4.1-flash-ist-das-2.00bpw-ab.log
PY=~/code/ds41e/.venv/bin/python
log "=== ab start"
for r in 1 2 3; do
  ds_stop; ds_start
  samp_start ab-ds41e-r$r
  CL $DSURL ds41e $OUT warm $DSKEY 2>&1 | tee -a $H/session.log
  $PY $H/lk_check.py $DSURL $DSLOG $OUT single --round $r --key-file ~/.config/ds41e/api-key 2>&1 | tee -a $H/session.log
  samp_stop
  ds_stop
  UPENV="STRATA_DSV41_LOOKUP=12 STRATA_DS4_SLOT_DIR=$UP/ds4-slots-ab" up_start ab
  samp_start ab-up-r$r
  CL $UPURL up $OUT warm 2>&1 | tee -a $H/session.log
  $PY $H/lk_check.py $UPURL $LKLOG $OUT ab --round $r 2>&1 | tee -a $H/session.log
  samp_stop
  up_stop
done
ds_start
log "=== ab end"
