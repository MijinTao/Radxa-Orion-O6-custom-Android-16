#!/bin/bash
# Builds Android 16 for the Radxa Orion O6 from CIX's Android 16 tree, applies the patches in
# /opt/android-patches, verifies the result and writes it to /out. Runs inside the Docker image defined by
# ./Dockerfile; start it with ./build.sh or .\build.ps1 (see README.md).
#
# Environment variables:
#   BOARD           O6 (O6N: not available, CIX's Android 16 tree has no O6N device)   (default: O6)
#   VARIANT         userdebug or user                                                    (default: userdebug)
#   PATCHES         1 = apply the patches, 0 = CIX's tree as is ("stock")               (default: 1)
#   MANIFEST        pinned = the exact revisions the patches were made and tested on
#                   (manifest/orion-o6-pinned.xml); latest = the current head of
#                   MANIFEST_BRANCH (the patches may then no longer apply)              (default: pinned)
#   MANIFEST_URL    CIX's manifest repository       (default: https://github.com/cixtech/android-manifest)
#   MANIFEST_BRANCH                                 (default: cix_android16_2025q3_dev)
#   SYNC            1 = run "repo sync" even if the source is already there            (default: 0)
#   JOBS            parallel build jobs                                                  (default: all CPUs)
#   SYNC_JOBS       parallel download jobs                                               (default: 8)
#   WIFI_COUNTRY    two-letter Wi-Fi country code (patch 0001 sets IT)                  (default: from the patch)
#   SKIP_PATCHES    patch numbers to leave out, e.g. "0014" (build.ps1 -VerboseConsole /
#                   build.sh --verbose-console set 0014)                                (default: none)
#   HOST_UID/HOST_GID  build as this user id and own the output (Linux hosts)
#
# Volumes:
#   /work  persistent source checkout + build output (about 250 GB, re-used between builds)
#   /out   output folder:
#            <BOARD>-Android16-<variant>[-stock]/             images + flash scripts
#            <BOARD>-Android16-<variant>[-stock]-build-info/  how it was built

set -euo pipefail

BOARD="${BOARD:-O6}"
VARIANT="${VARIANT:-userdebug}"
PATCHES="${PATCHES:-1}"
MANIFEST="${MANIFEST:-pinned}"
MANIFEST_URL="${MANIFEST_URL:-https://github.com/cixtech/android-manifest}"
MANIFEST_BRANCH="${MANIFEST_BRANCH:-cix_android16_2025q3_dev}"
SYNC="${SYNC:-0}"
JOBS="${JOBS:-$(nproc)}"
SYNC_JOBS="${SYNC_JOBS:-8}"
WIFI_COUNTRY="${WIFI_COUNTRY:-}"
SKIP_PATCHES="$(echo "${SKIP_PATCHES:-}" | tr ',' ' ')"
PATCH_DIR=/opt/android-patches
PINNED=/opt/android-manifest/orion-o6-pinned.xml
SRC=/work/cix-android16

log() { echo -e "\n\033[1;36m==> $*\033[0m"; }
die() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

# --- run as the unprivileged "builder" user (re-exec once) --------------------------------------------
if [[ "$(id -u)" == "0" ]]; then
  if [[ -n "${HOST_UID:-}" && "$HOST_UID" != "0" && "$HOST_UID" != "$(id -u builder)" ]]; then
    groupmod -o -g "${HOST_GID:-$HOST_UID}" builder && usermod -o -u "$HOST_UID" builder
    chown -R builder:builder /home/builder
  fi
  chown builder:builder /work /out 2>/dev/null || true
  [[ -d "$SRC" ]] && [[ "$(stat -c %u "$SRC")" != "$(id -u builder)" ]] && \
    die "/work/cix-android16 belongs to another user id ($(stat -c %u "$SRC")); use the same HOST_UID as before or a new source volume"
  exec setpriv --reuid=builder --regid=builder --init-groups env HOME=/home/builder USER=builder "$0" "$@"
fi

case "$BOARD" in
  O6) PRODUCT=sky1_orion_o6 ;;
  O6N) die "the Orion O6N isn't supported: CIX's Android 16 tree only has the O6 product (sky1_orion_o6),
       there is no O6N device configuration or device tree in it, and nothing here was tested on an O6N.
       For the O6N use Radxa's Android 14 release (see README.md, 'Orion O6N')." ;;
  *) die "BOARD must be O6 or O6N (got '$BOARD')" ;;
