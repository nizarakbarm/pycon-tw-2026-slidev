#!/bin/bash
# Wait for pass 3 to finish, then run the full three-pass verification.
# Detached: survives the ssh session. Writes one report file.
set -u
D=/root/experiment/results/perfrecord
R=/root/pass3_final_report.txt
exec > "$R" 2>&1

echo "[WATCH] started $(date -Is) — waiting for pass3_perfrec_sweep to exit"

# wait for the sweep process to disappear (not for a marker file: the marker name
# changed between runs, the process name did not).
# Anchor the pattern: a bare 'pgrep -f pass3_perfrec_sweep' also matches any ssh
# command line that merely mentions the name -- including the one that starts this
# watcher -- so the loop would never exit.
while pgrep -f 'bash .*pass3_perfrec_sweep\.sh' >/dev/null 2>&1; do sleep 30; done

echo "[WATCH] sweep gone at $(date -Is)"
sleep 20   # let the last flamegraph finish flushing

echo
echo "================ PASS 3 ARM AUDIT ================"
tot=0; ok=0; bad=0; miss=0
for g in "$D"/perfrec_*.log; do
  [ -f "$g" ] || continue
  tot=$((tot+1))
  n=$(basename "$g" | sed -n 's/.*N\([0-9]*\)_2026.*/\1/p')
  s=$(grep -a '\[SUMMARY\]' "$g" 2>/dev/null | sed -n 's/.*map: *//p')
  if [ -z "$s" ]; then
    echo "  MISSING-SUMMARY  $(basename "$g")"; miss=$((miss+1))
  elif [ "$s" = "$((n+1))" ]; then
    ok=$((ok+1))
  else
    echo "  FAIL  N=$n got=$s want=$((n+1))  $(basename "$g")"; bad=$((bad+1))
  fi
done
echo "  --> arms ok=$ok fail=$bad missing_summary=$miss  (total $tot)"

echo
echo "================ ARTEFACTS ================"
printf "  data=%s folded=%s svg=%s  (expect 36 each)\n" \
  "$(ls "$D"/*.data 2>/dev/null | wc -l)" \
  "$(ls "$D"/*.folded 2>/dev/null | wc -l)" \
  "$(ls "$D"/*.svg 2>/dev/null | wc -l)"
echo "  2M arms with log+data+folded+svg:"
for n in 2000000; do
  for f in "$D"/*N${n}*.log; do
    [ -f "$f" ] || continue
    b="${f%.log}"
    printf "    %s  data=%s folded=%s svg=%s\n" "$(basename "$b" | sed 's/perfrec_execve_//;s/_2026.*//')" \
      "$([ -s "$b.data" ] && echo y || echo N)" \
      "$([ -s "$b.folded" ] && echo y || echo N)" \
      "$([ -s "$b.svg" ] && echo y || echo N)"
  done
done

echo
echo "================ GATE WARNINGS ================"
w=$(grep -c 'never reported polling' "$D"/sweep_*.log 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
echo "  arms where the gate timed out: $w"
echo "  (expected for pythonbpf abl_A / abl_B: those two programs lack flush=True on"
echo "   the ready line, so it stays in the 8 KB stdout buffer. Fallback fires at 60 s"
echo "   and delivery is unaffected -- confirm via the ARM AUDIT above.)"

echo
echo "================ THREE-PASS VERIFY ================"
bash /root/experiment/scripts/verify_passes.sh 2>&1 || echo "  verify_passes.sh exited nonzero"

echo
echo "[WATCH] done $(date -Is)"
