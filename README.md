# Omarchy on the MacBook Air 2020 (Intel)

Fixes that make [Omarchy](https://omarchy.org/) work properly on the **MacBook Air 2020 with an Intel CPU** (A2179, `MacBookAir9,1`, T2 chip, Broadcom BCM4377 Wi-Fi), plus an optional goose and flying pigs. One command applies everything after a fresh install or a factory reset, and running it again is always safe.

Tested on Omarchy 4.5 (kernel `linux-t2` 7.2) on one A2179. It's shared as-is: it changes only the files listed below, and backs up every file it edits first.

## What it fixes

| Problem | Fix |
|---|---|
| **No Wi-Fi or Bluetooth after a single-boot install.** The firmware fetcher reads it from macOS, which the installer has wiped ([#16287](https://github.com/omacom/omarchy/issues/16287)). | Installs the firmware from a `firmware.tar` you make yourself (see below). |
| **With the lid closed, the Mac suspends and wakes every ~33 s all night.** The Wi-Fi card raises a wake ~2 s into every deep sleep, and its driver re-enables that wake on every resume ([#19638](https://github.com/omacom/omarchy/issues/19638)). | `macbook-wifi-no-wakeup.service` turns the card's wake off right before every sleep. You only lose Wake-on-WLAN; the lid, keyboard, power button and charger still wake it. |
| **The top row gives F1–F12 instead of brightness and volume.** Omarchy's installer forces `fnmode=2` on every machine ([#7343](https://github.com/omacom/omarchy/pull/7343)). | Media keys first, like macOS (`hid_apple fnmode=1`), applied from boot. Hold Fn for F1–F12. |
| **The hardware clock reads 1970 after an SMC reset.** | Writes the network time back to it when it's off. |
| **French keyboard symbols don't match the keycaps.** The default `fr` layout is for PC keyboards ([discussion](https://github.com/omacom/omarchy/discussions/19410)). | Sets `fr` with the `mac` variant. Change `personal/settings.env` for another layout. |

## Before you start: the Wi-Fi firmware

The firmware belongs to Apple, so it isn't in this repo. Make it once and keep it on a USB stick:

- **On any Mac:** run `bash firmware.sh` from the [t2linux firmware guide](https://wiki.t2linux.org/guides/wifi-bluetooth/) and choose to create a tarball.
- **Without another Mac:** the same script can download a macOS recovery image from Apple and extract the firmware, but that needs a temporary internet connection on the laptop (USB tethering or a USB-C Ethernet adapter).

Put the resulting `firmware.tar` in `system/`. If you make `system/firmware.tar.sha256` with `sha256sum firmware.tar > firmware.tar.sha256`, setup also checks the archive isn't damaged.

## After a fresh install

1. Install Omarchy, log in, and copy this folder (with `system/firmware.tar`) to your home folder.
2. Open a terminal (Super + Enter) in the folder and run:
   ```bash
   bash setup.sh
   ```
   Enter your password when asked. It applies the hardware fixes, the keyboard layout and the critters. No internet is needed if `fun/omarchy-critters` is already in the folder; otherwise setup downloads it, so connect to Wi-Fi first and run `bash setup.sh fun` again.
3. Reboot once. `bash check.sh` then shows a green line for every item.

`bash setup.sh system`, `bash setup.sh keyboard` and `bash setup.sh fun` run one part only. On a different Mac model, setup warns and asks before changing anything.

## The fun part

`bash setup.sh fun` installs [omarchy-critters](https://github.com/vtrmln/omarchy-critters):

- **Super + Ctrl + Alt + P:** pig mode. Every left click launches a flapping winged pig.
- **Super + Ctrl + Alt + G:** a pixel goose on the window you're typing in. It walks as you type, or follows your text cursor.

## If something goes wrong

- **It wakes with the lid closed again:** `sudo bash tools/wake-test.sh test` runs one lid-closed test and reports how many times the Mac slept and which wake signals fired. Add device names from `/proc/acpi/wakeup` (for example `ARPT`) to block them for that run only. This is the test that found the Wi-Fi card. Plugging in the charger always wakes the Mac; that's normal.
- Every file setup edits gets a `.bak.<timestamp>` copy next to it.

## What it changes

| File | Why |
|---|---|
| `/lib/firmware/brcm/*` | Wi-Fi and Bluetooth firmware from `firmware.tar` |
| `/etc/modprobe.d/hid_apple.conf` | Fn mode, then a boot-image rebuild with `limine-mkinitcpio` |
| `/etc/systemd/system/macbook-wifi-no-wakeup.service` | The wake-loop fix, enabled for `sleep.target` |
| the hardware clock | Only when it's more than 2 minutes off and network time is synced |
| `~/.config/hypr/input.lua` | Keyboard layout |
| omarchy-critters' files | See its README |

## License

MIT, see [LICENSE](LICENSE).
