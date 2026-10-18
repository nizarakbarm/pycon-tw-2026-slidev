#!/bin/bash
# Launcher for pass 2 (strace -T).
set -u
D=/root/experiment/results/straceT
T=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$D"
env BASE_TAG="$T" \
    NS="20 50 100 1000 2000 2000000" VARIANTS="count A B" \
    OUT="$D" GAP=60 T=0.5 \
    setsid nohup bash /root/experiment/scripts/rebenc_straceT_sweep.sh > "$D/sweep_$T.log" 2>&1 < /dev/null &
sleep 10
echo "TAG=$T"
echo "== dir:"; ls -la "$D" | sed 's/^/  /'
echo "== running:"; pgrep -af 'rebenc_straceT|gen_exec' | grep -v pgrep | sed 's/^/  /' || echo "  NOTHING"
echo "== log head:"; head -8 "$D/sweep_$T.log" 2>/dev/null | sed 's/^/  /'
