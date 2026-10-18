#!/bin/bash
# strace -T sweep: 3 variants x N = 20 50 1000, both frameworks (18 arms).
set -u
BASE_TAG="${BASE_TAG:-$(date -u +%Y%m%dT%H%M%SZ)}"
NS="${NS:-20 50 1000}"
VARIANTS="${VARIANTS:-count A B}"
OUT="${OUT:-/root/rebenc-strace-T}"
GAP="${GAP:-60}"
T="${T:-0.5}"
mkdir -p "$OUT"
echo "[SWEEP START] BASE_TAG=$BASE_TAG host=$(hostname) NS='$NS' VARIANTS='$VARIANTS' $(date -Is)"
for v in $VARIANTS; do for n in $NS; do
  echo "[SWEEP VARIANT=$v N=$n] $(date -Is)"
  VARIANT="$v" N="$n" OUT="$OUT" GAP="$GAP" T="$T" TAG="${BASE_TAG}-${v}-N${n}" \
      bash /root/experiment/scripts/rebenc_straceT.sh
done; done
echo "[SWEEP DONE] BASE_TAG=$BASE_TAG $(date -Is)"
touch "$OUT/ALLDONE_$BASE_TAG"
