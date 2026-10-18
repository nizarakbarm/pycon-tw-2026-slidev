#!/usr/bin/env python3
# GhostLock enforcer half, BCC version.
#
# This is the A/B partner of ghostlock_enforce.py (Python-BPF). Same job: watch
# kprobe/do_futex, tag the GhostLock op set, and act on FUTEX_CMP_REQUEUE_PI.
#
# The difference is the helper surface. BCC ships bpf_send_signal, so the signal
# is raised FROM THE KERNEL PROGRAM rather than read back through trace_pipe.
# Python-BPF has no such helper, so ghostlock_enforce.py has to print the line,
# read it in userspace, and os.kill() from there.
#
# What is STILL true in this version, and worth saying on the slide:
#   * bpf_send_signal delivers SIGKILL on return from the tracepoint, which is
#     AFTER do_futex has run. So the syscall that matters has already executed.
#     Being in the kernel removes the trace_pipe hop, not the ordering.
#   * No in-kernel deny. Neither library can say "return an error here instead".
#     XDP drop is a verdict; a kprobe is not. A seccomp filter acts before the
#     syscall, which is why it can deny where a signal cannot.
#
# Probe point: kprobe/do_futex, matching the Python-BPF tracker. The sys_*
# wrapper needs a two-step deref for the op; do_futex takes it as a plain arg.
from bcc import BPF

program = r"""
// Two headers are deliberately NOT included, and both cost a debugging round:
//   linux/futex.h -> drags in mutex code clang cannot emit for BPF
//                    ("call to undeclared function mutex_init")
//   struct pt_regs -> this kernel forward-declares it only, so BCC's own
//                    rewrite of a typed kprobe argument ("int op" -> "ctx->di")
//                    fails with "incomplete definition of type struct pt_regs".
// So state the op values as integers and give the register frame a local
// layout. x86-64 pt_regs order is fixed, and the 2nd C argument is in rsi -
// the same register the Python-BPF tracker reads as ctx.si.
#define SIGKILL 9

struct pt_regs_x64 {
    unsigned long r15, r14, r13, r12, rbp, rbx, r11, r10, r9, r8;
    unsigned long rax, rcx, rdx, rsi, rdi, orig_rax, rip, cs, eflags, rsp, ss;
};
#define ARG2(ctx) (((struct pt_regs_x64 *)(ctx))->rsi)

// FUTEX_LOCK_PI=6, FUTEX_WAIT_REQUEUE_PI=11, FUTEX_CMP_REQUEUE_PI=12,
// plus FUTEX_PRIVATE_FLAG(128) -> 134 / 139 / 140.
static __always_inline int ghostlock_tag(int op) {
    if (op == 12 || op == 140) return 3;   // GhostLock trigger
    if (op == 11 || op == 139) return 2;   // waiter parks
    if (op == 6  || op == 134) return 1;   // PI chain built
    return 0;
}

int do_futex_probe(void *ctx) {
    int op = (int)ARG2(ctx);
    int tag = ghostlock_tag(op);
    if (tag == 0)
        return 0;

    u32 pid = bpf_get_current_pid_tgid() >> 32;
    bpf_trace_printk("GHOSTLOCK op=%d tag=%d pid=%d\n", op, tag, pid);

    // The helper Python-BPF does not have. Queues a signal on return from this
    // probe, which is AFTER do_futex has already done its work.
    //
    // The kill itself leaves no line: the program is gone before anything could
    // print it, and the only trace is the child's exit status. So print the
    // decision here, before signalling, and let the harness report the rc. The
    // Python-BPF enforcer can log ENFORCER KILLED because userspace does the
    // kill; this side has to announce it in advance.
    if (tag == 3) {
        bpf_trace_printk("ENFORCER signalling SIGKILL pid=%d\n", pid);
        bpf_send_signal(SIGKILL);
    }

    return 0;
}
"""

b = BPF(text=program)
b.attach_kprobe(event="do_futex", fn_name="do_futex_probe")
print("ENFORCER-READY (bcc, in-kernel signal)", flush=True)

# Keep the process alive while the program is attached. No trace_pipe read is
# needed for enforcement: the kernel raises the signal itself. Drain the trace
# pipe only so the log matches the Python-BPF run line for line.
while True:
    try:
        (_, _, pid, _, _, line) = b.trace_fields()
        print(line.decode().strip(), flush=True)
    except KeyboardInterrupt:
        break
