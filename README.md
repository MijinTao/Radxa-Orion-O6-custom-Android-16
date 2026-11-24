# Radxa-Orion-O6-custom-Android-16

Android 16 for the **Radxa Orion O6**, built in Docker from CIX's public Android 16 sources
([cixtech/android-manifest](https://github.com/cixtech/android-manifest), branch `cix_android16_2025q3_dev`,
"Android16 + k6.6 + 2025Q3 Rc4.2") plus seventeen patches: six that make Wi-Fi, Bluetooth and `adb reboot bootloader`
work, fix the board's freezes and add a mouse-click-as-touch option, six kernel fixes backported from mainline
Linux, where CIX is upstreaming the P1 (Sky1) drivers (see [Mainline backports](#mainline-backports)), two fixes for DP
audio turning robotic and then silent, and three more fixes taken from CIX's mainline work (HD audio, USB-C, USB3).

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
| `-VerboseConsole` / `--verbose-console` | Leave out patch 0014: the kernel writes all its messages to the serial console again (to chase a hard freeze over UART; DP audio may break up again) |
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

From the output folder (or from the repository folder: there the scripts use the newest build in `output/`, `-ImagesDir` / `--images` picks another), with the board connected over its **USB-C data port**:

```powershell
.\flash.ps1          # update: keeps your apps and data
.\flash.ps1 -Wipe    # full install: new partition table, ALL DATA ERASED (asks first)
```

```bash
./flash.sh           # update
./flash.sh --wipe    # full install
```

- **Getting into fastboot**: if Android is running with USB debugging allowed for the PC, the script does
  `adb reboot bootloader` (the firmware's fastboot, patch 0002); if the board comes back in Android instead, it
  tries `adb reboot fastboot` (Android's own fastbootd), which is enough for an update. `-Wipe` needs the
  firmware's fastboot (fastbootd can't write the partition table), so from fastbootd the script switches over with
  `fastboot reboot bootloader`. Otherwise start fastboot yourself: power on, press **Escape**, **Boot Manager →
  UEFI Shell**, type `fastboot`. The script keeps checking for adb and fastboot while it waits.
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
| 0007 | `mailbox-cix-upstream-fixes` | kernel | **Mailbox hardening** (mainline `cix-mailbox.c`). The mailbox carries the SCMI traffic to the power-management firmware, the audio DSP and the sensor hub. The FIFO receive interrupt could overrun a 32-word stack buffer; a failed channel startup returned success or leaked its IRQ; kernel addresses were printed to dmesg. |
| 0008 | `reset-sky1-reset-pulse-timing` | kernel | **Reliable block resets** (mainline `reset-sky1.c`, `reset-sky1-audss.c`). Assert/deassert returned immediately, so drivers doing assert→deassert (I2C, SPI, I3C, DMA, audio) produced a reset pulse two register writes long. Like mainline, the line is now held 50–100 µs after each edge. |
| 0009 | `i2c-cadence-shutdown-handler` | kernel | **Clean I2C state across reboots** (mainline f612925f989). On reboot each I2C controller is marked suspended and reset, so a transfer in flight can't leave the bus busy for the firmware or the next boot. |
| 0010 | `spi-cadence-upstream-fixes` | kernel | **SPI data integrity** (mainline 633cd6fe6e1, d9eadfce2fa, 666fa7e9ca9, 5b1689a41f0, ecea4f0e9db). RX is drained before TX is refilled (received bytes were lost on transfers longer than the FIFO); the TX-full back-off is applied per FIFO entry (transfers could stall and time out); unbind and probe failure no longer touch an unclocked controller or unbalance its clocks. |
| 0011 | `usb-cdnsp-upstream-fixes` | kernel | **USB-C role switching** (mainline 87c5ff5615d, 87e4b043b98, 3348f444a4c). Fixes a use-after-free each time the USB-C port leaves device (ADB) mode, a NULL dereference on resume when the role changed during suspend, and a DMA memory leak on a failed USB3 streams endpoint setup. |
| 0012 | `scmi-perf-check-allowed-ops` | kernel | **No needless DVFS requests to the SCP** (mainline 189df98777a, by CIX). Level/limit changes that the firmware reports as not allowed for a performance domain are refused locally instead of being sent to the SCP and rejected. |
| 0013 | `dma350-cyclic-lost-period-resync` | kernel | **DP audio turning robotic, then silent.** The audio DMA tracked the playback position only by counting period interrupts; when one was held off for more than a period (5.3 ms) the position fell behind for good, until the DMA played stale data. The position is now read from the hardware (current linked command + what is left of it), the same method as CIX's own pending mainline DMA-350 cyclic support; the interrupt count stays as a fallback and is resynchronised, misses counted in `/sys/module/arm_dma350/parameters/lost_periods`. |
| 0014 | `serial-console-quiet` | `device/cix` | **Quiet serial console** (kernel command line `loglevel=4`). Every kernel message used to go out over the 115200-baud UART, and each line kept interrupts off on one CPU for ~10 ms; that made the audio DMA miss period interrupts. Now only errors and worse go to the UART; `dmesg`, `logcat` and the pstore log still have everything, and an oops/panic still prints in full. `-VerboseConsole` / `--verbose-console` builds without this patch. |
| 0015 | `hda-reset-response-counter-on-timeout` | kernel | **3.5 mm jack audio that stops responding** (mainline 51ee6ce2418, which names the CIX HDA controller). After one lost codec reply, every later command to the ALC256 codec waited the full 1 s timeout and failed (jack detection, volume, stream start). The pending-reply count is now reset on a timeout. |
| 0016 | `typec-rts5453-shared-irq-fixes` | kernel | **USB-C ports disturbing each other** (from CIX's pending mainline PD driver, v7). Both RTS5453 PD controllers share one interrupt; every event reprogrammed both ports' orientation switch and USB/DP mux. Now a port is only reprogrammed when its own status changes; pending interrupts are acknowledged at probe/resume; no more status dump per interrupt. |
| 0017 | `usb-cdnsp-sky1-d3-and-suspend-fixes` | kernel | **USB3 controller power-state fixes** (from CIX's pending mainline glue driver, v9). A failed D3 entry puts the controller back into D0 instead of half way; PME wake-up only when asked for; system suspend only gates the controller clocks once it has really stopped (gating a running controller can hang the bus); the per-autosuspend log lines are debug level. |

All patches together change 34 files; the build checks that each one is in the result (kernel config, drivers,
firmware, the input library) and stops if one is missing.

## Mainline backports

CIX is upstreaming the P1 (Sky1) SoC support into mainline Linux and tracks it at
[cixtech/linux-mainline/wiki](https://github.com/cixtech/linux-mainline/wiki). The mainline drivers are new, cleaned-up
versions of the drivers in CIX's 6.6 Android kernel, often with different device-tree bindings, so they are not
dropped in as a whole: each one was compared with the vendor driver of the pinned kernel
(`cix_opensource__linux` 2cee169e, 6.6.100), and the bug fixes the vendor driver lacks were ported to it as
patches 0007–0012. Each patch file starts with a description and the upstream commit IDs.

| Wiki item (mainline) | Result for this kernel |
|---|---|
| Basic DT, board DT (v6.17) | Not applied: different bindings from the vendor DT. The only mainline DT fix (pcie_x2 RCSU address typo) doesn't exist in the vendor DT; CPU idle states are identical. |
| Mailbox (v6.17) | **0007** |
| UART (PL011), Clock (SCMI) (v6.17) | Nothing to port: PL011 fixes since 6.6 concern DMA/RS485/PREEMPT_RT, unused here. |
| I2C (v6.18) | **0009**. Atomic (polled) transfers not ported: needs the clock handling reworked, no user on the O6. |
| I3C (v6.18) | Nothing to port: the use-after-free fix and prescaler fix are already in the vendor tree; no I3C devices on the O6. |
| SPI (v6.19) | **0010** |
| Pinctrl (v6.19) | Not applicable: mainline driver is a rewrite with a different DT binding. |
| PCIe (v6.19) | Nothing to port: the vendor driver already has the post-link-training delay and more (it also has a per-port `max-aspm-support` DT property). |
| HDA (v6.19) | Nothing to port: the vendor driver already has the same quirks (polled RIRB, address offset, aligned MMIO). |
| Reset (v7.1) | **0008**; reset tables compared, identical. |
| GPIO (v7.1) | Nothing to port: the only functional mainline change (both-edge interrupts) is already in the vendor driver. |
| Power domain (v7.1) | Not applicable: SCMI power domains are not used by the Android kernel (`CONFIG_ARM_SCMI_POWER_DOMAIN` off). |
| DPU (v7.1) | Not applicable: mainline only adds the Linlon-D6 ID to `komeda`; Android uses CIX's `linlon-dp` driver. |
| CPU idle, CPU DVFS (v7.2) | DT only in mainline (idle states identical); **0012** from CIX's SCMI perf work. |
| DMA (v7.3) | Not applicable: mainline uses Arm's `arm-dma350` driver (no audio/cyclic support); the vendor kernel has CIX's own DMA-350 driver, fixed separately in **0013**. |
| USB (reviewing) | **0011** (Cadence USBSSP core fixes); 11 other mainline cdnsp/xhci fixes are already in the vendor tree. |
| USB3/DP PHY, I2S, DP, GPU (planning) | Nothing merged yet. |

### Pending CIX work (lore.kernel.org, checked 23 Nov 2026)

Series CIX has posted but that are not merged yet, and what came of them:

| Series | Result for this kernel |
|---|---|
| `dmaengine: arm-dma350: Add slave support and Sky1 integration` (v7) | Its cyclic position code (from `CH_LINKADDR` + `CH_XSIZE`, "since multiple period completions may share a pending DONE interrupt") is the method **0013** now uses. The other fixes in it are for the mainline driver's own code (the vendor driver's trigger bits are already right). |
| `usb: typec: add CIX Type-C PD controller driver` (v7) | **0016** (same chips, vendor `rts5453.c`). |
| `usb: cdns3: Add CIX Sky1 glue driver` (v9) | **0017** (vendor `cdnsp-sky1.c`). |
| `soc: cix: Add the Sky1 AUDSS DMA-350 interrupt path` (v5) | Not needed: the vendor DMA driver programs the AUDSS interrupt gate itself on every stream setup. |
| `ASoC: cdns: Add Cadence I2S-SC and I2S-MC` (v5) | Nothing to port: same FIFO reset, clock selection and clock-ratio checks as the vendor `cdns_i2s_mc.c`. |
| `drm/cix: add Sky1 DisplayPort transmitter` (v2) | Not applicable: no audio support yet, much less complete than the vendor `trilin_dptx` driver. |
| `phy: cix: Sky1 DP PHY` (v5), `USB/DP combo PHY` (v2), `USB3 PHY` (v8) | Not applicable: new drivers with new bindings; the DP PHY review fix (PLL left off after a bad link rate) doesn't apply, the vendor PHY re-enables the PLL. |
| `drm/panthor: CIX Sky1` GPU (v3) | Not applicable: Android uses Arm's Mali kbase driver. |
| `ALSA: hda: Wait for PCM files on codec teardown` (v4) | Not needed: only matters when an HDA codec driver is unbound at runtime. |
| `arm64: dts: cix: fix I2C bus address and size cells` (v3) | Already right in the vendor device tree. |
| `perf: arm_pmu_acpi` / `arm_spe` heterogeneous ACPI | Not applicable: the Android image boots with a device tree, not ACPI. |

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
