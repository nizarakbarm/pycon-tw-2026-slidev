#!/bin/bash
# sys_enter_execve with_map, UN-PROFILED (no strace, no perf record).
# Variant-agnostic: VAR = count | A | B  (canonical + both ablation variants).
# Same mechanism as rebenc_abl2m.sh; output path passed in via OUT so the three
# passes can land in separate trees.
#
# vmnono (nono1) only. Output NOT under /tmp.
set -u
TAG="${TAG:-$(date -u +%Y%m%dT%H%M%SZ)}"
N="${N:-100}"
VAR="${VAR:-count}"
OUT="${OUT:-/root/experiment/results/unprofiled}"
GAP="${GAP:-60}"
T="${T:-0.5}"
mkdir -p "$OUT"

[ "$(hostname)" = nono1 ] || { echo "[HALT] vmnono/nono1 only"; exit 1; }

case "$VAR" in
  count) SUFFIX="map1_count" ;;
  A)     SUFFIX="ablA_empty" ;;
  B)     SUFFIX="ablB_print_const" ;;
  *) echo "[HALT] VAR must be count|A|B"; exit 2 ;;
esac

PY_BCC=/usr/bin/python3
PY_PB=/root/experiment/.venv/bin/python3
case "$VAR" in
  count) PB=/root/experiment/with_map/bcc/sys_enter_execve/map_1_perf_timed_count.py
         PP=/root/experiment/with_map/pythonbpf/sys_enter_execve/map_1_perf_timed_count.py ;;
  A)     PB=/root/experiment/with_map/bcc/sys_enter_execve/abl_A_empty_callback.py
         PP=/root/experiment/with_map/pythonbpf/sys_enter_execve/abl_A_empty_callback.py ;;
  B)     PB=/root/experiment/with_map/bcc/sys_enter_execve/abl_B_print_const.py
         PP=/root/experiment/with_map/pythonbpf/sys_enter_execve/abl_B_print_const.py ;;
esac
TRIG_USER=operator
TRIG_BIN=/usr/local/bin/gen_exec

for p in "$PB" "$PP"; do
  [ -f "$p" ] || { echo "[HALT] missing: $p"; exit 3; }
done

arm() {                    # impl python program pre-sleep
  local impl="$1" py="$2" prog="$3" pre="$4"
  local base="$OUT/unprofiled_execve_${SUFFIX}_${impl}_N${N}_${TAG}"
  local log="$base.log" pid i

  "$py" "$prog" > "$log" 2>&1 &
  pid=$!
  sleep "$pre"

  # GATE: fire the trigger only once the program reports it is polling.
  # A fixed pre-sleep can expire before attach under strace/perf, losing the
  # trigger's whole burst with no [LOST] and no way to recover it by draining longer.
  local ready=0
  for i in $(seq 1 120); do
    grep -qaE 'Starting (to )?poll' "$log" && { ready=1; break; }
    sleep 0.5
  done
  [ "$ready" = 1 ] || echo "    [WARN] program never reported polling within 60s"

  sudo -u "$TRIG_USER" "$TRIG_BIN" "$N"
  sleep "$T"

  kill -INT "$pid" 2>/dev/null || true
  for i in $(seq 1 40); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
  kill -0 "$pid" 2>/dev/null && { echo "    [WARN] child alive; killing"; kill -9 "$pid" 2>/dev/null; sleep 1; }
  grep -q '\[TIMING\] Total CPU' "$log" || echo "    [WARN] teardown missing"

  local sum
  sum=$(grep -a '\[SUMMARY\]' "$log" | sed -n 's/.*Events in map: *\([0-9]*\).*/\1/p')
  echo "[DONE] VAR=$VAR impl=$impl N=$N summary=${sum:-MISSING} (expect $((N+1)))  prog=$(basename "$prog")"
  grep -a '\[TIMING\]\|\[RUSAGE\]\|\[SUMMARY\]\|\[LOST\]' "$log" | sed 's/^/    /'
}

echo "[START] TAG=$TAG host=$(hostname) VAR=$VAR ($SUFFIX) N=$N UN-PROFILED T=${T}s $(date -Is)"
echo "  BCC : $PB  md5=$(md5sum $PB | cut -c1-12)"
echo "  PBPF: $PP  md5=$(md5sum $PP | cut -c1-12)"
echo "--- arm 1: BCC (pre-sleep 2s) ---"
arm bcc  "$PY_BCC" "$PB" 2
echo "[GAP] idle ${GAP}s"; sleep "$GAP"
echo "--- arm 2: PBPF (pre-sleep 1s) ---"
arm pbpf "$PY_PB"  "$PP"  1
echo "[ALL-DONE] TAG=$TAG VAR=$VAR N=$N $(date -Is)"
touch "$OUT/ALLDONE_${SUFFIX}_N${N}_$TAG"
