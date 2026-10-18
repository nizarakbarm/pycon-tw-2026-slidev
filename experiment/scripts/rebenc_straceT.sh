#!/bin/bash
# strace -f -T UNFILTERED: per-syscall wall duration, all syscalls.
# Scope: N = 20 50 1000 (per plan), 3 variants, both frameworks.
#
# Deliverable: summed per-call time per syscall, ranked -- the ranking is produced
# from the FULL trace, NOT strace -c (which does not carry per-call durations).
# Artifacts are big (one line per syscall); output NOT under /tmp.
#
# CAVEAT baked into the report: these arms are ~93% blocked, so a syscall's summed
# duration can be pure WAITING (poll's own 1 ms timeout), not cost. The ranking must
# be cross-read with the count table in
# [[strace syscall census sys_enter_execve with_map BCC vs Python-BPF]].
set -u
TAG="${TAG:-$(date -u +%Y%m%dT%H%M%SZ)}"
N="${N:-20}"
VARIANT="${VARIANT:-count}"
OUT="${OUT:-/root/rebenc-strace-T}"
GAP="${GAP:-60}"
T="${T:-0.5}"
STRACE="${STRACE:-/usr/bin/strace}"
mkdir -p "$OUT"

[ "$(hostname)" = nono1 ] || { echo "[HALT] vmnono/nono1 only"; exit 1; }

case "$VARIANT" in
  count) SUFFIX="map1_count" ;;
  A)     SUFFIX="ablA_empty" ;;
  B)     SUFFIX="ablB_print_const" ;;
  *) echo "[HALT] VARIANT must be count|A|B"; exit 2 ;;
esac

PY_BCC=/usr/bin/python3
PY_PB=/root/experiment/.venv/bin/python3
D_BCC=/root/experiment/with_map/bcc/sys_enter_execve
D_PB=/root/experiment/with_map/pythonbpf/sys_enter_execve
case "$VARIANT" in
  count) PROG_BCC=$D_BCC/map_1_perf_timed_count.py ; PROG_PB=$D_PB/map_1_perf_timed_count.py ;;
  A)     PROG_BCC=$D_BCC/abl_A_empty_callback.py  ; PROG_PB=$D_PB/abl_A_empty_callback.py ;;
  B)     PROG_BCC=$D_BCC/abl_B_print_const.py     ; PROG_PB=$D_PB/abl_B_print_const.py ;;
esac
TRIG_USER=operator
TRIG_BIN=/usr/local/bin/gen_exec

for p in "$PROG_BCC" "$PROG_PB"; do
  [ -f "$p" ] || { echo "[HALT] missing: $p"; exit 3; }
done

arm() {                    # impl python program pre-sleep
  local impl="$1" py="$2" prog="$3" pre="$4"
  local base="$OUT/trace_execve_${SUFFIX}_${impl}_N${N}_${TAG}"
  local tr="$base.T.txt" log="$base.prog.log" rank="$base.rank.txt"
  local spid pid i

  "$STRACE" -f -T -o "$tr" -- "$py" "$prog" > "$log" 2>&1 &
  spid=$!
  sleep "$pre"

  pid=""
  for i in $(seq 1 40); do
    pid=$(pgrep -P "$spid" 2>/dev/null | sed -n 1p)
    [ -n "$pid" ] && break
    sleep 0.5
  done


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

  if [ -n "$pid" ]; then kill -INT "$pid" 2>/dev/null || true
  else echo "    [WARN] no child pid under strace $spid"; pkill -INT -f "^${py} ${prog}" || true; fi
  for i in $(seq 1 60); do
    kill -0 "$pid" 2>/dev/null || break
    kill -0 "$spid" 2>/dev/null || break
    sleep 0.5
  done
  kill -INT "$spid" 2>/dev/null || true
  for i in $(seq 1 60); do kill -0 "$spid" 2>/dev/null || break; sleep 0.5; done
  kill -0 "$spid" 2>/dev/null && { echo "    [WARN] strace alive; killing"; kill -9 "$spid" 2>/dev/null; sleep 1; }
  grep -q '\[TIMING\] Total CPU' "$log" || echo "    [WARN] program teardown missing"

  local summary tl
  summary=$(grep -a '\[SUMMARY\]' "$log" | sed -n 's/.*Events in map: *\([0-9]*\).*/\1/p')
  tl=$(wc -l < "$tr" 2>/dev/null || echo 0)

  # rank: sum the <dur> field per syscall name.
  # The -T duration is the LAST <d.dddd> on a completed line -- lines can carry
  # trailing content and resumed syscalls wrap, so anchoring a match on the end
  # of the line finds almost nothing (it silently produced empty ranks once).
  # rank_T.py handles this and writes $rank itself.
  python3 /root/experiment/scripts/rank_T.py "$tr" > /dev/null 2>&1

  echo "[DONE] variant=$SUFFIX impl=$impl N=$N  summary=${summary:-MISSING} (expect $((N+1)))  trace_lines=$tl"
  echo "    TOP syscalls by summed time (sec, calls, name):"
  head -12 "$rank" | awk -F'\t' '{printf "      %10.4f s  %8d  %s\n", $1, $2, $3}'
}

echo "[START] TAG=$TAG host=$(hostname) VARIANT=$VARIANT ($SUFFIX) N=$N strace=-f -T (unfiltered) $(date -Is)"
echo "  BCC : $PROG_BCC"
echo "  PBPF: $PROG_PB"
echo "--- arm 1: BCC (pre-sleep 2s) ---"
arm bcc  "$PY_BCC" "$PROG_BCC" 2
echo "[GAP] idle ${GAP}s"; sleep "$GAP"
echo "--- arm 2: PBPF (pre-sleep 1s) ---"
arm pbpf "$PY_PB"  "$PROG_PB"  1
echo "[ALL-DONE] TAG=$TAG VARIANT=$VARIANT N=$N $(date -Is)"
touch "$OUT/ALLDONE_${SUFFIX}_N${N}_$TAG"
