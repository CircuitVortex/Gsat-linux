# Run Linux on this PC without turning on virtualization (no BIOS change).
#
# WSL2 needs AMD-V/SVM enabled in firmware. That is switched off on this
# machine and the owner has ruled out BIOS changes. WSL1 does not use a
# virtual machine at all - it runs Linux binaries on the Windows kernel - so
# it works with SVM off. This script installs the WSL1 component and imports
# an Ubuntu 24.04 rootfs as a WSL1 distro.
#
# Phase 1: enable "Windows Subsystem for Linux" (UAC prompt, then reboot).
# Phase 2: run again - imports the distro and smoke-tests it.
#
# Nothing here touches firmware, partitions, or existing WSL distros.

$ErrorActionPreference = 'Stop'
$distro = 'Ubuntu-24.04-Build'
$tar    = Join-Path $env:TEMP 'opencode\ubuntu-base-24.04.5-base-amd64.tar.gz'
$root   = Join-Path $env:LOCALAPPDATA "wsl\$distro"

function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---- phase 1: the optional component -----------------------------------
# After the reboot the driver lands on disk and the service exists, so this
# check lets the second run skip elevation (and the second UAC prompt).
$wsl1Installed = (Test-Path "$env:SystemRoot\System32\drivers\lxcore.sys") -or
                 [bool](Get-Service LxssManager -ErrorAction SilentlyContinue)

if (-not $wsl1Installed) {
    if (-not (Test-Elevated)) {
        Write-Host 'Elevation required to enable the WSL1 component. Approve the UAC prompt...'
        $psi = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
        $p = Start-Process powershell -Verb RunAs -Wait -PassThru -ArgumentList $psi
        Write-Host "elevated run finished with exit code $($p.ExitCode)"
        exit $p.ExitCode
    }

    $feature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
    if ($feature.State -ne 'Enabled') {
        Write-Host "Microsoft-Windows-Subsystem-Linux is $($feature.State) - enabling (no restart yet)"
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux `
            -All -NoRestart | Out-Null
    }
    Write-Host ''
    Write-Host 'Component enabled. REBOOT WINDOWS, then run this script again to import the distro.'
    Write-Host 'This is a normal Windows restart, not a BIOS change.'
    exit 0
}

# ---- phase 2: import ----------------------------------------------------
Write-Host 'WSL1 component is enabled.'

if (-not (Test-Path $tar)) { throw "rootfs tarball missing: $tar" }
New-Item -ItemType Directory -Force -Path $root | Out-Null

$existing = (wsl.exe -l -q 2>$null) -replace "`0", ''
if ($existing -match [regex]::Escape($distro)) {
    Write-Host "distro '$distro' already registered - skipping import"
} else {
    Write-Host 'setting default WSL version to 1'
    wsl.exe --set-default-version 1

    Write-Host "importing $distro as WSL1 -> $root"
    wsl.exe --import $distro $root $tar --version 1
    if ($LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Host "import failed with exit code $LASTEXITCODE."
        Write-Host 'This build of WSL may have dropped WSL1 support. Use the GitHub Actions route instead.'
        exit $LASTEXITCODE
    }
}

Write-Host ''
Write-Host '=== distros ==='
wsl.exe -l -v

Write-Host ''
Write-Host '=== smoke test ==='
wsl.exe -d $distro -e bash -lc 'uname -srm; echo "cpus: $(nproc)"; free -m | head -2; echo "gcc: $(command -v gcc || echo missing)"'

Write-Host ''
Write-Host "done. enter it with:  wsl -d $distro"
