#!/bin/bash
# Launcher so quoting survives the ssh hop.
set -u
D=/root/experiment/results/unprofiled
T=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$D"
env BASE_TAG="$T" \
    SMALL_NS="20 50 100 1000 2000" BIG_NS="2000000" VARIANTS="count A B" \
    OUT="$D" GAP=60 T=0.5 \
    setsid nohup bash /root/experiment/scripts/pass1_unprof_sweep.sh > "$D/sweep_$T.log" 2>&1 < /dev/null &
sleep 10
echo "TAG=$T"
echo "== dir:"; ls -la "$D" | sed 's/^/  /'
echo "== running:"; pgrep -af 'pass1_unprof|rebenc_unprof|gen_exec' | grep -v pgrep | sed 's/^/  /' || echo "  NOTHING"
echo "== log head:"; head -10 "$D/sweep_$T.log" 2>/dev/null | sed 's/^/  /'
