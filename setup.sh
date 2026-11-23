#!/bin/bash
# Make a fresh Omarchy install work on this MacBook Air (A2179, 2020, T2), and
# bring back the flying pigs and the goose.
#
#   ./setup.sh            everything, in order
#   ./setup.sh system     hardware fixes only (needs sudo, works offline)
#   ./setup.sh keyboard   French Mac keyboard layout
#   ./setup.sh fun        flying pigs and the goose
#
# Run it as your normal user from a terminal inside the desktop; it asks for
# your password when it needs it. Every step checks first and skips what is
# already done, so running it again is safe.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

part=${1:-all}
case $part in
  all | system | keyboard | fun) ;;
  *)
    sed -n '2,12p' "$0"
    exit 1
    ;;
esac
((EUID != 0)) || die "Run this as your normal user, not with sudo. It asks for your password itself."

model=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)
if [[ $model != "$expected_model" && $part != "fun" ]]; then
  printf '\e[33m!\e[0m This kit is for the %s (MacBook Air 2020, Intel); this machine is %s.\n' "$expected_model" "$model"
  read -rp "  Continue anyway? [y/N] " answer
  [[ ${answer,,} == "y" ]] || exit 1
fi

need_reboot=0

setup_system() {
  local need_initramfs=0
  step "1. Hardware fixes (sudo)"
  sudo -v || die "This part needs your password."

  # Wi-Fi and Bluetooth firmware. The installer can't fetch it once macOS is wiped.
  if firmware_installed; then
    ok "Wi-Fi/Bluetooth firmware already installed"
  elif [[ ! -f $kit/system/firmware.tar ]]; then
    die "Wi-Fi firmware is missing and system/firmware.tar isn't here. Make it on any Mac with https://wiki.t2linux.org/tools/firmware.sh (\"create a tarball\"), put it in system/, and run this again. See README.md."
  else
    if [[ -f $kit/system/firmware.tar.sha256 ]]; then
      (cd "$kit/system" && sha256sum --quiet -c firmware.tar.sha256) || die "system/firmware.tar is damaged (checksum mismatch)."
    fi
    if tar -tf "$kit/system/firmware.tar" | grep -qE '^/|\.\./|/'; then
      die "system/firmware.tar contains unexpected paths; refusing to extract."
    fi
    sudo mkdir -p "$fw_dir"
    sudo tar -xf "$kit/system/firmware.tar" -C "$fw_dir" --no-same-owner
    sudo modprobe -r brcmfmac_wcc brcmfmac 2>/dev/null || true
    sudo modprobe brcmfmac
    sudo modprobe -r hci_bcm4377 2>/dev/null || true
    sudo modprobe hci_bcm4377
    ok "Wi-Fi/Bluetooth firmware installed and drivers reloaded"
  fi

  # Fn keys: media keys first, like macOS. Omarchy's installer sets F-keys first.
  if cmp -s "$kit/system/hid_apple.conf" "$etc/modprobe.d/hid_apple.conf"; then
    ok "Fn keys already set to media keys first"
  else
    sudo install -m 644 "$kit/system/hid_apple.conf" "$etc/modprobe.d/hid_apple.conf"
    need_initramfs=1
    ok "Fn keys set to media keys first"
  fi
  if [[ $(cat /sys/module/hid_apple/parameters/fnmode 2>/dev/null) != "1" ]]; then
    echo 1 | sudo tee /sys/module/hid_apple/parameters/fnmode >/dev/null
  fi

  # Wi-Fi card wakes the Mac 2 s into every sleep; this turns that off before each sleep.
  if cmp -s "$kit/system/$service" "$etc/systemd/system/$service"; then
    ok "Lid-closed wake-loop fix already installed"
  else
    sudo install -m 644 "$kit/system/$service" "$etc/systemd/system/$service"
    sudo systemctl daemon-reload
    ok "Lid-closed wake-loop fix installed"
  fi
  systemctl is-enabled --quiet "$service" 2>/dev/null || sudo systemctl enable --quiet "$service"
  # The boot-only udev rule from the first attempt is superseded by the service.
  sudo rm -f "$etc/udev/rules.d/90-macbook-wifi-no-wakeup.rules"

  # Hardware clock: an SMC reset sets it back to 1970.
  if rtc_ok; then
    ok "Hardware clock is correct"
  elif [[ $(timedatectl show -p NTPSynchronized --value 2>/dev/null) == "yes" ]]; then
    sudo hwclock --systohc
    ok "Hardware clock corrected from network time"
  else
    warn "Hardware clock is off; connect to the internet and run ./setup.sh system again to correct it"
  fi

  if ((need_initramfs)); then
    echo "  Rebuilding the boot image so the Fn setting applies from boot..."
    if command -v limine-mkinitcpio >/dev/null; then
      sudo limine-mkinitcpio >/dev/null
    else
      sudo mkinitcpio -P >/dev/null
    fi
    need_reboot=1
    ok "Boot image rebuilt"
  fi
}

setup_keyboard() {
  step "2. Keyboard"
  load_settings
  if kb_configured; then
    ok "Keyboard already $KB_LAYOUT ($KB_VARIANT)"
    return
  fi
  [[ -f $hypr/input.lua ]] || die "$hypr/input.lua not found; log in to the desktop once first."
  cp "$hypr/input.lua" "$hypr/input.lua.bak.$(date +%s)"
  cat >>"$hypr/input.lua" <<EOF

-- Keyboard layout for this MacBook (added by macbook-air-kit).
hl.config({
  input = {
    kb_layout = "$KB_LAYOUT",
    kb_variant = "$KB_VARIANT",
    kb_options = "$KB_OPTIONS",
  },
})
EOF
  if in_session; then
    hyprctl reload >/dev/null
    errors=$(hyprctl configerrors 2>/dev/null || true)
    [[ -z ${errors//[[:space:]]/} ]] || {
      bad "Hyprland reports config errors:"
      echo "$errors"
    }
  fi
  ok "Keyboard set to $KB_LAYOUT ($KB_VARIANT)"
}

setup_fun() {
  step "3. Flying pigs and the goose"
  in_session || die "Run this part from a terminal inside the desktop."
  if [[ ! -f $kit/fun/omarchy-critters/install.sh ]]; then
    git clone --quiet "$critters_repo" "$kit/fun/omarchy-critters" ||
      die "Couldn't download the critters from $critters_repo. Connect to the internet and run ./setup.sh fun again."
  fi
  bash "$kit/fun/omarchy-critters/install.sh"
  omarchy-restart-shell >/dev/null 2>&1 || warn "Couldn't restart the Omarchy shell; log out and back in"
}

case $part in
  all)
    setup_system
    setup_keyboard
    setup_fun
    ;;
  system) setup_system ;;
  keyboard) setup_keyboard ;;
  fun) setup_fun ;;
esac

bash "$kit/check.sh" || true
((need_reboot)) && printf '\n\e[1mReboot once to finish.\e[0m\n'
exit 0
