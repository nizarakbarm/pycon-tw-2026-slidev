import logging
from pythonbpf import bpf, struct, map, section, BPF
from pythonbpf.maps import HashMap
from pythonbpf.helper import pid
from ctypes import c_uint32, c_uint64, c_void_p, c_int64

@bpf
@struct
class ProcessStats:
    syscall_count: c_uint64
    total_time: c_uint64
    max_latency: c_uint64

@bpf
@map
def stats() -> HashMap:
    return HashMap(
        key=c_uint32,
        value=ProcessStats,
        max_entries=1024
    )

@bpf
@section("tracepoint/syscalls/sys_enter_read")
def track_syscalls(ctx: c_void_p) -> c_int64:
    process_id = pid()

    # Lookup existing stats
    s = stats.lookup(process_id)

    if s:
        # Update existing stats
        s.syscall_count = s.syscall_count + 1
        stats.update(process_id, s)
    else:
        # Create new stats
        new_stats = ProcessStats()
        new_stats.syscall_count = 1
        new_stats.total_time = 0
        new_stats.max_latency = 0
        stats.update(process_id, new_stats)

    return 0


b = BPF(loglevel=logging.DEBUG)
b.load()
b.attach_all()
