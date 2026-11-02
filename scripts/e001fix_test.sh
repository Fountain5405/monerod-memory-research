#!/bin/bash
# E001-fix test: rewind to 3,105,401, then run repro_e001.sh v2 with the PATCHED monerod.
# Completion marker in ~/work/research-artifacts/E001/fixtest.done: E001FIX_COMPLETE
set -u
SECS=${1:-90}
BASE=/home/optimizer/work/monero-fcmp/build/beta31/bin/monerod
FIX=/home/optimizer/work/monero-fcmp-e001fix/build/beta31-e001fix/bin/monerod
DD=/home/optimizer/work/chains/stressnet
D=~/work/research-artifacts/E001
echo "e001fix_test start $(date -Is) secs=$SECS" > $D/fixtest.done
~/work/research/scripts/pop_to.sh $BASE $DD 3105401 $D/fixtest_pop.log
tail -1 $D/fixtest_pop.log >> $D/fixtest.done
if tail -1 $D/fixtest_pop.log | grep -q "RESULT OK"; then
  ~/work/research/scripts/repro_e001.sh $FIX $DD $D/repro_fix $SECS
  cat $D/repro_fix/summary.txt >> $D/fixtest.done
else
  echo "pop failed; test not run" >> $D/fixtest.done
fi
echo E001FIX_COMPLETE >> $D/fixtest.done
