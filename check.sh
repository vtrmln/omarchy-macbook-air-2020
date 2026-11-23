#!/bin/bash
# Report whether each part of the kit is in place. Changes nothing, needs no sudo.

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_settings
problems=0
check() {
  if eval "$2"; then
    ok "$1"
  else
    bad "$1"
    problems=$((problems + 1))
  fi
}

step "Hardware"
check "Wi-Fi/Bluetooth firmware installed" firmware_installed
check "Wi-Fi interface present" 'ls /sys/class/net/*/wireless >/dev/null 2>&1'
check "Bluetooth controller present" '[[ -e /sys/class/bluetooth/hci0 ]]'
check "Fn keys: media keys first (now and at boot)" '[[ $(cat /sys/module/hid_apple/parameters/fnmode 2>/dev/null) == "1" ]] && cmp -s "$kit/system/hid_apple.conf" "$etc/modprobe.d/hid_apple.conf"'
check "Lid-closed wake-loop fix enabled" 'systemctl is-enabled --quiet "$service" && cmp -s "$kit/system/$service" "$etc/systemd/system/$service"'
check "Hardware clock correct" rtc_ok

step "Keyboard"
check "Keyboard $KB_LAYOUT ($KB_VARIANT)" kb_configured

step "Fun"
check "Flying pigs installed" '[[ -d $HOME/.config/omarchy/plugins/critters.flying-pigs ]] && grep -q flying_pigs "$hypr/bindings.lua"'
check "Goose installed" '[[ -d $HOME/.config/omarchy/plugins/critters.goose ]] && grep -q critters.goose "$hypr/bindings.lua"'
check "Goose follow mode (hypr-caret) built" '[[ -f $HOME/.local/share/omarchy-critters/hypr-caret.so ]]'

echo
if ((problems)); then
  printf '\e[33m%d item(s) not in place.\e[0m Run ./setup.sh to fix them.\n' "$problems"
  exit 1
fi
printf '\e[32mEverything is in place.\e[0m\n'
