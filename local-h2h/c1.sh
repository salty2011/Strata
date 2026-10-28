#!/bin/bash
# c1: correctness of the lookup-draft port (local-lookup branch). ds41e stops, upstream starts with lookup on by
# default (K 12, gate 3, n-gram 4; a request's strata_tune lookup 0 is the plain arm), own slot folder; then ds41e back.
. ~/code/strata-up/local-h2h/lib.sh
OUT=$H/results-lk.jsonl
LKLOG=$UP/strata-deepseek-v4.1-flash-ist-das-2.00bpw-lk.log
log "=== c1 start (lookup port correctness)"
ds_stop
UPENV="STRATA_DSV41_LOOKUP=12 STRATA_DSV41_LOOKUP_GATE=3 STRATA_DSV41_LOOKUP_NGRAM=4 STRATA_DS4_SLOT_DIR=$UP/ds4-slots-lk" up_start lk
grep -a "lookup drafts on" $LKLOG | tail -1 | tee -a $H/session.log
for mode in t0 sampled edge; do
  log "lk_check $mode"
  ~/code/ds41e/.venv/bin/python $H/lk_check.py $UPURL $LKLOG $OUT $mode 2>&1 | tee -a $H/session.log
done
up_stop
ds_start
log "=== c1 end"
