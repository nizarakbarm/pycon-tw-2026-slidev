import threading, time, signal
from bcc import BPF

main_ident = threading.get_ident()
main_native = threading.get_native_id()

interrupted = False

def handler(signum, frame):
    global interrupted
    interrupted = True

signal.signal(signal.SIGINT, handler)

program="""
struct data_t {
    u32 uid;
    char comm[16];
};

BPF_PERF_OUTPUT(events);

TRACEPOINT_PROBE(syscalls, sys_enter_execve) {
    u32 uid = bpf_get_current_uid_gid();
    if (uid == 1000) {
        struct data_t data = {};
        bpf_get_current_comm(&data.comm, sizeof(data.comm));
        data.uid = uid;
        events.perf_submit(args, &data, sizeof(data));
    }
    return 0;
}
"""

t0_cpu = time.process_time()
t0_wall = time.perf_counter()

b = BPF(text=program)
t1_cpu = time.process_time()
t1_wall = time.perf_counter()

def print_event(cpu, data, size):
    if threading.get_ident() != main_ident:
        print(f"[THREAD] WARNING: callback on DIFFERENT thread! pid={threading.get_ident()} main={main_ident}")
    event = b["events"].event(data)
    if event.uid == 1000:
        print(f"CPU [{cpu}] UID {event.uid} comm: {event.comm.decode('utf8', 'replace')}")

b["events"].open_perf_buffer(print_event)
t2_cpu = time.process_time()
t2_wall = time.perf_counter()

print(f"[THREAD] Main poll: ident={main_ident} native={main_native}")
print(f"[TIMING] BPF init CPU: {t1_cpu-t0_cpu:.3f}s wall: {t1_wall-t0_wall:.3f}s")
print(f"[TIMING] Setup CPU: {t2_cpu-t1_cpu:.3f}s wall: {t2_wall-t1_wall:.3f}s")
print("Starting to poll... (Ctrl+C top stop)")

try:
    while not interrupted:
        b.perf_buffer_poll(1)
except KeyboardInterrupt:
    pass
t3_cpu = time.process_time()
t3_wall = time.perf_counter()

print(f"[TIMING] Poll loop CPU {t3_cpu-t2_cpu:.3f}s wall: {t3_wall-t2_wall:.3f}s")
print(f"[TIMING] Total CPU: {t3_cpu-t0_cpu:.3f}s wall: {t3_wall-t0_wall:.3f}s")
print(f"[SUMMARY] Events in using perf only")

