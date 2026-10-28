#!/bin/bash
# s1: the main matrix. 3 rounds; each round starts every arm fresh: A = ds41e production (restart-lan.sh, lookup
# drafts on), B = upstream as setup wrote it (--dspark auto, which does not load the drafter here), C = upstream with
# --dspark on --dspark-conf 0.65 (the 4090 report's setting). Round 1 also runs decode, prefill (8K/17K/follow-up)
# and the 60K prefill; round 2 repeats decode. Every round: warm-up, then the agent edit (E) and review (C) tasks.
. ~/code/strata-up/local-h2h/lib.sh
OUT=$H/results-s1.jsonl
DSLOG=~/code/ds41e/local/serve-engine.log
arm_tests() {   # $1 url  $2 tag  $3 round  $4 key-args
  local url=$1 tag=$2 r=$3 key=$4
  samp_start $tag-r$r
  CL $url $tag $OUT warm $key 2>&1 | tee -a $H/session.log
  if [ $r = 1 ]; then
    CL $url $tag $OUT decode $key 2>&1 | tee -a $H/session.log
    CL $url $tag $OUT prefill $key 2>&1 | tee -a $H/session.log
    CL $url $tag $OUT prefill60 $key 2>&1 | tee -a $H/session.log
  fi
  [ $r = 2 ] && CL $url $tag $OUT decode $key 2>&1 | tee -a $H/session.log
  CL $url $tag-r$r $OUT agent $key 2>&1 | tee -a $H/session.log
  samp_stop
}
log "=== s1 start"
for r in 1 2 3; do
  # A: ds41e (production is running at the start of round 1)
  if [ $r != 1 ]; then ds_start; else ds_stop; ds_start; fi
  off=$(stat -c %s $DSLOG)
  arm_tests $DSURL ds41e $r "$DSKEY"
  tail -c +$((off + 1)) $DSLOG > $H/englog-ds41e-r$r.log
  ds_stop
  # B: upstream, setup defaults
  up_start auto-r$r && arm_tests $UPURL up-auto $r ""
  up_stop
  # C: upstream, DSpark forced on
  up_start on-r$r --dspark on --dspark-conf 0.65 && arm_tests $UPURL up-on $r ""
  up_stop
done
ds_start
log "=== s1 end"
