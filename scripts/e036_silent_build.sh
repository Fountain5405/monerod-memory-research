#!/bin/bash
# E036 part c5, box81: adds E036_SILENT to the TEST-ONLY liar tree (scripts/e036_liar_build.sh). With it set the node takes block requests and never answers them, keeping its connection and the span it was given. E036_LIE works as before. Never joins a network: same flags as part c4.
set -u
W0=$HOME/work; A=$W0/research-artifacts; C=$A/e036silent.chain
T=$W0/monero-fcmp-e036-liar; BD=$T/build/liar
echo "silent start $(date -Is)" > $C
sha256sum $BD/bin/monerod >> $C
source ~/.cargo/env; export CCACHE_BASEDIR=$W0
cd $T || exit 1
python3 - <<'PYEOF'
import pathlib
p=pathlib.Path('src/cryptonote_protocol/cryptonote_protocol_handler.inl'); s=p.read_text()
old='''    MLOG_P2P_MESSAGE("Received NOTIFY_REQUEST_GET_OBJECTS (" << arg.blocks.size() << " blocks)");'''
assert s.count(old)==1
new=old+'''
    // E036 TEST ONLY: never answer block requests.
    if (std::getenv("E036_SILENT"))
      return 1;'''
p.write_text(s.replace(old,new,1))
PYEOF
git diff --stat >> $C
cd $BD
{ nice -n 10 ninja -j6 daemon && echo BUILD_OK || echo BUILD_FAILED; } > $A/e036silent.build.log 2>&1
echo "build $(tail -1 $A/e036silent.build.log) $(date -Is)" >> $C
sha256sum $BD/bin/monerod >> $C
echo CHAIN_E036SILENT_BUILT >> $C
