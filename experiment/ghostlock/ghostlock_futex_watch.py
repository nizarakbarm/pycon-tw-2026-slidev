#!/root/experiment/.venv/bin/python3
# GhostLock (CVE-2026-43499) tracker — Python-BPF 0.2.0
#
# Probe point: kprobe/do_futex, NOT kprobe/__x64_sys_futex.
#   sys_* wrappers receive `struct pt_regs *` in rdi; the syscall args only exist
#   in the saved frame, so reading them needs a two-step dereference PBPF cannot
#   emit (see "Python-BPF Probe Read of ctx.si Returns Garbage"). Measured on
#   vmnono 6.12: at __x64_sys_futex, rsi=0xca (syscall nr), never the op.
#   do_futex takes the op as a plain C argument -> op == ctx.si. Verified:
#   tracefs p:gl3 do_futex -> si=0x6,0x86,0xb,0x8b,0xc,0x8c for our trigger.
#
# Design forced by our limitation notes:
#   * ONE section per file (struct_pt_regs + 2 sections => RecursionError)
#   * no buffer arrays, no pointer deref  -> only scalar register reads
#   * no struct-valued map (assign_pass/StructType.gep -> "invalid getelementptr
#     indices", broken on 0.2.0 and master f2e6fba) -> no state kept in maps
#   * one printk per program in the hot path (reads many ctx fields / many
#     printk args are what break: measured 8-arg and 5-print variants silent)
from pythonbpf import bpf, bpfglobal, section, BPF, trace_pipe
from pythonbpf.helper import pid
from vmlinux import struct_pt_regs
from ctypes import c_int64

# kernel/futex/syscalls.c op values used by the GhostLock chain
# FUTEX_LOCK_PI=6, FUTEX_WAIT_REQUEUE_PI=11, FUTEX_CMP_REQUEUE_PI=12
# + FUTEX_PRIVATE_FLAG(128) -> 134 / 139 / 140 (glibc PI mutexes are private)

@bpf
@bpfglobal
def LICENSE() -> str:
    return "GPL"

@bpf
@section("kprobe/do_futex")
def ghostlock_watch(ctx: struct_pt_regs) -> c_int64:
    op = ctx.si              # 2nd arg of do_futex = int op
    process_id = pid()
    tag = 0
    if op == 12 or op == 140:
        tag = 3              # proxy-lock requeue: the GhostLock trigger
    if op == 11 or op == 139:
        tag = 2              # waiter parks in FUTEX_WAIT_REQUEUE_PI
    if op == 6 or op == 134:
        tag = 1              # PI chain built with FUTEX_LOCK_PI
    if tag > 0:
        print(f"GHOSTLOCK op={op} tag={tag} pid={process_id}")
    return 0

b = BPF()
b.load()
b.attach_all()
print("attached kprobe/do_futex")
trace_pipe()
