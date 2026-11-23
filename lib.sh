# Shared helpers for setup.sh and check.sh. Sourced, not run.

kit="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hypr="$HOME/.config/hypr"
fw_dir=${KIT_ROOT:-}/lib/firmware/brcm
etc=${KIT_ROOT:-}/etc
service=macbook-wifi-no-wakeup.service

ok() { printf '  \e[32m✔\e[0m %s\n' "$1"; }
warn() { printf '  \e[33m!\e[0m %s\n' "$1"; }
bad() { printf '  \e[31m✘\e[0m %s\n' "$1"; }
die() {
  printf '\e[31m✘ %s\e[0m\n' "$1" >&2
  exit 1
}
step() { printf '\n\e[1m%s\e[0m\n' "$1"; }

in_session() { [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; }

# Copy $1 over $2, keeping a timestamped backup of $2 if it existed.
replace_with_backup() {
  if [[ -f $2 ]]; then
    cp "$2" "$2.bak.$(date +%s)"
  fi
  mkdir -p "$(dirname "$2")"
  cp "$1" "$2"
}

critters_repo=${KIT_CRITTERS_REPO:-https://github.com/vtrmln/omarchy-critters.git}
expected_model=MacBookAir9,1

# With the archive at hand, every file in it must be installed. Without it
# (the published repo doesn't ship Apple's firmware), any Apple BCM4377 Wi-Fi
# firmware counts.
firmware_installed() {
  local f
  if [[ -f $kit/system/firmware.tar ]]; then
    while read -r f; do
      [[ -f $fw_dir/$f ]] || return 1
    done < <(tar -tf "$kit/system/firmware.tar")
  else
    compgen -G "$fw_dir/brcmfmac4377b3-pcie.apple,*.bin" >/dev/null
  fi
}

rtc_ok() {
  local rtc now
  rtc=$(cat /sys/class/rtc/rtc0/since_epoch 2>/dev/null) || return 1
  now=$(date +%s)
  ((rtc > now - 120 && rtc < now + 120))
}

kb_configured() {
  grep -qE "kb_layout = \"$KB_LAYOUT\"" "$hypr/input.lua" 2>/dev/null &&
    grep -qE "kb_variant = \"$KB_VARIANT\"" "$hypr/input.lua" 2>/dev/null
}

load_settings() {
  [[ -f $kit/personal/settings.env ]] || die "personal/settings.env is missing from the kit."
  # shellcheck source=/dev/null
  source "$kit/personal/settings.env"
}
