#!/bin/bash
# Flashes an Orion O6 Android 16 build (the output of build.sh / build.ps1) over USB with fastboot.
# Run it from the build's output folder (it is copied there), or pass --images <dir>.
#
#   ./flash.sh               update, keeps your data (both A/B slots + super)
#   ./flash.sh --wipe        full install like CIX's android_flush_images.sh: partition table, erases
#                            userdata/misc/persist/metadata (ALL DATA IS LOST), asks first (--yes: don't ask)
#   ./flash.sh --no-wait     don't wait for Android to boot
#
# Gets the board into fastboot with "adb reboot bootloader" if Android is running, otherwise waits while
# you start fastboot yourself (UEFI Shell command "fastboot" on the dmod BIOS). Needs adb + fastboot.
set -euo pipefail
WIPE=0; YES=0; WAIT=1; DIR="$(cd "$(dirname "$0")" && pwd)"; FB_TIMEOUT=600; BOOT_TIMEOUT=600
while [[ $# -gt 0 ]]; do
  case "$1" in
    --wipe) WIPE=1 ;; --yes) YES=1 ;; --no-wait) WAIT=0 ;;
    --images) DIR="$2"; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac; shift
done
command -v adb >/dev/null && command -v fastboot >/dev/null || { echo "adb/fastboot not found (install Android platform-tools)" >&2; exit 1; }
cd "$DIR"
LOG="$DIR/flash-$(date +%Y%m%d-%H%M%S).log"
log() { echo "$(date +%T) $*" | tee -a "$LOG"; }
fail() { log "FAILED: $*"; log "log: $LOG"; exit 1; }
fb_serial() { fastboot devices 2>/dev/null | awk '$2=="fastboot"{print $1; exit}'; }
adb_up() { [[ "$(adb get-state 2>/dev/null)" == "device" ]]; }
adb_sh() { adb shell "$@" 2>/dev/null | tr -d '\r'; }

log "flash: images=$DIR wipe=$WIPE"
need=(boot.img init_boot.img vendor_boot.img super.img dtbo-sky1.img vbmeta-sky1.img LinuxLoader.efi.cap)
[[ $WIPE == 1 ]] && need+=(partition-table-default.img partition-table-default-4096.img)
for f in "${need[@]}"; do [[ -f "$f" ]] || fail "missing $f in $DIR"; done
if [[ -f SHA256SUMS ]]; then log "Checking SHA256SUMS ..."; sha256sum -c --quiet SHA256SUMS || fail "checksum mismatch"; log "  all images OK"
else log "WARNING: no SHA256SUMS, images not checked"; fi
if [[ $WIPE == 1 && $YES == 0 ]]; then
  read -r -p "Full install: ALL DATA ON THE BOARD WILL BE ERASED. Type YES to continue: " a; [[ "$a" == "YES" ]] || fail "cancelled"
fi

serial="$(fb_serial)"
if [[ -z "$serial" ]]; then
  if adb_up; then log "Android is running: adb reboot bootloader"; adb reboot bootloader || true
  else log 'Waiting for the board in fastboot mode: in the UEFI Shell type "fastboot" and connect the USB-C data port ...'; fi
  end=$((SECONDS + FB_TIMEOUT))
  until serial="$(fb_serial)"; [[ -n "$serial" ]]; do (( SECONDS < end )) || fail "no fastboot device within ${FB_TIMEOUT}s"; sleep 2; done
fi
log "Fastboot device: $serial"
vars="$(fastboot getvar all 2>&1 || true)"
grep -q 'backdoor:yes' <<<"$vars" && fail 'the board is in DDR ("backdoor") fastboot mode; this script flashes the NVMe install only'

steps=()
if [[ $WIPE == 1 ]]; then
  gpt=partition-table-default.img; grep -q 'block-size: *4096' <<<"$vars" && gpt=partition-table-default-4096.img
  steps+=("flash gpt $gpt" "erase userdata" "erase misc" "erase persist" "erase metadata")
fi
steps+=("flash dtbo_a dtbo-sky1.img" "flash dtbo_b dtbo-sky1.img" "flash s2_a LinuxLoader.efi.cap" "flash s2_b LinuxLoader.efi.cap"
        "flash boot_a boot.img" "flash boot_b boot.img" "flash init_boot_a init_boot.img" "flash init_boot_b init_boot.img"
        "flash vbmeta_a vbmeta-sky1.img" "flash vbmeta_b vbmeta-sky1.img" "flash vendor_boot_a vendor_boot.img"
        "flash vendor_boot_b vendor_boot.img" "flash super super.img")
for s in "${steps[@]}"; do
  log "fastboot $s"
  # shellcheck disable=SC2086
  out="$(fastboot $s 2>&1)" || { echo "$out" >> "$LOG"; fail "fastboot $s"; }
  echo "$out" >> "$LOG"; grep -q FAILED <<<"$out" && fail "fastboot $s"
done
if [[ $WIPE == 1 ]]; then log "fastboot oem cixboot"; fastboot oem cixboot >>"$LOG" 2>&1 || true
else log "fastboot reboot"; fastboot reboot >>"$LOG" 2>&1 || true; fi
[[ $WAIT == 1 ]] || { log "Flashed. Log: $LOG"; exit 0; }

log "Waiting for Android to boot (the first boot after --wipe takes longer) ..."
end=$((SECONDS + BOOT_TIMEOUT)); fb_since=""; fb_reboots=0
while :; do
  (( SECONDS < end )) || fail "Android did not finish booting within ${BOOT_TIMEOUT}s"
  if adb_up; then fb_since=""; [[ "$(adb_sh getprop sys.boot_completed)" == "1" ]] && break
  elif [[ -n "$(fb_serial)" ]]; then
    # After "reboot bootloader" the firmware keeps the fastboot reason for one more boot: reboot again.
    if [[ -z "$fb_since" ]]; then fb_since=$SECONDS
    elif (( SECONDS - fb_since > 10 )); then
      (( fb_reboots < 3 )) || fail "the board keeps booting into fastboot"
      fb_reboots=$((fb_reboots + 1)); log "Board is in fastboot again: fastboot reboot #$fb_reboots"
      fastboot reboot >>"$LOG" 2>&1 || true; fb_since=""; end=$((end + 60)); sleep 5
    fi
  else fb_since=""; fi
  sleep 3
done
log "Android booted (uptime $(adb_sh cut -d. -f1 /proc/uptime) s)"
log "  fingerprint : $(adb_sh getprop ro.build.fingerprint)"
log "  build date  : $(adb_sh getprop ro.build.date)"
log "  kernel      : $(adb_sh uname -v)"
log "  DDR low-power on = $(adb_sh cat /sys/devices/platform/cix_ddr_lp/on) (0 = off, patched image)"
log "  PCIe ASPM policy: $(adb_sh cat /sys/module/pcie_aspm/parameters/policy)"
log "Done. Log: $LOG"
