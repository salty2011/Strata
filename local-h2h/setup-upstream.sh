#!/bin/bash
# Upstream setup against the files already on disk (no model download): the 2.00 set from the ds41e folder, the
# shared drafter/meta/mmproj in /srv/models/strata-up/deepseek-v4.1-flash-shared. No GPU smoke here (ds41e holds the
# GPU); smoke.py runs later under the lock.
cd ~/code/strata-up
export STRATA_DSV41_EXE=$PWD/build-dsv41-hip/strata-dsv41 STRATA_DSV41_NO_SMOKE=1
./setup.sh --family deepseek41 --model IST-DAS-2.00bpw --models-dir /srv/models/strata-up \
  --data-dir /srv/models/strata-up/data --gguf-dir /srv/models/ds41e/rco-iq2xxs \
  --context 65536 --vision no --port 8160 --no-start --yes --no-browser "$@"
