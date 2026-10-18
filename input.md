# Python eBPF: BCC C-String Runtime vs Python-BPF AST AOT

## Conference
PyCon Taiwan 2026

## Speaker
Nizar Akbar Meilani — DomaiNesia

## Core Narrative
Two frameworks, same BPF bytecode. But completely different userland architectures.
We measured everything: startup syscalls, per-event CPU, memory, profiling, bytecode, JIT instructions.

### Surprising Discovery
For identical programs, BCC and Python-BPF produce **byte-for-byte identical BPF bytecode** (same BTF tag). All runtime differences are purely userspace dispatch overhead.

### The Real Bottleneck (Centerpiece)
PBPF's `struct_parser` performs **two memcpy operations** per event:

1. `py::bytes(data, size)` — COPY #1: ring buffer → Python bytes (~130 ns). ALWAYS.
2. `from_buffer_copy(py_data)` — COPY #2: Python bytes → ctypes struct (~675 ns). Only with `struct_name`.

**Total: ~805 ns/event = 1.61s at 2M events (17% of CPU).**

BCC uses zero-copy `c_void_p` pointer overlay — ~238 ns.

### Framework Bridge Comparison
- PBPF no-struct: 3,968 ns/ev (16% faster than BCC equivalent)
- PBPF with struct: 4,773 ns/ev (3.4% faster than BCC)
- Full callback (print): essentially equal (~1.013x)
- PBPF pybind11 dispatch beats BCC ctypes by ~18% raw dispatch

### Key Measurements
| Metric | BCC | PBPF | Winner |
|--------|-----|------|--------|
| Init CPU | ~0.54s | ~0.024s | PBPF 23x |
| Peak memory | 125 MB | 53 MB | PBPF 0.43x |
| Total syscalls | 15,333 | 4,513 | PBPF 3.4x |
| Kernel header reads | 10,517 | 0 | PBPF ∞ |
| No-struct empty CB | 4,705 ns/ev | 3,968 ns/ev | PBPF 16% |
| Struct empty CB | 4,943 ns/ev | 4,773 ns/ev | PBPF 3.4% |
| Full print CB | 6,965 ns/ev | 7,056 ns/ev | BCC 1.3% |
| JIT glue | 12.1 cyc/ev | 15.3 cyc/ev | BCC 1.26x (negligible) |

### PBPF Double Copy — Cost Breakdown
| Component | Per-event | 2M total | Notes |
|-----------|-----------|----------|-------|
| COPY #1: `py::bytes` | ~130 ns | 0.26s | Always — BCC skips via c_void_p |
| COPY #2: `from_buffer_copy` | ~675 ns | 1.35s | Only with `struct_name="data_t"` |
| **Total struct_parser** | **805 ns/ev** | **1.61s** | PBPF-specific double-copy |
| BCC `.event(data)` | ~238 ns | 0.48s | Cheaper — pointer overlay |

### Fix
Replace `from_buffer_copy` with typed memoryview overlay on existing `py::bytes` buffer. Eliminates COPY #2, saving 1.35s at 2M events.

### Architecture Differences
**BCC Pipeline:**
```
Python code → BPF(text="""C code""")
  → fork clang (preprocessor)
  → fork clang (compiler)
  → BPF .o via kernel headers (10,517 read() calls)
  → load via bpf() syscall
```

**PBPF Pipeline:**
```
Python code → @bpf decorator
  → AST parsed from source (0 kernel headers)
  → llvmlite IR generated
  → llc compile to BPF .o
  → load via bpf() syscall
```

### Runtime Architecture Table
| Aspect | BCC | Python-BPF |
|--------|-----|------------|
| Callback bridge | ctypes (c_void_p, zero-copy) | pybind11 (py::bytes alloc per event) |
| Poll mechanism | poll() (POSIX) | epoll_wait() (libbpf perf_buffer__poll) |
| GIL release | implicit — ctypes Py_BEGIN_ALLOW_THREADS | explicit — py::gil_scoped_release |
| GIL re-acquire | implicit on C return | explicit py::gil_scoped_acquire per event |
| Format string | Stack movabs pairs per 8B | .rodata map — single movabs |
| Attach method | legacy PERF_EVENT_IOC_SET_BPF ioctl | modern BPF_LINK_CREATE |
| Struct access | Clang AST rewrite (ProbeVisitor) | explicit probe_read via vmlinux_parser + BTF |

### Methodology
**Workloads:**
- High-rate: syscalls/sys_enter_openat, ~150K ev/s, 2M events via gen_fast
- Low-rate: syscalls/sys_enter_unlinkat, ~1K ev/s

**10 Measurement Tools:** strace -c/-T, time.process_time(), perf stat, perf record -F 199, perf probe, py-spy, scalene, time -v, bpftool dump

### Test Matrix
Each program varies 3 axes:
| Axes | Variants |
|------|----------|
| Map usage | with_map vs perf_only vs no_perf |
| Callback | full (print) vs empty vs none |
| Struct/event | struct_name set vs no-struct |

### Key Surprises
1. PBPF no-struct (raw bytes, empty cb) is 16% faster than BCC — cleanest baseline. pybind11 dispatch leaner than ctypes.
2. BCC's "1.68x cheaper" was ring buffer overflow artifact (BCC lost 5,543 samples at 2M events with slow callbacks). Fresh data with empty callback: PBPF 7.3% faster.
3. JIT glue delta (1.26x BCC = 3.2 cyc/ev = 1.3 ns/ev × 2M = 2.6ms) is negligible — contributes 0.07% of gap.

### BCC's Remaining Advantage
`(*count)++` in BPF C → 3 JIT insns ptr dereference. PBPF requires `lookup() + update()` read-modify-write via helper call (~22 insns). At high map write rates, this is ~1.8 µs kernel cost.

### PBPF Format String Advantage
Stored in .rodata BPF map — single pointer load, independent of length.
BCC stores on stack — movabs pairs per 8 bytes, scales with length.
→ 6x fewer instructions for long strings (~100B).

### PBPF Limitations
1. **No ast.Subscript handler** (expr_pass.py:730) — blocks array-indexed field access
2. **No atomic_rmw** (expr_pass.py:227) — count += 1 has race window on multi-CPU
3. **Cannot read kernel strings from kprobes** — missing inttoptr in emitter for probe_read_str
