#!/bin/bash
# Launcher for pass 3 (perf record), gated harness.
set -u
D=/root/experiment/results/perfrecord
T=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$D"
env BASE_TAG="$T" \
    SMALL_NS="20 50 100 1000 2000" BIG_NS="2000000" VARIANTS="count A B" \
    OUT="$D" GAP=60 T=1 FREQ=199 \
    setsid nohup bash /root/experiment/scripts/pass3_perfrec_sweep.sh > "$D/sweep_$T.log" 2>&1 < /dev/null &
sleep 12
echo "TAG=$T"
echo "== dir:"; ls -la "$D" | sed 's/^/  /'
echo "== running:"; pgrep -af 'pass3_perfrec|rebenc_perfrec|perf record' | grep -v pgrep | sed 's/^/  /' || echo "  NOTHING"
echo "== log head:"; head -8 "$D/sweep_$T.log" 2>/dev/null | sed 's/^/  /'
