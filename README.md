# Python eBPF: BCC C-String Runtime vs Python-BPF AST AOT

PyCon Taiwan 2026. The deck, the harness, and the measured dataset.

**Nizar Akbar Meilani** — DomaiNesia

- Deck source: [`slides.md`](./slides.md)
- Rendered: [`outputs/presentation.pdf`](./outputs/presentation.pdf)
- Speaker notes: [`outputs/notes.md`](./outputs/notes.md)

## Run it

```bash
pnpm install
pnpm dev          # presentation entry, keeps the live <Editor /> slides
```

The deck is `theme: slidev-theme-nord`. Live editor slides need `slidev dev`;
a static build shows a placeholder.

## Export

```bash
pnpm export:pdf    # outputs a PDF
pnpm export:html
pnpm notes
```

Export goes through **`slides.export.md`**, not `slides.md`. The livecode addon
keeps a socket open and `slidev export` waits for networkidle, which then never
arrives (14 s becomes 250 s or a timeout), so the export entry omits the addon
and imports `slides.md` in ranges that skip the three `<Editor />` slides: 9,
10 and 24. Those ranges are by slide NUMBER, so update them whenever a slide is
added or removed above an Editor.

PDF and PPTX export need a Chromium. Set `SLIDEV_CHROME` to use a system one:

```bash
export SLIDEV_CHROME="/path/to/chrome"
```

## What was measured

Two Python eBPF frameworks, one tracepoint (`sys_enter_execve`), 2,000,000
events, three passes over the same arms.

| pass | instrument | what it answers | in this repo |
|---|---|---|---|
| 1 | none | startup, per-event CPU, wall, memory | `experiment/results/unprofiled/` |
| 2 | `strace -f -T` | every syscall, with duration | `experiment/results/straceT/` |
| 3 | `perf record --call-graph dwarf` | where the cycles go, by frame | `experiment/results/perfrecord/` |

```bash
# pass 1: the [TIMING] lines the CPU numbers come from
grep -E '^\[TIMING\]' experiment/results/unprofiled/*.log

# pass 2: per-syscall totals, sorted by time
cat experiment/results/straceT/*rank.txt

# pass 3: folded stacks, summed by frame
cat experiment/results/perfrecord/*.folded
```

## How to read the numbers

- **Quote CPU, not wall.** The trigger is a sequential `fork` → `wait` loop at
  about 0.7 ms per event, so wall measures the trigger and agrees between
  frameworks to 0.3% while CPU differs by 30% in the same pair.
- **Do not compare CPU across passes.** `--call-graph dwarf` unwinds in the
  target's own context and roughly doubles measured CPU, so pass 3 absolute CPU
  sits about 80% above pass 1. Ratios also move with the instrument:
  un-profiled 1.30 / 1.23 / 1.21, under `perf record` 1.21 / 1.17 / 1.08.
  Direction is stable; magnitude is not.
- **Rusage and `[TIMING]` are different accountings.** `[TIMING]` is
  `process_time()`, self only, scoped to a phase. Rusage counts self and
  children across the process lifetime. Do not compare them to each other.
- **Do not fire the trigger on a fixed pre-sleep.** Under `strace` or
  `perf record` the traced child starts after `$!`, so a fixed sleep can expire
  before attach; the burst is then lost with no `[LOST]` printed. The runners
  wait for the program to report it is polling.
- **Delivery is asserted per arm.** `[SUMMARY] Events in map` must equal `N+1`
  (the trigger's own `exec` adds one).
- **`strace -T` field position shifts with the argument text**, so a fixed `$9`
  silently reads the wrong field or nothing:
  `epoll_wait(9, [], 3, 1) = 0 <t>` has its duration at `$8`, and
  `epoll_wait(9, [{…}], 3, 1) = 1 <t>` at `$9`. Scan from `NF` downward for the
  last `<digits>` token instead.

## Limitations the talk reports

Four, all live. Each is a Python-BPF gap, and each is a compiler or helper gap
rather than a design limit. Two are visible in this tree:

- **No in-kernel deny, so enforcement is a userspace kill.** Python-BPF cannot
  attach a BPF-LSM program, cannot call `bpf_override_return`, and cannot call
  `bpf_send_signal`. The consequence is ordering: a userspace kill acts after
  the syscall returns, while a seccomp filter acts before it. `experiment/ghostlock/`
  is the end-to-end demo, and `ghostlock_enforce_bcc.py` is the BCC side, which
  does have `bpf_send_signal` and raises the signal from inside the program.
  It is still a kill on return from the probe, not a deny.
- **Two sections on one register struct.** A program with two sections that both
  take `struct_pt_regs` loads and attaches, and prints garbage, with no error.
  `experiment/Python-BPF/BCC-Examples/disksnoop.py` is that shape.

The other two: no two-step kernel read, so a kernel string cannot be
dereferenced; and silent codegen traps, where a `printk` with more than three
values after the format string compiles, attaches, and emits nothing. The bound
is a kernel one: `bpf_trace_printk` takes at most three additional u64 arguments.

## Layout

```
slides.md                 the deck, presentation entry (keeps the Editors)
slides.export.md          export entry (skips the Editors)
input.md                  raw source notes the deck was written from
styles/index.css          deck palette and the section-divider rule
images/                   the intro portrait
img/                      SVG renders of the two perf traces
outputs/                  built artifacts
experiment/scripts/       the runners, one per pass
experiment/with_map/      the count arm, BCC and Python-BPF
experiment/without_map/   the null arm, sources only
experiment/results/       measured data, see the table above
experiment/ghostlock/     the end-to-end deny demo, both frameworks
```

## What is not in this repository

Raw dumps, because they are gigabytes and regenerate:

- `*.data` — `perf record` binaries, 1.3 GB
- `*.T.txt` — full `strace -f -T` traces, 2.9 GB
- per-event `stdout.txt` / `prog.log` — millions of lines each

The `prog.log` files under `results/unprofiled/` are reduced to their
`[TIMING]`, `[SUMMARY]` and `[THREAD]` lines, which is every number the deck
cites. The `*.folded` stacks are kept whole, because slide 18 sums them by frame.

## Links

- Python-BPF — <https://github.com/python-bpf/python-bpf>
- BCC — <https://github.com/iovisor/bcc>
- Slidev — <https://sli.dev>
