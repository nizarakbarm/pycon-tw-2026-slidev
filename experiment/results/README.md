# BCC vs Python-BPF — execve benchmark results

Three measurement passes over the same six programs, same tracepoint, same trigger.
Built for publishing alongside the analysis notes.

## Layout

```
results/
  unprofiled/    pass 1 — no instrumentation; [TIMING] + [RUSAGE]
  straceT/       pass 2 — strace -f -T (unfiltered); full syscall traces + rankings
  perfrecord/    pass 3 — perf record -F 199 --call-graph dwarf; .data + .folded + .svg
```

Each pass writes one file set per arm, tagged so a rerun cannot overwrite a previous one.

## What was measured

| item | value |
|---|---|
| host | `vmnono` (hostname `nono1`), 3 CPUs, openSUSE Leap 16.1, kernel 6.12.0-160100.7 |
| tracepoint | `syscalls/sys_enter_execve` |
| trigger | `/usr/local/bin/gen_exec N`, run as user `operator` (uid 1000) |
| uid filter | `uid == 1000`, enforced in the BPF program |
| N | 20, 50, 100, 1000, 2000, 2000000 |
| frameworks | BCC (system `python3`) vs Python-BPF (`/root/experiment/.venv/bin/python3`) |
| arms | 2 frameworks × 3 variants × 6 N = 36 per pass |
| drain | `T=0.5` s after the trigger returns, then bounded SIGINT teardown |
| order | BCC arm first, 60 s idle gap, then PBPF; pre-sleep 2 s (BCC) / 1 s (PBPF) |

## The trigger gate — read this before reproducing

**Do not fire the trigger on a fixed pre-sleep.** Under `strace` or `perf record` the traced
child starts *later* than `$!`, so `sleep $pre` can expire before the BPF program has
attached. The trigger's burst is then fired into a program that is not listening: those
events are lost, **no `[LOST]` is reported**, and no drain length recovers them.

The harness therefore waits for the program to report it is polling, then fires:

```bash
local ready=0
for i in $(seq 1 120); do
  grep -qaE 'Starting (to )?poll' "$log" && { ready=1; break; }
  sleep 0.5
done
[ "$ready" = 1 ] || echo "    [WARN] program never reported polling within 60s"
```

The pattern must match both frameworks — BCC prints `Starting poll...`, Python-BPF prints
`Starting to poll...`. The pre-sleep is retained only as a lower bound.

> [!warning] **Evidence.** Two pass-2 arms failed before the gate existed (PBPF N=50 gave
> 25/51; BCC N=50 gave 30/51) and the cause was *not* a short drain: attach time fell
> **after** the trigger in both, a negative margin. `T=2` alone did not fix it. With the
> gate, both re-ran to 51/51. The gate is in `rebenc_straceT.sh`, `rebenc_perfrec.sh` and
> `rebenc_unprof.sh`; pre-gate copies are in `/root/rebenc-t15-backup/*.pregate`.

## Quarantined arms

The published tree holds only valid arms. Defective and duplicate runs are kept for audit:

| dir | contents |
|---|---|
| `straceT/_failed/` | 2 arms (6 files) that did not deliver `N+1` — the trigger-race cases above |
| `straceT/_dup/` | 2 arms (6 files) superseded by a gated re-run of the same `(variant, impl, N)` |

## Programs (all six, identical structure — only the callback body differs)

| variant | file | callback body |
|---|---|---|
| `count` | `map_1_perf_timed_count.py` | full line: `UID`, `comm`, `count` |
| `A` | `abl_A_empty_callback.py` | `pass` (no print, no field access) |
| `B` | `abl_B_print_const.py` | `print("event")` |

Source: `/root/experiment/with_map/{bcc,pythonbpf}/sys_enter_execve/`

All six carry `resource.getrusage` instrumentation, emitting `[RUSAGE]` at each
`[TIMING]` point and after `[SUMMARY]`.

> [!warning] **No `flush=True` on the per-event print** in any of the six. It was removed
> after it was shown to add a write syscall per event, drop delivery to 55–78%, and
> inflate BCC's CPU ~21%. Startup/teardown prints do flush, so `[TIMING]` survives teardown.

## Reading each pass

### `unprofiled/` — `unprofiled_execve_<variant>_<impl>_N<N>_<TAG>.log`

In-program counters. Quote **CPU**, not wall: the trigger is fork-bound and wall varies
~10% run to run.

- `[TIMING]` — `process_time()` deltas per phase (init / setup / poll loop / total)
- `[RUSAGE]` — peak RSS, page faults, block I/O, context switches, and a **user/sys split**,
  reported for the process **and for reaped children separately**
