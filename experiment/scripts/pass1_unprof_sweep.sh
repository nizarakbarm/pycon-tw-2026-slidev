#!/bin/bash
# Pass 1 driver: un-profiled, VARIANTS x NS. 2M last so partial results are usable.
set -u
BASE_TAG="${BASE_TAG:-$(date -u +%Y%m%dT%H%M%SZ)}"
SMALL_NS="${SMALL_NS:-20 50 100 1000 2000}"
BIG_NS="${BIG_NS:-2000000}"
VARIANTS="${VARIANTS:-count A B}"
OUT="${OUT:-/root/experiment/results/unprofiled}"
GAP="${GAP:-60}"
T="${T:-0.5}"
mkdir -p "$OUT"
echo "[PASS1 START] BASE_TAG=$BASE_TAG host=$(hostname) variants='$VARIANTS' small='$SMALL_NS' big='$BIG_NS' T=$T $(date -Is)"
run() { echo "[PASS1 VAR=$1 N=$2] $(date -Is)"
  VAR="$1" N="$2" OUT="$OUT" GAP="$GAP" T="$T" TAG="${BASE_TAG}-${1}-N${2}" bash /root/experiment/scripts/rebenc_unprof.sh; }
for v in $VARIANTS; do for n in $SMALL_NS; do run "$v" "$n"; done; done
for v in $VARIANTS; do for n in $BIG_NS;   do run "$v" "$n"; done; done
echo "[PASS1 DONE] BASE_TAG=$BASE_TAG $(date -Is)"
touch "$OUT/ALLDONE_$BASE_TAG"
