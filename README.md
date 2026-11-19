# Radxa-Orion-O6-custom-Android-16

Android 16 for the **Radxa Orion O6**, built in Docker from CIX's public Android 16 sources
([cixtech/android-manifest](https://github.com/cixtech/android-manifest), branch `cix_android16_2025q3_dev`,
"Android16 + k6.6 + 2025Q3 Rc4.2") plus six patches that make Wi-Fi, Bluetooth and `adb reboot bootloader` work,
fix the board's freezes, and add a mouse-click-as-touch option.

**Tested on a Radxa Orion O6 with the `Android-1.3.2-dmod` BIOS from
[Radxa-Orion-O6-custom-BIOS](https://github.com/MijinTao/Radxa-Orion-O6-custom-BIOS). The Orion O6N is not supported (see [Orion O6N](#orion-o6n)).**

## Requirements

- **Docker**: Docker Desktop on Windows (WSL 2 backend) or Docker Engine on Linux, x86-64.
- **Disk**: about **250 GB** free where Docker keeps its data (Docker Desktop: its WSL disk image). The source
  is about 90 GB, the build output about 90 GB, plus the images.
- **RAM**: 32 GB minimum, 64 GB recommended; count about 2 GB per build job (e.g. `-Cpus 16 -Memory 32`). On
  Windows, Docker Desktop's WSL 2 VM gets half of the PC's RAM by default, and `-Memory` can't go above that; raise
  it in `%USERPROFILE%\.wslconfig` (`[wsl2]` → `memory=48GB`) if needed.
- **Time**: the first run downloads the whole source (several hours, depending on your connection) and builds
  everything (1–3 hours with 16–32 cores). Later builds reuse the source and are incremental.
- **To flash**: [Android platform-tools](https://developer.android.com/tools/releases/platform-tools)
  (`adb`, `fastboot`) and a USB-C cable to the O6's USB-C data port.

## Build

Windows (PowerShell), from the repository folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1 -O6
```

Linux:

```bash
./build.sh --o6
```

The images end up in **`output/O6-Android16-userdebug/`**. Without a board switch the O6 is built.

| Option (`build.ps1` / `build.sh`) | Effect |
|---|---|
| `-O6` / `--o6` | Build for the Orion O6 (default) |
| `-O6N` / `--o6n` | Stops with an explanation: not supported (see below) |
| `-Variant user` / `--variant user` | `user` build instead of `userdebug` (no root, no `adb root`) → `O6-Android16-user/` |
| `-Stock` / `--stock` | CIX's tree **without** the patches → `...-stock/` |
| `-Latest` / `--latest` | Newest revision of CIX's branch instead of the pinned manifest (the patches may no longer apply) |
| `-Sync` / `--sync` | Run `repo sync` again (otherwise the source is synced once and reused) |
| `-Jobs <n>` / `--jobs <n>` | Parallel build jobs (default: all CPUs, or the `-Cpus` value; lower it if the build runs out of memory) |
| `-Cpus <n>` / `--cpus <n>` | Limit the build container to *n* CPUs (Docker `--cpus`); also sets the jobs to *n* |
| `-Memory <GB>` / `--memory <GB>` | Limit the build container's RAM to that many GB (Docker `--memory`, no extra swap) |
| `-WifiCountry <XX>` / `--wifi-country <XX>` | Wi-Fi country code (patch 0001 sets `IT`) |
| `-OutputDir <dir>` / `--output <dir>` | Another output folder (default `output` in the repository) |

### Pinned source

By default the build uses **`manifest/orion-o6-pinned.xml`**: the exact revision of every project the patches
were made and tested on (`repo manifest -r` of the tested tree). CIX's branch can move; `-Latest` builds its
current head instead, which is useful to try a newer CIX drop but may need the patches updated.

## Output

`output/O6-Android16-<variant>/` contains what you need to flash:

| File | What it is |
|---|---|
| `boot.img`, `init_boot.img`, `vendor_boot.img` | Kernel, ramdisks (A/B slots) |
| `super.img` | System, vendor and product partitions (sparse image) |
| `dtbo-sky1.img`, `vbmeta-sky1.img` | Device-tree overlays and verified-boot metadata |
| `LinuxLoader.efi.cap` | CIX's Android boot loader (UEFI app, partitions `s2_a`/`s2_b`) |
| `partition-table-default*.img` | GPT for NVMe (512 and 4096-byte sectors), used by `flash -Wipe` |
| `flash.ps1`, `flash.sh` | Flash scripts (below) |
| `SHA256SUMS` | Checksums, checked by the flash scripts |

CIX's build also produces a BIOS (`cix_flash_all*.bin`) from CIX's own EDK2 tree. It is **not** copied to the
output on purpose: flash the BIOS from Radxa-Orion-O6-custom-BIOS instead.

Next to it, `output/O6-Android16-<variant>-build-info/` records how it was built: `BUILD-INFO.txt` (manifest,
fingerprint, kernel, patch checksums), `manifest-revisions.xml`, the full `source-changes.patch`, the kernel
config lines the patches set, and `build.log`. You don't need it to flash.

## Flash

Use the BIOS from [Radxa-Orion-O6-custom-BIOS](https://github.com/MijinTao/Radxa-Orion-O6-custom-BIOS) (`Android-1.3.2-dmod`): it has the UEFI Shell `fastboot` command
and turns the firmware's DDR low-power mode off.

From the output folder, with the board connected over its **USB-C data port**:

```powershell
.\flash.ps1          # update: keeps your apps and data
.\flash.ps1 -Wipe    # full install: new partition table, ALL DATA ERASED (asks first)
```

```bash
./flash.sh           # update
./flash.sh --wipe    # full install
```

- **Getting into fastboot**: if Android (with patch 0002) is running, the script does `adb reboot bootloader`.
  Otherwise start fastboot yourself: power on, press **Escape**, **Boot Manager → UEFI Shell**, type `fastboot`.
  The script waits for the board.
- **Update** flashes both A/B slots (`dtbo`, `s2`, `boot`, `init_boot`, `vbmeta`, `vendor_boot`) and `super`, then
  reboots. **`-Wipe`** does what CIX's `android_flush_images` script does: writes the GPT that matches the
  disk's sector size, erases `userdata`, `misc`, `persist`, `metadata`, flashes everything and ends with
  `fastboot oem cixboot`.
- Use **`-Wipe` for the first install**, when coming from another Android build, and after switching BIOS lines
  (Android's data encryption keys live in the BIOS's OP-TEE).
- After `adb reboot bootloader` the firmware keeps the fastboot reason for one more boot, so the board can land in
  fastboot again after flashing; the scripts detect that and reboot it.
- At the end the scripts wait for Android and print the fingerprint, kernel, DDR low-power state (`0` = off) and
  the PCIe ASPM policy (`[performance]`). Everything is logged to `flash-<time>.log` in the output folder.

## The patches

The patches are in `patches/<project path>/NNNN-<name>.patch` and are applied in number order; one number is one
fix, which can change several projects. Projects that patches touch are reset to the pinned revision before
every build, so rebuilding always starts clean.

| # | Patch | Projects | What and why |
|---|---|---|---|
| 0001 | `wifi-generic-nl80211-hal` | `device/cix` | **Wi-Fi works.** Realtek's Wi-Fi HAL (`libwifi-hal-rtk`, `lib_driver_cmd_rtl`) isn't in CIX's Android 16 manifest, so the stub HAL was linked and Wi-Fi never turned on. Uses AOSP's generic nl80211 HAL (`BOARD_WLAN_DEVICE := emulator`, which despite its name drives real nl80211 drivers) with `lib_driver_cmd_simulated_cf_bp`; CIX's `rtl_wlan.ko` driver stays. Installs the missing `/vendor/etc/wifi/wpa_supplicant.conf` template and sets the Wi-Fi country to `IT` (`-WifiCountry` changes it). |
| 0002 | `adb-reboot-bootloader-to-fastboot` | kernel | **`adb reboot bootloader` enters fastboot.** A small built-in driver (`cix-reboot-reason.c`) passes reboot reason `0x01` to the firmware (SiP call `0xC2000002`) and clears a leftover one at boot. Used by the flash scripts. |
| 0003 | `ddr-low-power-off` | `device/cix`, kernel | **Fixes freezes and power-offs under load.** With the firmware's DDR low-power mode on, sustained CPU/GPU load made the power-management firmware (SCP) stop answering and the board froze, reset or switched off. The `cix-ddr-lp` driver now turns it off when it probes, and `init.rc` writes `/sys/devices/platform/cix_ddr_lp/on 0` at early-init. Boot parameter `cix_ddr_lp.keep_on=1` leaves it on. (The dmod BIOS turns it off too.) |
| 0004 | `bluetooth-btusb-aosp-hal` | `device/cix` | **Bluetooth works.** CIX's image uses Realtek's out-of-tree `rtk_btusb`, which only serves Realtek's own HAL (not in the tree), and its firmware was missing. Switches the kernel to upstream `btusb` + `btrtl` (they know the RTL8852BE, USB `13d3:3570`), loads `btintel`/`btrtl`/`btusb` instead of `rtk_btusb`/`rfkill-bt`, installs AOSP's default Bluetooth HAL and `rtl_bt/rtl8852bu_fw.bin` from linux-firmware (binary, in the patch). |
| 0005 | `mouse-click-as-touch` | `frameworks/native`, `frameworks/base`, `packages/apps/Settings` | **New developer option "Mouse click as touch"** (Settings → System → Developer options → Input, off by default). Left-button clicks and drags reach apps as finger taps and swipes, for apps and games that ignore mouse input; the cursor, right/middle click, wheel and hover stay mouse. Done in `PointerChoreographer` after the cursor update; the switch is plumbed like "Show taps" (`Settings.Global dmod_mouse_click_as_touch`, also `adb shell settings put global dmod_mouse_click_as_touch 1`). |
| 0006 | `pcie-aspm-off` | `device/cix` | **Fixes the remaining random hard freezes.** The kernel's ASPM policy was `powersave`, which put the NVMe, Wi-Fi and 2.5 GbE PCIe links in L1; a CPU access to a link that didn't come back hung the whole board. The kernel default policy is now `performance` (`CONFIG_PCIEASPM_PERFORMANCE=y`): ASPM off on every link, as in Radxa's Android 1.0.0 BIOS. Costs a little idle power, no performance. The dmod BIOS (patch 0006 there) sets the firmware side to match. |

All patches together change 18 files; the build checks that each one is in the result (kernel config, drivers,
firmware, the input library) and stops if one is missing.

## Orion O6N

Not supported. CIX's Android 16 tree only contains the O6 product (`sky1_orion_o6`): there is no O6N device
configuration or device tree, and the O6N uses another SoC variant (CD8160). Nothing in this repository was tested
on an O6N. For the O6N, Radxa publishes Android 14 images
([radxa/cix-android-manifests releases](https://github.com/radxa/cix-android-manifests/releases),
`radxa-orion-o6n-android14-rc3.4`).

## How it works

- `build.ps1` / `build.sh` build the Docker image from `Dockerfile` (Ubuntu 22.04 with the AOSP host packages,
  plus the EDK2 host tools that CIX's `build-android.sh` uses for its boot loader and
  kernel steps) and run it with two volumes: the Docker volume `radxa-o6-android16-src` (source + build output,
  reused) and `output/`.
- `container-build.sh` runs inside the container as an unprivileged user:
  1. `repo init` (with `--git-lfs`, shallow) + `repo sync` of the pinned manifest, once;
  2. resets the projects the patches touch and applies `patches/`;
  3. `source build/envsetup.sh`, `lunch sky1_orion_o6-bp2a-userdebug`, `./build-android.sh -j<n>` (CIX's
     script: boot loader, kernel, out-of-tree drivers, Android, image export);
  4. checks that every patch is in the result (kernel config, drivers, firmware, the input library);
  5. writes `output/`.
- `manifest/orion-o6-pinned.xml` pins the source; `flash.ps1` / `flash.sh` are copied into every output folder.
- To start completely fresh: `docker volume rm radxa-o6-android16-src`.

## Credits

Android and AOSP: Google and the Android Open Source Project. Android 16 tree for the CIX P1: CIX Technology
(cixtech). Orion O6: Radxa. The patches modify that code under its licenses (Apache-2.0 for AOSP and most of the
device tree, GPL-2.0 for the kernel). The Bluetooth firmware `rtl8852bu_fw.bin` comes from linux-firmware
(Realtek, redistributable). No warranty: use at your own risk.