- `[SUMMARY] Events in map` — delivery; equals `N+1` (the trigger's own exec adds one)

> [!important] **Rusage CPU and `[TIMING]` CPU are different accountings and must not be
> compared to each other.** `[TIMING]` is `process_time()`, self only, scoped to a phase.
> Rusage counts self and children across the whole process lifetime. Init reads 0.580 s
> under `[TIMING]` and 0.543 s under rusage for BCC; 0.021 s and 0.171 s for PBPF.

### `straceT/` — `trace_execve_<variant>_<impl>_N<N>_<TAG>.{T.txt,prog.log,rank.txt}`

`strace -f -T -o <T.txt> -- <py> <prog>` — **unfiltered**, every syscall, with per-call duration.

- `.T.txt` is the durable artefact (one line per syscall)
- `.rank.txt` is a derived summary, **populated for all 36 arms** (header line + one row per syscall). Regenerate from `.T.txt` with `/root/experiment/scripts/rank_T.py` — the harness's own inline ranker was anchored on end-of-line and silently produced empty files, so use the script, not the old `awk`.
- `.prog.log` is the program's own stdout, including `[TIMING]` and `[RUSAGE]`

**Fold format:** `process_name;function_A;function_B;function_C 123456` — frames
semicolon-joined into **one field**, then a space, then the value in **microseconds**.
`awk` sees exactly 2 fields; `$2` is the value.

**Timings from this pass are unusable** — strace intercepts every syscall and these arms
spend ~93% of wall blocked, so interception lands on the syscall under study. **Counts only.**

### `perfrecord/` — `perfrec_execve_<variant>_<impl>_N<N>_<TAG>.{log,data,folded,svg}`

`perf record -F 199 --call-graph dwarf`. `-F` is frequency mode, so
`stackcollapse-perf.pl` sums sample **periods** — the folded values are **PMU cycles**,
not sample counts.

> [!warning] **`--call-graph dwarf` roughly doubles the target's measured CPU** (DWARF
> unwinding runs in the target's context). Absolute CPU from this pass is therefore
> comparable only **within** the pass, never to `unprofiled/`.

## Regenerating a rank file

`strace -c` discards per-call durations, so rankings must come from the full trace. The
`-T` value is the **last** `<d.dddd>` on a completed line (lines may carry trailing content,
and resumed syscalls wrap):

```python
import re, collections, glob
DUR = re.compile(r"<(\d+\.\d+)>")
for path in glob.glob("*T.txt"):
    tot, cnt = collections.Counter(), collections.Counter()
    for line in open(path, errors="replace"):
        m = None
        for m in DUR.finditer(line): pass          # last one wins
        if not m: continue
        head = re.sub(r"^\s*\d+\s+", "", line[:m.start()])
        head = re.sub(r"^<\.\.\.\s*", "", head).split("(")[0].strip()
        name = head.split()[-1] if head.split() else "?"
        tot[name] += float(m.group(1)); cnt[name] += 1
    with open(path.replace(".T.txt", ".rank.txt"), "w") as fh:
        for k, v in tot.most_common():
            fh.write("%.6f\t%d\t%s\n" % (v, cnt[k], k))
```

## Regenerating the flamegraphs

```bash
FG=/root/FlameGraph
for d in perfrec_execve_*.data; do
  b="${d%.data}"
  perf script -i "$d" 2>/dev/null | "$FG/stackcollapse-perf.pl" > "$b.folded"
  "$FG/flamegraph.pl" --color=io --countname=us --hash "$b.folded" > "$b.svg"
done
```

## Notes on interpretation

- **Wall time carries no framework signal.** The trigger sets the pace and is fork-bound;
  run-to-run trigger variance is ~8–16% on an idle machine.
- **The trigger's own cost, measured standalone at N=2M:** wall 1746 s, user 663 s,
  sys 925 s (58% kernel), peak RSS 12.3 MB, 3,986,194 voluntary context switches
  (1.99 per event).
- **2M is the only N where init has amortised.** Small-N ratios (~2.1×) and 2M ratios
  (~1.2–1.3×) measure the same thing at different points on the amortisation curve.
- **Delivery is asserted per arm** — `[SUMMARY]` must equal `N+1`. A shortfall means the
  drain was too short or events were dropped; the harness prints a `WARN`.

## Reproducing

```bash
cd /root

# pass 1 — un-profiled
env BASE_TAG=$(date -u +%Y%m%dT%H%M%SZ) \
    SMALL_NS="20 50 100 1000 2000" BIG_NS="2000000" VARIANTS="count A B" \
    OUT=/root/experiment/results/unprofiled T=0.5 \
    bash /root/experiment/scripts/pass1_unprof_sweep.sh

# pass 2 — strace -T
env BASE_TAG=$(date -u +%Y%m%dT%H%M%SZ) \
    NS="20 50 100 1000 2000 2000000" VARIANTS="count A B" \
    OUT=/root/experiment/results/straceT T=0.5 \
    bash /root/experiment/scripts/rebenc_straceT_sweep.sh

# pass 3 — perf record
env BASE_TAG=$(date -u +%Y%m%dT%H%M%SZ) \
    SMALL_NS="20 50 100 1000 2000" BIG_NS="2000000" VARIANTS="count A B" \
    OUT=/root/experiment/results/perfrecord T=1 FREQ=199 \
    bash /root/experiment/scripts/pass3_perfrec_sweep.sh
```

Launch detached (`setsid nohup … </dev/null &`) — the sweeps outlive an ssh session, and
pass 2 at 2M writes ~370 MB of trace per BCC arm.

## Program checksums

Recorded at packaging time. Compare against your checkout to confirm the arms match these files.

| file | md5 |
|---|---|
| `bcc/map_1_perf_timed_count.py` | `369eca40b59b6c542cacec9ab7d705a7` |
| `bcc/abl_A_empty_callback.py` | `9b6b66a173911eb7fa8e2815dcd1f106` |
| `bcc/abl_B_print_const.py` | `f8fb230ee7a04f24480c06fccf321a65` |
| `pythonbpf/map_1_perf_timed_count.py` | `6c6c11932fadfcea8a11854bf635b59e` |
| `pythonbpf/abl_A_empty_callback.py` | `35a089af9912b55979dbdbde8d33ebd5` |
| `pythonbpf/abl_B_print_const.py` | `8cd48288bd58edb4d746bbd9ccb25e1c` |
