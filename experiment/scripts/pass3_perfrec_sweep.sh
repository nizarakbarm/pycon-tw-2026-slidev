#!/bin/bash
# Pass 3 driver: perf record, VARIANTS x NS. 2M last.
set -u
BASE_TAG="${BASE_TAG:-$(date -u +%Y%m%dT%H%M%SZ)}"
SMALL_NS="${SMALL_NS:-20 50 100 1000 2000}"
BIG_NS="${BIG_NS:-2000000}"
VARIANTS="${VARIANTS:-count A B}"
OUT="${OUT:-/root/experiment/results/perfrecord}"
GAP="${GAP:-60}"
T="${T:-0.5}"
FREQ="${FREQ:-199}"
mkdir -p "$OUT"
echo "[PASS3 START] BASE_TAG=$BASE_TAG host=$(hostname) variants='$VARIANTS' small='$SMALL_NS' big='$BIG_NS' freq=$FREQ T=$T $(date -Is)"
run() { echo "[PASS3 VAR=$1 N=$2] $(date -Is)"
  VAR="$1" N="$2" OUT="$OUT" GAP="$GAP" T="$T" FREQ="$FREQ" TAG="${BASE_TAG}-${1}-N${2}" bash /root/experiment/scripts/rebenc_perfrec.sh; }
for v in $VARIANTS; do for n in $SMALL_NS; do run "$v" "$n"; done; done
for v in $VARIANTS; do for n in $BIG_NS;   do run "$v" "$n"; done; done
echo "[PASS3 DONE] BASE_TAG=$BASE_TAG $(date -Is)"
touch "$OUT/ALLDONE_$BASE_TAG"
