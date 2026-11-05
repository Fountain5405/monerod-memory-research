#!/bin/bash
# E036 part c5, run from the control box after E037: a TEST-ONLY peer that advertises false weights and then does not answer block requests (E036_SILENT, scripts/e036_silent_build.sh). Why: from the code, a span given to such a peer stays scheduled, and after 5-30 s another peer can be asked for it. If the weights were false, that request is oversize on the honest connection. Part c4's liar answered at once and could not show this.
# Each case 600 s from 3,105,401, single runs, not timing runs, one at a time on hydrogen. Expected, fixed before any case ran:
#   s_ref      .22 alone, e036: as c4's ref, about 3,107,800, 0 oversize. Read against this, not c4's ref, since .22 has moved on.
#   s_truth    silent peer with true weights + .22, e036: the control, what any non-answering peer costs today. Progress, 0 oversize, height below s_ref. Spans it holds get double-downloaded from .22.
#   s_under    silent under liar + .22, e036: the question. Oversize errors on the .22 connection (at least 1), .22's connection closing and returning, height below s_truth. How far below is the point: I expect a delay of some minutes, ending when the silent peer's score runs out or heavy blocks get applied (then the estimate gives single-block spans whatever is advertised), and not a permanent stall. A permanent stall (height still under 3,105,441 at 600 s) would be the important result.
#   s_final    silent under liar + .22, final: 0 oversize, height within reach of s_truth. Its cap uses no peer data.
# Connection counts: JSON-RPC get_connections on the victim, every 30 s, now fixed in e036_liar_case.sh. Liar isolation: JSON-RPC get_connections on the liar at mid-run, only hydrogen expected.
# Waits for CHAIN_E037_COMPLETE on hydrogen. Mining on box81 is paused for these cases and restored at the end.
set -u
W=/home/optimizer/work; S=$W/research/scripts; A=$W/research-artifacts; E=$W/monero-fcmp-e036/build/beta31-e036/bin/monerod; F=$W/monero-fcmp-idle/build/beta31-idle/bin/monerod
LIAR=192.168.1.81:28180; H=192.168.1.22:28080; SECS=600
until ssh -n hydrogen "grep -q CHAIN_E037_COMPLETE $A/e037.chain"; do sleep 120; done
node() { ssh -n box81 "$W/e036_liar_node.sh $1"; }
midcheck() { sleep 300; ssh -n box81 "curl -s -m 5 http://127.0.0.1:28181/json_rpc -d '{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"get_connections\"}' | grep -E '\"(address|incoming)\"' | tr -d ' \n'; echo" | sed "s/^/  liar connections at 300 s, $1: /"; }
case_() { midcheck "$1" & ssh -n hydrogen "$S/e036_liar_case.sh $*"; wait; }
ssh -n hydrogen "ps -eo comm | grep -qx shadow && echo lanes running || echo no lanes"
node stop
case_ s_ref $E $SECS $H
node siltruth
case_ s_truth $E $SECS $LIAR $H
node silunder
case_ s_under $E $SECS $LIAR $H
case_ s_final $F $SECS $LIAR $H
node w006
ssh -n hydrogen "echo CHAIN_E036SILENT_COMPLETE >> $A/e036liar.chain"
echo E036_C5_DONE
