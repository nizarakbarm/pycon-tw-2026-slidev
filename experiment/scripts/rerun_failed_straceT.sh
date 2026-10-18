#!/bin/bash
# Rerun straceT arms that under-delivered, with a longer drain (T=2).
# Scans a straceT results dir for <variant>_<impl>_N<n>_<TAG>.prog.log whose
# [SUMMARY] != n+1, and re-runs exactly those arms.
#
# Usage:  bash /root/experiment/scripts/rerun_failed_straceT.sh <results_dir>
set -u
D="${1:-/root/experiment/results/straceT}"
NEWTAG="$(date -u +%Y%m%dT%H%M%SZ)rerun"
T="${T:-2}"            # longer drain for strace
FOUND=0

for g in "$D"/*.prog.log; do
  [ -f "$g" ] || continue
  b=$(basename "$g")
  n=$(echo "$b" | sed -n "s/.*N\([0-9]*\)_2026.*/\1/p")
  v=$(echo "$b" | sed -n "s/trace_execve_\([a-z_0-9]*\)_\(bcc\|pbpf\)_.*/\1/p")
  s=$(grep -a '\[SUMMARY\]' "$g" 2>/dev/null | sed -n 's/.*map: *//p')
  [ -z "$s" ] && { echo "[SKIP] $b -- no SUMMARY (incomplete)"; continue; }
  if [ "$s" != "$((n+1))" ]; then
    case "$v" in
      map1_count) VAR=count ;;
      ablA_empty) VAR=A ;;
      ablB_print_const) VAR=B ;;
      *) echo "[SKIP] cannot map variant '$v'"; continue ;;
    esac
    FOUND=$((FOUND+1))
    echo "[RERUN] $v/$b  got=$s want=$((n+1))  -> VAR=$VAR N=$n T=$T"
    VAR="$VAR" N="$n" OUT="$D" T="$T" TAG="${NEWTAG}-${VAR}-N${n}" bash /root/experiment/scripts/rebenc_straceT.sh
  fi
done

echo "[RERUN DONE] $FOUND arm(s) re-run with T=$T, tag suffix $NEWTAG"
