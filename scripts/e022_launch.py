#!/usr/bin/env python3
import pathlib, re, datetime, gzip, shutil, csv, collections
R = pathlib.Path.home() / "work/research"; A = pathlib.Path.home() / "work/research-artifacts"
now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M"); hhmm = now.split()[1]
e = R / "evidence/E022"; e.mkdir(parents=True, exist_ok=True)
with open(A / "e022scan/chain_inputs.csv", "rb") as i, gzip.open(e / "chain_inputs.csv.gz", "wb") as o: shutil.copyfileobj(i, o)
shutil.copy(A / "e022scan.chain", e / "e022scan.chain")
p = R / "STATE.md"; s = p.read_text()
s = s.replace(re.search(r"Last updated: .*", s).group(0), f"Last updated: {now}", 1)
old = "NEXT (node): E022 16-input threshold sweep. The two existing windows cannot discriminate (128-input and 1-2-input txs trip every threshold or none), so E022a scans the input-count distribution first (scripts/run_e022scan.sh, RUNNING since 00:59, offline node on the synced snapshot, marker e022scan.chain ends E022SCAN_COMPLETE, output e022scan/chain_inputs.csv). If no mid-size stretch exists, the sweep is not worth running on this chain: record that and move on. Then: optional perf profile of e020's +28%."
assert s.count(old) == 1
s = s.replace(old, f"**E022 RUNNING (hydrogen, started {hhmm}, scripts/run_e022.sh, marker ~/work/research-artifacts/e022.chain ends CHAIN_E022_COMPLETE, ETA ~1.5 h): HEAVY_PROOF_MIN_INPUTS 8 / 16 / 32 on the full series, window 3,106,060 -> 3,106,112, 5 rounds.** The E022a scan (done 01:19, evidence/E022/chain_inputs.csv.gz) found only 104 of 43,270 blocks are threshold-sensitive (largest tx 8-31 inputs), and 42 of them are contiguous at 3,106,069-3,106,110 (37 with 8 inputs, 5 with 16). Decision rule fixed in the script header. t32 differs from t16 on only those 5 blocks, so its reading is weak. Then: experiments/E022-threshold-sweep, FINDINGS, SUMMARY caveat. After that: optional perf profile of e020's +28%.", 1)
p.write_text(s)
with (R / "JOURNAL.md").open("a") as f:
    f.write(f"""
## 2026-11-04 {hhmm} E022a scan done, E022 threshold sweep launched
- Scan of 3,080,000-3,123,269 on our offline node: 762,594 txs, 99.6% with 1-2 inputs (759,840), 1,339 with 3-15, 148 with 16-63, 1,267 with 64 or more. Blocks by largest tx: 34,507 empty, 8,535 at 1-2, 43 at 3-7, 83 at 8-15, 21 at 16-31, 17 at 32-63, 64 at 64+. So only 104 of 43,270 blocks (0.24%) change behaviour for a threshold of 8, 16 or 32. Stressnet's mix is synthetic; it says nothing about how often mid-size proofs would occur on mainnet.
- Contiguous stretch 3,106,069-3,106,110 (37 blocks at 8 inputs, 5 at 16) makes a targeted sweep cheap, with no new snapshot (pop_to from h3106400). t8 / t16 / t32 on the idle tree, 5 rounds because wall resolution is 2 s on a short window. Decision rule written into run_e022.sh before the data.
""")
print("ok", now)
