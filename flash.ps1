<#
.SYNOPSIS
  Flashes an Orion O6 Android 16 build (the output of build.ps1 / build.sh) over USB with fastboot.

.DESCRIPTION
  Run it from the build's output folder (it is copied there), or pass -ImagesDir.
  1. Checks the images against SHA256SUMS.
  2. Gets the board into fastboot: "adb reboot bootloader" if Android is running, otherwise it waits
     while you start fastboot yourself (UEFI Shell command "fastboot" on the dmod BIOS).
  3. Flashes. Default: update, keeps your data (both A/B slots + super, no partition-table write, no erase).
     -Wipe: full install like CIX's android_flush_images.bat: partition table, erases userdata/misc/
     persist/metadata (ALL DATA IS LOST), all partitions, then "fastboot oem cixboot".
  4. Waits for Android to boot (unless -NoWait) and prints the build, kernel, DDR low-power and ASPM state.
  Needs adb and fastboot (Android platform-tools) on PATH or in C:\adb.

.EXAMPLE
  .\flash.ps1               # update, keeps data
  .\flash.ps1 -Wipe         # full install, erases all data (asks first)
  .\flash.ps1 -Wipe -Yes    # same, no question
#>
param(
  [switch]$Wipe,
  [switch]$Yes,
  [switch]$NoWait,
  [string]$ImagesDir = $PSScriptRoot,
  [int]$FastbootTimeoutSec = 600,
  [int]$BootTimeoutSec = 600
)
$ErrorActionPreference = 'Stop'