esac
case "$VARIANT" in userdebug|user) ;; *) die "VARIANT must be userdebug or user (got '$VARIANT')" ;; esac
case "$PATCHES" in 0|1) ;; *) die "PATCHES must be 1 or 0 (got '$PATCHES')" ;; esac
case "$MANIFEST" in pinned|latest) ;; *) die "MANIFEST must be pinned or latest (got '$MANIFEST')" ;; esac
for n in $SKIP_PATCHES; do [[ "$n" =~ ^[0-9]{4}$ ]] || die "SKIP_PATCHES: '$n' is not a 4-digit patch number"; done
skipped() { local n; for n in $SKIP_PATCHES; do [[ "$1" == "$n"-* ]] && return 0; done; return 1; }
if [[ "$PATCHES" == "1" && -z "$(find "$PATCH_DIR" -name '*.patch' 2>/dev/null | head -1)" ]]; then
  die "PATCHES=1 but no patches found in $PATCH_DIR"
fi

PKG_NAME="${BOARD}-Android16-${VARIANT}"
[[ "$PATCHES" == "0" ]] && PKG_NAME="${PKG_NAME}-stock"
PKG="/out/${PKG_NAME}"
INFO="/out/${PKG_NAME}-build-info"

git config --global user.name  "builder"
git config --global user.email "builder@localhost"
git config --global color.ui false
git config --global --add safe.directory '*'
git config --global advice.detachedHead false
export GIT_TERMINAL_PROMPT=0

# --- 1. source ------------------------------------------------------------------------------------------
log "1/6 Source: CIX Android 16 ($MANIFEST manifest) in $SRC"
mkdir -p "$SRC"; cd "$SRC"
want="$MANIFEST_URL $MANIFEST_BRANCH $MANIFEST $( [[ $MANIFEST == pinned ]] && sha256sum "$PINNED" | cut -c1-16 )"
have="$(cat /work/.synced 2>/dev/null || true)"
if [[ ! -d .repo ]]; then
  repo init -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH" --git-lfs --depth=1 --no-clone-bundle </dev/null
fi
if [[ "$MANIFEST" == "pinned" ]]; then
  cp "$PINNED" .repo/manifests/orion-o6-pinned.xml
  repo init -m orion-o6-pinned.xml </dev/null
else
  repo init -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH" -m default.xml </dev/null
fi
if [[ "$SYNC" == "1" || "$want" != "$have" ]]; then
  echo "Syncing (first time: ~90 GB download, takes hours) ..."
  repo sync -c --no-tags --no-clone-bundle --fail-fast --retry-fetches=3 -j"$SYNC_JOBS" </dev/null
  echo "$want" > /work/.synced
else
  echo "Re-using the synced source (SYNC=1 to sync again)"
fi

# --- 2. reset + patch -----------------------------------------------------------------------------------
log "2/6 Patches: $( [[ $PATCHES == 1 ]] && echo applying || echo none, stock build )"
# Projects the patches touch are reset to the manifest revision first, so a rebuild starts clean and a
# stock build has no leftovers. Includes files a patch added (git clean).
mapfile -t PROJECTS < <(cd "$PATCH_DIR" && find . -name '*.patch' -printf '%h\n' | sed 's#^\./##' | sort -u)
for p in "${PROJECTS[@]}"; do
  [[ -d "$SRC/$p/.git" || -f "$SRC/$p/.git" ]] || die "patches/$p: no such project in the tree"
  git -C "$SRC/$p" reset -q --hard && git -C "$SRC/$p" clean -fdq
done
if [[ "$PATCHES" == "1" ]]; then
  # Apply in patch-number order (one number = one fix, possibly in several projects)
  while read -r name rel; do
    proj="$(dirname "$rel")"
    if skipped "$name"; then echo "skipping $rel  (SKIP_PATCHES)"; continue; fi
    echo "applying $rel  (sha256 $(sha256sum "$PATCH_DIR/$rel" | cut -c1-16))"
    git -C "$SRC/$proj" apply --whitespace=nowarn "$PATCH_DIR/$rel" \
      || die "patch $rel does not apply (tree changed? try MANIFEST=pinned)"
  done < <(cd "$PATCH_DIR" && find . -name '*.patch' -printf '%f %P\n' | sort)
  if [[ -n "$WIFI_COUNTRY" ]]; then
    [[ "$WIFI_COUNTRY" =~ ^[A-Z]{2}$ ]] || die "WIFI_COUNTRY must be two capital letters (got '$WIFI_COUNTRY')"
    sed -i -E "s/(androidboot\.wificountrycode=)[A-Z]{2}\b/\1${WIFI_COUNTRY}/" device/cix/sky1/sky1_orion_o6/BoardConfig.mk
    echo "Wi-Fi country code: $WIFI_COUNTRY"
  fi
  for p in "${PROJECTS[@]}"; do git -C "$SRC/$p" status --short --untracked-files=all | sed "s#^#  $p: #"; done
