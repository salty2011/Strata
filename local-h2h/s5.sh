#!/bin/bash
# s5: production candidate with the CPU lane's experts read in place (--mmap-experts on, no RAM store): the page cache
# holds them, which the kernel can reclaim, so MemAvailable stays high. Same workload as s4.
. ~/code/strata-up/local-h2h/lib.sh
OUT=$H/results-s4.jsonl
PY=~/code/ds41e/.venv/bin/python
log "=== s5 start"
ds_stop
X=mmap
ENVP="STRATA_DSV41_LOOKUP=12 STRATA_DS4_SLOT_GB=8 STRATA_DS4_SLOT_DIR=$UP/ds4-slots-p$X"
LG=$UP/strata-deepseek-v4.1-flash-ist-das-2.00bpw-p$X.log
UPENV="$ENVP" up_start p$X --max-context 262144 --mmap-experts on --ssd-cache 0
samp_start p$X
for m in warm decode prefill prefill60 agent; do CL $UPURL p$X $OUT $m 2>&1 | tee -a $H/session.log; done
$PY $H/lk_check.py $UPURL $LG $OUT prime 2>&1 | tee -a $H/session.log
# a second pass of the agent tasks (page cache warm by now)
CL $UPURL p$X-2 $OUT agent 2>&1 | tee -a $H/session.log
samp_stop
up_stop
ds_start
log "=== s5 end"
