#!/usr/bin/env bash
# Find what wakes the MacBook from deep sleep while the lid is closed.
#
#   sudo ./wake-test.sh tables          copy ACPI tables here so GPEs can be mapped to devices
#   sudo ./wake-test.sh test [DEV ...]  lid-closed test; DEVs (e.g. ARPT) lose wake permission
#                                       for the run only, and are restored when it ends
#
# Results land next to this script, owned by you. Nothing is changed permanently.
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
owner="${SUDO_USER:-$USER}"
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo $0 $*"; exit 1; }

gpe_snapshot() {
  for f in /sys/firmware/acpi/interrupts/{ff_*,gpe[0-9A-F][0-9A-F]}; do
    printf '%s %s\n' "${f##*/}" "$(awk '{print $1}' "$f")"
  done
}
asleep_seconds() {
  python3 -I -c 'import time; print(f"{time.clock_gettime(time.CLOCK_BOOTTIME) - time.clock_gettime(time.CLOCK_MONOTONIC):.1f}")'
}

cmd_tables() {
  mkdir -p "$dir/acpi"
  for t in /sys/firmware/acpi/tables/DSDT /sys/firmware/acpi/tables/SSDT*; do
    cp "$t" "$dir/acpi/${t##*/}.dat"
  done
  cp /proc/acpi/wakeup "$dir/acpi/wakeup.txt"
  chown -R "$owner:" "$dir/acpi"
  echo "Copied $(ls "$dir/acpi" | wc -l) files to $dir/acpi"
  if ! command -v iasl >/dev/null; then
    echo "Installing acpica (provides iasl, the ACPI table decompiler)..."
    pacman -S --needed acpica
  fi
}

# Globals, not locals: the EXIT trap runs after cmd_test returns, when its locals are gone.
toggled=()
out=""
restore() {
  local d
  for d in "${toggled[@]}"; do
    if grep -qE "^$d\s.*\*disabled" /proc/acpi/wakeup; then
      echo "$d" >/proc/acpi/wakeup && echo "Wake restored: $d"
    fi
  done
  [[ -w /sys/power/pm_debug_messages ]] && echo 0 >/sys/power/pm_debug_messages
  [[ -n $out ]] && chown -R "$owner:" "$out" 2>/dev/null
  true
}

cmd_test() {
  local d
  out="$dir/run-$(date +%m%d-%H%M%S)${1:+-$(IFS=-; echo "$*")}"
  mkdir -p "$out"
  trap restore EXIT

  for d in "$@"; do
    if grep -qE "^$d\s.*\*enabled" /proc/acpi/wakeup; then
      echo "$d" >/proc/acpi/wakeup && toggled+=("$d")
      echo "Wake disabled for this run: $d"
    else
      echo "Skipping $d: not listed as wake-enabled in /proc/acpi/wakeup"
    fi
  done
  [[ -w /sys/power/pm_debug_messages ]] && echo 1 >/sys/power/pm_debug_messages

  cp /proc/acpi/wakeup "$out/wakeup-during.txt"
  gpe_snapshot >"$out/gpe-before.txt"
  local start asleep0 t0
  start="$(date '+%F %T')"; asleep0="$(asleep_seconds)"; t0=$(date +%s)

  echo
  echo ">>> Close the lid now. Leave it closed for about 2 minutes, then open it,"
  echo ">>> unlock, and press Enter here."
  read -r

  local t1 asleep1 suspends
  t1=$(date +%s); asleep1="$(asleep_seconds)"
  gpe_snapshot >"$out/gpe-after.txt"
  journalctl -k -b --no-pager -o short-iso --since "$start" >"$out/kernel.log"
  journalctl -b --no-pager -o short-iso --since "$start" -u systemd-logind >"$out/logind.log"
  suspends=$(grep -c 'PM: suspend entry' "$out/kernel.log" || true)

  {
    echo "run:        $start  ($((t1 - t0))s wall clock)"
    echo "disabled:   ${toggled[*]:-none}"
    echo "suspends:   $suspends"
    python3 -I -c "
a=float('$asleep1')-float('$asleep0'); n=int('$suspends') or 1
print(f'asleep:     {a:.1f}s total, {a/n:.1f}s per suspend')"
    echo "pm_wakeup_irq: $(cat /sys/power/pm_wakeup_irq 2>/dev/null || echo none)"
    echo "gpe deltas:"
    join "$out/gpe-before.txt" "$out/gpe-after.txt" | awk '$3!=$2 {printf "  %s +%d\n", $1, $3-$2}'
    echo "lid events:"
    grep -E 'Lid (opened|closed)' "$out/logind.log" | sed 's/^/  /' || echo "  none"
    echo "wake-related kernel lines:"
    grep -iE 'wakeup|wake up|waking|GPE|PME|resume from|ACPI: EC' "$out/kernel.log" |
      grep -vE 'efivarfs' | sed 's/^[^ ]* [^ ]* kernel: //' | sort | uniq -c | sort -rn | head -25 | sed 's/^/  /'
  } | tee "$out/report.txt"
  echo
  echo "Saved to $out"
}

case "${1:-}" in
  tables) cmd_tables ;;
  test) shift; cmd_test "$@" ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac
