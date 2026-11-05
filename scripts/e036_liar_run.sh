#!/bin/bash
# E036 part c4, run from the control box: orchestrates the lying-peer cases. Expectations are in scripts/e036_liar_case.sh.
set -u
W=/home/optimizer/work; S=$W/research/scripts; E=$W/monero-fcmp-e036/build/beta31-e036/bin/monerod; F=$W/monero-fcmp-idle/build/beta31-idle/bin/monerod
LIAR=192.168.1.81:28180; H=192.168.1.22:28080; SECS=600
node() { ssh -n box81 "$W/e036_liar_node.sh $1"; }
case_() { ssh -n hydrogen "$S/e036_liar_case.sh $*"; ssh -n box81 "for p in 28181; do curl -s -m 5 http://127.0.0.1:\$p/get_connections | grep -E '\"(address|incoming)\"' | tr -d ' \n'; echo; done" | sed 's/^/  liar connections: /'; }
ssh -n hydrogen "ps -eo comm | grep -qx shadow && echo lanes running || echo no lanes"
node stop
case_ ref $E $SECS $H
node under
case_ under1 $E $SECS $LIAR
case_ under2 $F $SECS $LIAR
case_ under3 $E $SECS $LIAR $H
case_ under4 $F $SECS $LIAR $H
node over
case_ over1 $E $SECS $LIAR
case_ over2 $E $SECS $LIAR $H
node w006
ssh -n hydrogen "echo CHAIN_E036LIAR_COMPLETE >> $W/research-artifacts/e036liar.chain"
echo E036_LIAR_RUN_DONE
