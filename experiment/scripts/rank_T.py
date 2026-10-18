"""Rank syscalls by summed per-call duration from strace -f -T traces.

The -T duration is the LAST <d.dddddd> on a completed line. Lines may be:
  PID syscall(args) = ret  <0.000023>
  PID syscall(args) = ret  <0.000023>  more
  PID syscall(args <unfinished ...>
  PID <... syscall resumed>) = ret <0.000023>
So: take the last <digits.digits> token anywhere on the line, and derive the
syscall name from the text BEFORE it (last identifier before '(' ), skipping
'resumed>/<...' wrappers.
"""
import re
import sys
import glob
import os
import collections

DUR = re.compile(r"<(\d+\.\d+)>")
NAME = re.compile(r"(?:^\d+\s+)?(?:<\.\.\.\s+)?([a-zA-Z_][a-zA-Z0-9_]*)")

for path in sorted(glob.glob(sys.argv[1])):
    tot = collections.Counter()
    cnt = collections.Counter()
    unparsed = 0
    n = 0
    with open(path, errors="replace") as fh:
        for line in fh:
            n += 1
            m = None
            for m in DUR.finditer(line):   # last one wins
                pass
            if not m:
                unparsed += 1
                continue
            d = float(m.group(1))
            head = line[: m.start()]
            # drop a leading PID, then any 'resumed>/<...' noise
            head = re.sub(r"^\s*\d+\s+", "", head)
            head = re.sub(r"^<\.\.\.\s*", "", head)
            head = head.split("(")[0].strip()
            nm = head.split()[-1] if head.split() else ""
            if not nm:
                nm = "?"
            tot[nm] += d
            cnt[nm] += 1

    out = path.replace(".T.txt", ".rank.txt")
    with open(out, "w") as fh:
        fh.write("# total_s\tcalls\tsyscall\n")
        for k, v in tot.most_common():
            fh.write("%.6f\t%d\t%s\n" % (v, cnt[k], k))

    print("== %s" % os.path.basename(path))
    print("   lines=%d  with-duration=%d  without=%d  distinct-syscalls=%d" % (n, n - unparsed, unparsed, len(tot)))
    for k, v in tot.most_common(15):
        print("   %10.4f s  %8d  %s" % (v, cnt[k], k))
