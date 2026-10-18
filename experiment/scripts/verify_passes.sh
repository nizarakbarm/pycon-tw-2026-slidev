#!/bin/bash
# Cross-pass verification: delivery + [RUSAGE] summary across all three passes.
# Usage: bash /root/experiment/scripts/verify_passes.sh
set -u
R=/root/experiment/results

hdr() { printf "\n=== %s\n" "$1"; }

# audit <label> <glob> -- count [SUMMARY]==N+1 per arm
audit() {
  local label="$1" glob="$2" ok=0 bad=0 miss=0 g n s
  for g in $glob; do
    [ -f "$g" ] || continue
    n=$(basename "$g" | sed -n 's/.*N\([0-9]*\)_2026.*/\1/p')
    [ -z "$n" ] && continue
    s=$(grep -a '\[SUMMARY\]' "$g" 2>/dev/null | sed -n 's/.*map: *//p')
    if [ -z "$s" ]; then miss=$((miss+1)); printf "  MISSING  %s\n" "$(basename "$g")"; continue; fi
    if [ "$s" = "$((n+1))" ]; then ok=$((ok+1))
    else bad=$((bad+1)); printf "  FAIL     %-52s got=%s want=%s\n" "$(basename "$g")" "$s" "$((n+1))"; fi
  done
  echo "  --> arms ok=$ok  fail=$bad  missing=$miss"
}

# per-pass log glob: each pass has ONE log naming convention, so no double-match
hdr "PASS 1 — unprofiled  ($R/unprofiled)"
audit unprofiled "$R/unprofiled/unprofiled_*.log"

hdr "PASS 2 — straceT  ($R/straceT)"
audit straceT "$R/straceT/*.prog.log"

hdr "PASS 3 — perfrecord  ($R/perfrecord)"
audit perfrecord "$R/perfrecord/perfrec_*.log"

hdr "[RUSAGE] at 2M — self vs children maxrss"
printf "  %-18s %-5s %14s %14s\n" variant impl "self_maxrss" "children_maxrss"
rusage_row() {   # <file>
  local g="$1" v i r sm cm
  v=$(basename "$g" | sed -n 's/.*\(map1_count\|ablA_empty\|ablB_print_const\).*/\1/p')
  i=$(basename "$g" | sed -n 's/.*_\(bcc\|pbpf\)_N.*/\1/p')
  r=$(grep -a '\[RUSAGE\] after-summary' "$g" 2>/dev/null | head -1)
  [ -z "$r" ] && return
  # Split on '|': left = self, right = children. A greedy .* would take the LAST
  # maxrss (children's) for both columns -- parse each half separately.
  sm=$(printf '%s' "$r" | awk -F'|' '{n=split($1,a," "); for(i=1;i<=n;i++) if(a[i] ~ /^maxrss=/){sub(/maxrss=/,"",a[i]); sub(/KB/,"",a[i]); print a[i]; exit}}')
  cm=$(printf '%s' "$r" | awk -F'|' '{if(NF<2) exit; n=split($2,a," "); for(i=1;i<=n;i++) if(a[i] ~ /^maxrss=/){sub(/maxrss=/,"",a[i]); sub(/KB/,"",a[i]); print a[i]; exit}}')
  printf "  %-18s %-5s %14s %14s\n" "$v" "$i" "${sm:-?}KB" "${cm:-?}KB"
}
echo "  -- unprofiled";  for g in "$R"/unprofiled/*N2000000*.log;      do [ -f "$g" ] && rusage_row "$g"; done
echo "  -- straceT";     for g in "$R"/straceT/*N2000000*.prog.log;    do [ -f "$g" ] && rusage_row "$g"; done
echo "  -- perfrecord";  for g in "$R"/perfrecord/*N2000000*.log;      do [ -f "$g" ] && rusage_row "$g"; done

hdr "artefact counts"
for pass in unprofiled straceT perfrecord; do
  printf "  %-12s files=%-6s du=%s\n" "$pass" "$(ls "$R/$pass" 2>/dev/null | wc -l)" "$(du -sh "$R/$pass" 2>/dev/null | cut -f1)"
done
printf "\n  TOTAL results tree: %s\n" "$(du -sh "$R" 2>/dev/null | cut -f1)"
