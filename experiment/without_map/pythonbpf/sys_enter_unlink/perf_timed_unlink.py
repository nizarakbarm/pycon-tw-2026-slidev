import threading, time, signal
from pythonbpf import BPF, section, bpf, map, bpfglobal, struct
from pythonbpf.maps import HashMap, PerfEventArray
from pythonbpf.helper import uid, comm
from ctypes import c_void_p, c_uint32, c_uint64, c_int64

interrupted = False
def handler(signum, frame):
    global interrupted
    interrupted = True
signal.signal(signal.SIGINT, handler)

@bpf
@struct
class data_t:
    uid: c_uint64
    last_comm: str(16)

@bpf
@map
def events() -> PerfEventArray:
    return PerfEventArray(key_size=c_int64, value_size=c_int64)

@bpf
@bpfglobal
def LICENSE() -> str:
    return "GPL"

@bpf
@section("tracepoint/syscalls/sys_enter_unlink")
def trace_unlink(ctx: c_void_p) -> c_int64:
    u_id = uid()
    data = data_t()
    if u_id == 1000:
        comm(data.last_comm)
        data.uid = u_id
        events.output(data)
    return 0

main_ident = threading.get_ident()
main_native = threading.get_native_id()

t0_cpu = time.process_time()
t0_wall = time.perf_counter()
b = BPF()
b.load()
b.attach_all()
t1_cpu = time.process_time()
t1_wall = time.perf_counter()

def printdata(cpu, event):
    if threading.get_ident() != main_ident:
        print(f"[THREAD] WARNING: callback on DIFFERENT thread! pid={threading.get_ident()} main={main_ident}", flush=True)
    if event.uid == 1000:
       print(f"CPU [{cpu}] UID {event.uid} comm: {event.last_comm.decode()}")

perf = b["events"].open_perf_buffer(callback=printdata, struct_name="data_t")
t2_cpu = time.process_time()
t2_wall = time.perf_counter()

print(f"[THREAD] Main poll: ident={main_ident} native={main_native}", flush=True)
print(f"[TIMING] BPF init CPU: {t1_cpu-t0_cpu:.3f}s  wall: {t1_wall-t0_wall:.3f}s", flush=True)
print(f"[TIMING] Setup CPU: {t2_cpu-t1_cpu:.3f}s  wall: {t2_wall-t1_wall:.3f}s", flush=True)
print("Starting to poll... (Ctrl+C to stop)", flush=True)

try:
   while not interrupted:
     perf.poll(1)
except KeyboardInterrupt:
     pass
t3_cpu = time.process_time()
t3_wall = time.perf_counter()

print(f"[TIMING] Poll loop CPU: {t3_cpu-t2_cpu:.3f}s  wall: {t3_wall-t2_wall:.3f}s", flush=True)
print(f"[TIMING] Total CPU: {t3_cpu-t0_cpu:.3f}s  wall: {t3_wall-t0_wall:.3f}s", flush=True)
print(f"[SUMMARY] Events in using perf", flush=True)