function Find-Tool([string]$name) {
  $c = Get-Command $name -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  if (Test-Path "C:\adb\$name.exe") { return "C:\adb\$name.exe" }
  throw "$name not found: install Android platform-tools and put them on PATH"
}
$adb = Find-Tool 'adb'
$fastboot = Find-Tool 'fastboot'
$ImagesDir = (Resolve-Path $ImagesDir).Path
$log = Join-Path $ImagesDir ("flash-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".log")

function Log([string]$m) { $l = "$(Get-Date -Format HH:mm:ss) $m"; Write-Host $l; Add-Content -Path $log -Value $l }
function Fail([string]$m) { Log "FAILED: $m"; Log "log: $log"; exit 1 }
# adb/fastboot through cmd so stderr (fastboot progress) is captured as text
function Run([string]$exe, [string]$a, [switch]$Quiet) {
  $out = cmd /c "`"$exe`" $a 2>&1"; $code = $LASTEXITCODE
  $text = ($out | Out-String).Trim()
  if (-not $Quiet -and $text) { Add-Content -Path $log -Value $text }
  [pscustomobject]@{ Code = $code; Out = $text }
}
function Fastboot-Serial { $r = Run $fastboot 'devices' -Quiet; if ($r.Out -match '(\S+)\s+fastboot') { $Matches[1] } else { $null } }
function Adb-Up { (Run $adb 'get-state' -Quiet).Out -eq 'device' }
function Adb-Sh([string]$c) { (Run $adb "shell $c" -Quiet).Out }

Log "flash: images=$ImagesDir wipe=$Wipe"

# 1. Images
$need = 'boot.img','init_boot.img','vendor_boot.img','super.img','dtbo-sky1.img','vbmeta-sky1.img','LinuxLoader.efi.cap'
if ($Wipe) { $need += 'partition-table-default.img','partition-table-default-4096.img' }
foreach ($f in $need) { if (-not (Test-Path (Join-Path $ImagesDir $f))) { Fail "missing $f in $ImagesDir" } }
$sums = Join-Path $ImagesDir 'SHA256SUMS'
if (Test-Path $sums) {
  Log 'Checking SHA256SUMS ...'
  foreach ($line in Get-Content $sums) {
    if ($line -notmatch '^([0-9a-f]{64})\s+\*?(.+)$') { continue }
    $h = (Get-FileHash -Algorithm SHA256 (Join-Path $ImagesDir $Matches[2])).Hash.ToLower()
    if ($h -ne $Matches[1]) { Fail "checksum mismatch: $($Matches[2])" }
  }
  Log '  all images OK'
} else { Log 'WARNING: no SHA256SUMS, images not checked' }

if ($Wipe -and -not $Yes) {
  $a = Read-Host 'Full install: ALL DATA ON THE BOARD WILL BE ERASED. Type YES to continue'
  if ($a -ne 'YES') { Fail 'cancelled' }
}

# 2. Into fastboot
$serial = Fastboot-Serial
if (-not $serial) {
  if (Adb-Up) { Log 'Android is running: adb reboot bootloader'; Run $adb 'reboot bootloader' | Out-Null }
  else { Log 'Waiting for the board in fastboot mode: in the UEFI Shell type "fastboot" and connect the USB-C data port ...' }
  $deadline = (Get-Date).AddSeconds($FastbootTimeoutSec); $gone = $false; $hinted = $false
  while (-not ($serial = Fastboot-Serial)) {
    if ((Get-Date) -gt $deadline) { Fail "no fastboot device within $FastbootTimeoutSec s" }
    $up = Adb-Up; if (-not $up) { $gone = $true }
    if ($gone -and $up -and -not $hinted) {
      Log 'The board came back in Android, not fastboot (the running image lacks the reboot-to-fastboot patch). Start fastboot from the UEFI Shell; still waiting.'
      $hinted = $true
    }
    Start-Sleep -Seconds 2
  }
}
Log "Fastboot device: $serial"
$vars = Run $fastboot 'getvar all' -Quiet
if ($vars.Out -match 'backdoor:yes') { Fail 'the board is in DDR ("backdoor") fastboot mode; this script flashes the NVMe install only' }

# 3. Flash
$steps = @()
if ($Wipe) {
  if ($vars.Out -match 'block-size:\s*4096') { $gpt = 'partition-table-default-4096.img' } else { $gpt = 'partition-table-default.img' }
  $steps += "flash gpt $gpt", 'erase userdata', 'erase misc', 'erase persist', 'erase metadata'
}
$steps += 'flash dtbo_a dtbo-sky1.img', 'flash dtbo_b dtbo-sky1.img',
          'flash s2_a LinuxLoader.efi.cap', 'flash s2_b LinuxLoader.efi.cap',
          'flash boot_a boot.img', 'flash boot_b boot.img',
          'flash init_boot_a init_boot.img', 'flash init_boot_b init_boot.img',
          'flash vbmeta_a vbmeta-sky1.img', 'flash vbmeta_b vbmeta-sky1.img',
          'flash vendor_boot_a vendor_boot.img', 'flash vendor_boot_b vendor_boot.img',
          'flash super super.img'
Push-Location $ImagesDir
try {
  foreach ($s in $steps) {
    Log "fastboot $s"
    $r = Run $fastboot $s
    if ($r.Code -ne 0 -or $r.Out -match 'FAILED') { Fail "fastboot $s" }
  }
} finally { Pop-Location }
if ($Wipe) {
  # CIX's script ends the full install with "oem cixboot"
  Log 'fastboot oem cixboot'; Run $fastboot 'oem cixboot' | Out-Null
} else {
  # After an update flash "oem cixboot" doesn't boot Android; a plain reboot does.
  Log 'fastboot reboot'; Run $fastboot 'reboot' | Out-Null
}
if ($NoWait) { Log "Flashed. Log: $log"; exit 0 }

# 4. Wait for Android
Log 'Waiting for Android to boot (the first boot after -Wipe takes longer) ...'
$deadline = (Get-Date).AddSeconds($BootTimeoutSec); $fbSince = $null; $fbReboots = 0
while ($true) {
  if ((Get-Date) -gt $deadline) { Fail "Android did not finish booting within $BootTimeoutSec s" }
  if (Adb-Up) {
    $fbSince = $null
    if ((Adb-Sh 'getprop sys.boot_completed') -eq '1') { break }
  } elseif (Fastboot-Serial) {
    # After "reboot bootloader" the firmware keeps the fastboot reason for one more boot: reboot again.
    if (-not $fbSince) { $fbSince = Get-Date }
    elseif (((Get-Date) - $fbSince).TotalSeconds -gt 10) {
      if ($fbReboots -ge 3) { Fail 'the board keeps booting into fastboot' }
      $fbReboots++; Log "Board is in fastboot again: fastboot reboot #$fbReboots"
      Run $fastboot 'reboot' | Out-Null; $fbSince = $null; $deadline = $deadline.AddSeconds(60); Start-Sleep -Seconds 5
    }
  } else { $fbSince = $null }
  Start-Sleep -Seconds 3
}
Log "Android booted (uptime $(Adb-Sh 'cut -d. -f1 /proc/uptime') s)"
Log "  fingerprint : $(Adb-Sh 'getprop ro.build.fingerprint')"
Log "  build date  : $(Adb-Sh 'getprop ro.build.date')"
Log "  kernel      : $(Adb-Sh 'uname -v')"
Log "  DDR low-power on = $(Adb-Sh 'cat /sys/devices/platform/cix_ddr_lp/on') (0 = off, patched image)"
Log "  PCIe ASPM policy: $(Adb-Sh 'cat /sys/module/pcie_aspm/parameters/policy')"
Log "Done. Log: $log"
exit 0
