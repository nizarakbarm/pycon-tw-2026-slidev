import threading
import time
import resource
import signal
from bcc import BPF

main_ident = threading.get_ident()
main_native = threading.get_native_id()
interrupted = False

def handler(signum, frame):
    global interrupted
    interrupted = True

signal.signal(signal.SIGINT, handler)

program="""
BPF_HASH(count_hash, u32, u64);

struct data_t {
    u32 uid;
    u64 count;
    char comm[16];
};

BPF_PERF_OUTPUT(events);

TRACEPOINT_PROBE(syscalls, sys_enter_execve) {
    u32 uid = bpf_get_current_uid_gid();
    struct data_t data = {};
    if (uid == 1000) {
        bpf_get_current_comm(&data.comm, sizeof(data.comm));
	data.uid = uid;
	u64 *count, zero = 0;
        count = count_hash.lookup(&uid);
        if (count) {
            (*count)++;
	    data.count = *count;
        } else {
            count_hash.update(&uid, &zero);
            data.count = 0;
        }
        events.perf_submit(args, &data, sizeof(data));
    }
    return 0;
}
"""

def _rusage(tag):
    r = resource.getrusage(resource.RUSAGE_SELF)
    c = resource.getrusage(resource.RUSAGE_CHILDREN)
    print(f"[RUSAGE] {tag} maxrss={r.ru_maxrss}KB minflt={r.ru_minflt} majflt={r.ru_majflt} "
          f"inblock={r.ru_inblock} oublock={r.ru_oublock} nvcsw={r.ru_nvcsw} nivcsw={r.ru_nivcsw} "
          f"utime={r.ru_utime:.3f}s stime={r.ru_stime:.3f}s "
          f"| children utime={c.ru_utime:.3f}s stime={c.ru_stime:.3f}s maxrss={c.ru_maxrss}KB", flush=True)


t0_cpu = time.process_time()
t0_wall = time.perf_counter()

b = BPF(text=program)

t1_cpu = time.process_time()
t1_wall = time.perf_counter()

def print_event(cpu, data, size):
    if threading.get_ident() != main_ident:
        print(f"[THREAD] WARNING: callback on DIFFERENT thread! pid={threading.get_ident()} main={main_ident}", flush=True)
    pass

b["events"].open_perf_buffer(
            callback=print_event,
            lost_cb=lambda cnt: print(f"[LOST] {cnt} events lost")
)

t2_cpu = time.process_time()
t2_wall = time.perf_counter()

print(f"[THREAD] Main poll: ident={main_ident} native={main_native}", flush=True)
print(f"[TIMING] BPF init CPU: {t1_cpu-t0_cpu:.3f}s  wall: {t1_wall-t0_wall:.3f}s", flush=True)  # rusage
_rusage("init")
print(f"[TIMING] Setup CPU: {t2_cpu-t1_cpu:.3f}s  wall: {t2_wall-t1_wall:.3f}s", flush=True)  # rusage
_rusage("setup")

print("Starting poll... (Ctrl+C to stop)", flush=True)

try:
    t3_cpu = time.process_time()
    t3_wall = time.perf_counter()
    while not interrupted:
        b.perf_buffer_poll(1)
except KeyboardInterrupt:
    pass

t4_cpu = time.process_time()
t4_wall = time.perf_counter()

print(f"[TIMING] Poll loop CPU: {t4_cpu-t3_cpu:.3f}s  wall: {t4_wall-t3_wall:.3f}s", flush=True)  # rusage
_rusage("poll")
print(f"[TIMING] Total CPU: {t4_cpu-t0_cpu:.3f}s  wall: {t4_wall-t0_wall:.3f}s", flush=True)
print(f"[SUMMARY] Events in map: {sum(v.value+1 for v in b["count_hash"].values())}")
_rusage("after-summary")
