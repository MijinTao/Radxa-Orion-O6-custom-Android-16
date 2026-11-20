<#
.SYNOPSIS
  Builds Android 16 for the Radxa Orion O6 (CIX's Android 16 tree + the patches in .\patches) in Docker
  and puts the result in .\output.

.EXAMPLE
  .\build.ps1 -O6                    # Orion O6, userdebug -> .\output\O6-Android16-userdebug\
  .\build.ps1 -O6 -Variant user      # user build           -> .\output\O6-Android16-user\
  .\build.ps1 -O6 -Stock             # CIX's tree without the patches -> ...-stock\
  .\build.ps1 -O6 -Latest -Sync      # newest CIX manifest instead of the pinned one (patches may not apply)
  .\build.ps1 -O6 -WifiCountry DE    # another Wi-Fi country code (the patches set IT)
  .\build.ps1 -O6 -Cpus 16 -Memory 48 # limit the build container to 16 CPUs and 48 GB of RAM
  .\build.ps1 -O6 -VerboseConsole    # leave out patch 0014: full kernel log on the serial console

  Without -O6 / -O6N it builds the O6. -O6N stops with an explanation: CIX's tree has no O6N device.
  The first run downloads about 90 GB of source into the Docker volume and takes several hours.
#>
param(
  [switch]$O6,
  [switch]$O6N,
  [switch]$Stock,
  [ValidateSet('userdebug', 'user')][string]$Variant = 'userdebug',
  [switch]$Latest,
  [switch]$Sync,
  [int]$Jobs = 0,
  [double]$Cpus = 0,
  [int]$Memory = 0,
  [string]$WifiCountry = '',
  [switch]$VerboseConsole,
  [string]$OutputDir = (Join-Path $PSScriptRoot 'output'),
  [string]$Image = 'radxa-o6-android16-builder',
  [string]$SourceVolume = 'radxa-o6-android16-src'
)
$ErrorActionPreference = 'Stop'

$boards = @()
if ($O6)  { $boards += 'O6' }
if ($O6N) { $boards += 'O6N' }
if ($boards.Count -eq 0) {
  $boards = @('O6')
  Write-Host 'No board given: building the Orion O6.' -ForegroundColor Yellow
}
$patches  = if ($Stock) { '0' } else { '1' }
$manifest = if ($Latest) { 'latest' } else { 'pinned' }
$syncFlag = if ($Sync) { '1' } else { '0' }
New-Item -ItemType Directory -Force $OutputDir | Out-Null
$OutputDir = (Resolve-Path $OutputDir).Path

docker build -t $Image $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw 'docker build failed' }
docker volume create $SourceVolume | Out-Null

foreach ($board in $boards) {
  Write-Host "`n=== Building Android 16 for the $board ($Variant) ===" -ForegroundColor Cyan
  $envArgs = @('-e', "BOARD=$board", '-e', "VARIANT=$Variant", '-e', "PATCHES=$patches",
               '-e', "MANIFEST=$manifest", '-e', "SYNC=$syncFlag")
  # Without -Jobs the build uses one job per allowed CPU (nproc in the container ignores --cpus).
  $buildJobs = if ($Jobs -gt 0) { $Jobs } elseif ($Cpus -gt 0) { [int][math]::Max(1, [math]::Floor($Cpus)) } else { 0 }
  if ($buildJobs -gt 0) { $envArgs += @('-e', "JOBS=$buildJobs") }
  $limitArgs = @()
  if ($Cpus -gt 0)   { $limitArgs += @('--cpus', "$Cpus") }
  if ($Memory -gt 0) { $limitArgs += @('--memory', "${Memory}g", '--memory-swap', "${Memory}g") }
  if ($limitArgs.Count -gt 0) { Write-Host "Limits: $($limitArgs -join ' ')  jobs: $(if ($buildJobs) { $buildJobs } else { 'all CPUs' })" -ForegroundColor Yellow }
  if ($WifiCountry) { $envArgs += @('-e', "WIFI_COUNTRY=$WifiCountry") }
  if ($VerboseConsole) { $envArgs += @('-e', 'SKIP_PATCHES=0014'); Write-Host 'Leaving out patch 0014 (quiet serial console)' -ForegroundColor Yellow }
  docker run --rm -t @limitArgs `
    -v "${SourceVolume}:/work" `
    -v "${OutputDir}:/out" `
    @envArgs `
    $Image
  if ($LASTEXITCODE -ne 0) { throw "$board build failed (exit code $LASTEXITCODE)" }
}

Write-Host "`nDone ($($boards -join ', ')). Output in $OutputDir" -ForegroundColor Green
Get-ChildItem $OutputDir
