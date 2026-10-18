#!/bin/bash
# Keep ONE valid prog.log per (variant,impl,N) in a straceT results dir; move the
# older duplicates to _dup/. Only valid ones (SUMMARY==N+1) participate --
# anything invalid is left for quarantine_failed.sh.
# Rationale: the trigger gate was added mid-run, so N=50 got re-run more than once
# and produced multiple valid copies of the same arm.
set -u
D="${1:-/root/experiment/results/straceT}"
Q="$D/_dup"
mkdir -p "$Q"
moved=0

# group key -> newest file; use mtime
for key in $(ls "$D"/*.prog.log 2>/dev/null | sed 's|.*/trace_execve_||;s|\.prog\.log||' | sed 's/_N\([0-9]*\)_.*/|N\1/' | sort -u); do
  v="${key%|*}"; nk="${key#*|}"; n="${nk#N}"
  # files for this variant+N
  matches=$(ls "$D"/*"${v}"_N"${n}"_*.prog.log 2>/dev/null)
  [ -z "$matches" ] && continue
  cnt=$(printf '%s\n' $matches | wc -l)
  [ "$cnt" -le 1 ] && continue
  # newest first
  keep=$(printf '%s\n' $matches | xargs -r ls -t | head -1)
  for g in $matches; do
    [ "$g" = "$keep" ] && continue
    base="${g%.prog.log}"
    echo "[DEDUPE] keep $(basename "$keep" .prog.log)"
    echo "         move $(basename "$g" .prog.log)"
    mv -f "$g" "$Q/" 2>/dev/null
    [ -f "$base.T.txt" ]    && mv -f "$base.T.txt"    "$Q/" 2>/dev/null
    [ -f "$base.rank.txt" ] && mv -f "$base.rank.txt" "$Q/" 2>/dev/null
    moved=$((moved+1))
  done
done

echo "[DEDUPE DONE] moved=$moved -> $Q"
echo "  prog.logs remaining: $(ls "$D"/*.prog.log 2>/dev/null | wc -l)"
