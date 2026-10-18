#!/bin/bash
# Move any straceT arm whose [SUMMARY] != N+1 into <dir>/_failed/, together with
# its .T.txt and .rank.txt, so the published tree contains only valid arms.
# Idempotent: a second run finds nothing to move.
set -u
D="${1:-/root/experiment/results/straceT}"
Q="$D/_failed"
mkdir -p "$Q"
moved=0

for g in "$D"/*.prog.log; do
  [ -f "$g" ] || continue
  b=$(basename "$g")
  n=$(echo "$b" | sed -n 's/.*N\([0-9]*\)_2026.*/\1/p')
  s=$(grep -a '\[SUMMARY\]' "$g" 2>/dev/null | sed -n 's/.*map: *//p')
  [ -z "$n" ] && continue
  if [ -z "$s" ] || [ "$s" != "$((n+1))" ]; then
    base="${g%.prog.log}"
    echo "[QUARANTINE] $b  summary=${s:-none} expect=$((n+1))"
    mv -f "$g" "$Q/" 2>/dev/null
    [ -f "$base.T.txt" ]    && mv -f "$base.T.txt"    "$Q/" 2>/dev/null
    [ -f "$base.rank.txt" ] && mv -f "$base.rank.txt" "$Q/" 2>/dev/null
    moved=$((moved+1))
  fi
done

echo "[QUARANTINE DONE] moved=$moved  -> $Q"
ls "$Q" | wc -l | sed 's/^/  files now in _failed: /'
