#!/root/experiment/.venv/bin/python3
# GhostLock enforcer half. Python-BPF has no in-kernel deny primitive (no BPF-LSM
# section, no bpf_override_return helper), so the block is a userspace policy
# action fed by the PBPF signal: kill the task seen issuing FUTEX_CMP_REQUEUE_PI
# (tag=3). The kernel-side equivalent is the seccomp PI-futex filter from
# Atlas/Dots/Things/CVE-2026-43499 GhostLock/GhostLock — Mitigation.md.
#
# Reads /sys/kernel/tracing/trace_pipe (consuming reader): each printk line from
# the PBPF program is delivered exactly once.
import os
import re
import signal
import sys
from pythonbpf import bpf, bpfglobal, section, BPF
from pythonbpf.helper import pid
from vmlinux import struct_pt_regs
from ctypes import c_int64

@bpf
@bpfglobal
def LICENSE() -> str:
    return "GPL"

@bpf
@section("kprobe/do_futex")
def ghostlock_watch(ctx: struct_pt_regs) -> c_int64:
    op = ctx.si
    process_id = pid()
    tag = 0
    if op == 12 or op == 140:
        tag = 3
    if op == 11 or op == 139:
        tag = 2
    if op == 6 or op == 134:
        tag = 1
    if tag > 0:
        print(f"GHOSTLOCK op={op} tag={tag} pid={process_id}")
    return 0

b = BPF()
b.load()
b.attach_all()
print("ENFORCER-READY", flush=True)

PAT = re.compile(r"GHOSTLOCK op=(\d+) tag=(\d+) pid=(\d+)")
handled = set()
with open("/sys/kernel/tracing/trace_pipe", "r", errors="replace") as f:
    for line in f:
        m = PAT.search(line)
        if not m:
            continue
        op, tag, target = int(m.group(1)), int(m.group(2)), int(m.group(3))
        if target == os.getpid() or (target, tag) in handled:
            continue
        handled.add((target, tag))
        print(f"ENFORCER signal op={op} tag={tag} pid={target}", flush=True)
        if tag == 3:
            try:
                os.kill(target, signal.SIGKILL)
                print(f"ENFORCER KILLED pid={target}", flush=True)
            except ProcessLookupError:
                print(f"ENFORCER pid={target} already gone", flush=True)