fi

# --- 3. build -------------------------------------------------------------------------------------------
log "3/6 Building ${PRODUCT}-bp2a-${VARIANT} with $JOBS jobs - this takes hours the first time"
OUTDIR="$SRC/out/target/product/$PRODUCT"
rm -rf "$OUTDIR/images"
set +u
source build/envsetup.sh >/dev/null
lunch "${PRODUCT}-bp2a-${VARIANT}" >/dev/null || die "lunch ${PRODUCT}-bp2a-${VARIANT} failed"
set -u
rc=0
./build-android.sh -j"$JOBS" > /work/build.log 2>&1 || rc=$?
tail -n 25 /work/build.log
if [[ "$rc" == "0" ]] && ! grep -q "build completed successfully" /work/build.log; then rc=1; fi
[[ "$rc" == "0" ]] || { grep -n -E ' error:|FAILED:|ninja: build stopped' /work/build.log | head -30; die "build failed (exit $rc), full log: /work/build.log in the source volume"; }

# --- 4. verify ------------------------------------------------------------------------------------------
log "4/6 Verifying"
IMAGES=(boot.img init_boot.img vendor_boot.img super.img dtbo-sky1.img vbmeta-sky1.img LinuxLoader.efi.cap
        partition-table-default.img partition-table-default-4096.img)
for f in "${IMAGES[@]}"; do
  [[ -s "$OUTDIR/images/$f" ]] || die "missing image $f"
  printf '  %-34s %s\n' "$f" "$(stat -c %s "$OUTDIR/images/$f")"
done
KCONF="$OUTDIR/obj/KERNEL_OBJ/.config"
if [[ "$PATCHES" == "1" ]]; then
  check() {
    if skipped "${1%% *}-"; then printf '  %-34s skipped\n' "$1"; return; fi
    if eval "$2"; then printf '  %-34s yes\n' "$1"; else printf '  %-34s NO\n' "$1"; ok=0; fi
  }
  ok=1
  check "0002 reboot-to-fastboot driver"  "grep -q 'cix-reboot-reason.o' vendor/cix_opensource/kernel/drivers/soc/cix/Makefile"
  check "0003 DDR LP off (kernel)"        "grep -q ORION_O6_DDRLP_OFF vendor/cix_opensource/kernel/drivers/soc/cix/cix-ddr-lp.c"
  check "0004 btusb module in kernel"     "grep -q '^CONFIG_BT_HCIBTUSB=m' '$KCONF'"
  check "0004 BT firmware in vendor"      "[[ -s '$OUTDIR/vendor/firmware/rtl_bt/rtl8852bu_fw.bin' ]]"
  check "0005 mouse-as-touch in input"    "grep -q 'Mouse Click As Touch' '$OUTDIR/system/lib64/libinputflinger.so'"
  check "0006 kernel ASPM performance"    "grep -q '^CONFIG_PCIEASPM_PERFORMANCE=y' '$KCONF'"
  check "0007 mailbox FIFO bound"         "grep -q 'i < CIX_MBOX_MSG_LEN' vendor/cix_opensource/kernel/drivers/mailbox/cix-mailbox.c"
  check "0008 reset pulse timing"         "grep -q SKY1_RESET_PULSE_MIN_US vendor/cix_opensource/kernel/drivers/reset/reset-sky1.c"
  check "0009 i2c shutdown handler"       "grep -q cdns_i2c_shutdown vendor/cix_opensource/kernel/drivers/i2c/busses/i2c-cadence.c"
  check "0010 spi RX-before-TX"           "grep -q 'Drain RX before refilling TX' vendor/cix_opensource/kernel/drivers/spi/spi-cadence.c"
  check "0011 cdnsp role/UAF fixes"       "grep -q '!role_changed && cdns->roles' vendor/cix_opensource/kernel/drivers/usb/cdns3/core.c"
  check "0012 scmi perf allowed ops"      "grep -q '!dom->info.set_perf' vendor/cix_opensource/kernel/drivers/firmware/arm_scmi/perf.c"
  check "0013 dma350 hw cyclic position"  "grep -q cyc_cmd_addr vendor/cix_opensource/kernel/drivers/dma/arm_dma350.c"
  check "0014 quiet serial console"       "grep -q '^BOARD_KERNEL_CMDLINE += loglevel=4' device/cix/sky1/sky1_orion_o6/BoardConfig.mk"
  check "0015 hda verb-timeout recovery"  "grep -q snd_hdac_bus_reset_response_counter vendor/cix_opensource/kernel/sound/hda/hdac_bus.c"
  check "0016 rts5453 shared-irq fixes"   "grep -q 'u8 clear_irq, bool force' vendor/cix_opensource/kernel/drivers/usb/typec/rts5453.c"
  check "0017 usb d3/suspend fixes"       "grep -q clks_gated vendor/cix_opensource/kernel/drivers/usb/cdns3/cdnsp-sky1.c"
  check "0018 no app display-mode switch" "grep -q 'must mean never' frameworks/base/services/core/java/com/android/server/display/mode/DisplayModeDirector.java"
  [[ "$ok" == "1" ]] || die "a patch feature is missing from the build"
