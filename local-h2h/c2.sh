#!/bin/bash
# c2: temperature-0 determinism, plain vs lookup, with the expert cache as setup has it and with it frozen
. ~/code/strata-up/local-h2h/lib.sh
OUT=$H/results-lk.jsonl
log "=== c2 start (determinism)"
ds_stop
ENVLK="STRATA_DSV41_LOOKUP=12 STRATA_DS4_SLOT_DIR=$UP/ds4-slots-lk"
UPENV="$ENVLK" up_start lk
~/code/ds41e/.venv/bin/python $H/lk_check.py $UPURL $UP/strata-deepseek-v4.1-flash-ist-das-2.00bpw-lk.log $OUT det 2>&1 | tee -a $H/session.log
up_stop
UPENV="$ENVLK" up_start lkfrozen --no-expert-cache --profile-readonly
~/code/ds41e/.venv/bin/python $H/lk_check.py $UPURL $UP/strata-deepseek-v4.1-flash-ist-das-2.00bpw-lkfrozen.log $OUT det 2>&1 | tee -a $H/session.log
up_stop
ds_start
log "=== c2 end"
