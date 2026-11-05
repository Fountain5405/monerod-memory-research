#!/bin/bash
# E036, box81: a TEST-ONLY peer build that misreports block weights when E036_LIE is set. Never joins a network: run only with --hide-my-port, an unadvertised port and no outbound peers, for one LAN test node.
set -u
W0=$HOME/work; A=$W0/research-artifacts; C=$A/e036liar.chain
T=$W0/monero-fcmp-e036-liar; BD=$T/build/liar
echo "liar start $(date -Is)" > $C
source ~/.cargo/env; export CCACHE_BASEDIR=$W0
rsync -a --exclude build $W0/monero-fcmp/ $T/
cd $T || exit 1
python3 - <<'PYEOF'
import pathlib
p=pathlib.Path('src/cryptonote_protocol/cryptonote_protocol_handler.inl'); s=p.read_text()
old='''    MLOG_P2P_MESSAGE("-->>NOTIFY_RESPONSE_CHAIN_ENTRY: m_start_height="'''
assert s.count(old)==1
new='''    // E036 TEST ONLY: misreport block weights for a lying-peer test.
    if (const char *lie = std::getenv("E036_LIE"))
    {
      const bool over = std::string(lie) == "over";
      for (uint64_t &w : r.m_block_weights)
        w = over ? 200000000 : 1;
    }
'''+old
p.write_text(s.replace(old,new,1))
PYEOF
git diff --stat >> $C
mkdir -p $BD; cd $BD
{ cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DARCH=native -DBUILD_TESTS=OFF -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache ../.. && nice -n 10 ninja -j6 daemon && echo BUILD_OK || echo BUILD_FAILED; } > $A/e036liar.build.log 2>&1
echo "build $(tail -1 $A/e036liar.build.log) $(date -Is)" >> $C
sha256sum $BD/bin/monerod >> $C
echo CHAIN_E036LIAR_COMPLETE >> $C