fi

# --- 5. output ------------------------------------------------------------------------------------------
log "5/6 Writing $PKG_NAME"
# Empty the output folders instead of deleting them: on Windows a folder that is open in Explorer or is
# the current folder of a PowerShell window (e.g. after flashing from it) can't be removed.
mkdir -p "$PKG" "$INFO"
find "$PKG" "$INFO" -mindepth 1 -delete 2>/dev/null || \
  die "can't clear $PKG_NAME in the output folder: close any program that has a file in it open (an editor, a
       running flash script) and run the build again (it is incremental, the compiled tree is kept)"
cp "${IMAGES[@]/#/$OUTDIR/images/}" "$PKG/"
cp "$OUTDIR/images/partition-table-32GB.img" "$OUTDIR/images/partition-table-32GB-4096.img" \
   "$OUTDIR/images/dtbo-sky1-orion_o6.img" "$OUTDIR/images/vbmeta-sky1-orion_o6.img" "$PKG/" 2>/dev/null || true
cp /opt/android-flash/flash.ps1 /opt/android-flash/flash.sh "$PKG/"
chmod +x "$PKG/flash.sh"
(cd "$PKG" && sha256sum -- *.img *.cap > SHA256SUMS)
{
  echo "Board: $BOARD   lunch: ${PRODUCT}-bp2a-${VARIANT}   patches: $PATCHES   manifest: $MANIFEST"
  echo "Manifest: $MANIFEST_URL ($MANIFEST_BRANCH)"
  git -C .repo/manifests log -1 --format='manifest repo commit: %H %cd' 2>/dev/null || true
  grep -h -E '^ro\.build\.(fingerprint|date)=' "$OUTDIR/system/build.prop" 2>/dev/null || true
  echo "Kernel: $(strings "$OUTDIR/kernel" 2>/dev/null | grep -m1 'Linux version' || echo '?')"
  [[ -n "$WIFI_COUNTRY" ]] && echo "Wi-Fi country: $WIFI_COUNTRY"
  [[ -n "$SKIP_PATCHES" ]] && echo "Skipped patches: $SKIP_PATCHES"
  echo "Kernel command line: $(grep -h '^BOARD_KERNEL_CMDLINE' device/cix/sky1/sky1_orion_o6/BoardConfig.mk | sed 's/^BOARD_KERNEL_CMDLINE *[:+]= *//' | tr '\n' ' ')"
  if [[ "$PATCHES" == "1" ]]; then (cd "$PATCH_DIR" && find . -name '*.patch' -printf '%P\n' | sort | xargs sha256sum | sed 's/^/patch: /'); fi
  echo "Built $(date -u +%Y-%m-%dT%H:%M:%SZ) in $(. /etc/os-release && echo "$PRETTY_NAME"), $JOBS jobs"
} > "$INFO/BUILD-INFO.txt"
repo manifest -r -o "$INFO/manifest-revisions.xml" </dev/null 2>/dev/null || true
for p in "${PROJECTS[@]}"; do
  git -C "$SRC/$p" --no-pager diff --binary --src-prefix="a/$p/" --dst-prefix="b/$p/"
  git -C "$SRC/$p" ls-files --others --exclude-standard | while read -r f; do
    git -C "$SRC/$p" --no-pager diff --binary --no-index --src-prefix="a/$p/" --dst-prefix="b/$p/" /dev/null "$f" || true
  done
done > "$INFO/source-changes.patch"
grep -E 'PCIEASPM|CONFIG_BT_HCIBTUSB|CONFIG_BT_RTKBTUSB' "$KCONF" > "$INFO/kernel-config-highlights.txt" 2>/dev/null || true
cp /work/build.log "$INFO/build.log"
ls -l "$PKG"

# --- 6. done --------------------------------------------------------------------------------------------
log "6/6 Done: $PKG"
echo "Flash it with $PKG_NAME/flash.ps1 (Windows) or flash.sh (Linux), see README.md."
