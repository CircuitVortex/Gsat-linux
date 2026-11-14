# Apply the approved PC tuning. Backs up everything first; see revert.ps1.
# Changes: startup trim, powerscheme, visual effects, hibernation.
$ErrorActionPreference = 'Continue'
$root   = Split-Path -Parent $MyInvocation.MyCommand.Path
$backup = Join-Path $root 'backup'
New-Item -ItemType Directory -Force -Path $backup | Out-Null
$log = @()

# ---- 0. snapshot current state -----------------------------------------
$scheme = ((powercfg /getactivescheme) -split '\s+') | Where-Object { $_ -match '^[0-9a-f-]{36}$' } | Select-Object -First 1
$veKey  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
$twKey  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$origVE = (Get-ItemProperty -Path $veKey -Name VisualFXSetting -ErrorAction SilentlyContinue).VisualFXSetting
$origTW = (Get-ItemProperty -Path $twKey -Name EnableTransparency -ErrorAction SilentlyContinue).EnableTransparency
[pscustomobject]@{
    date = (Get-Date).ToString('o')
    powerScheme = $scheme
    visualFXSetting = $origVE
    enableTransparency = $origTW
} | ConvertTo-Json | Set-Content (Join-Path $backup 'state.json') -Encoding UTF8
$log += "snapshot: scheme=$scheme visualFX=$origVE transparency=$origTW"

# ---- 1. startup: back up, then remove ----------------------------------
reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" (Join-Path $backup 'hkcu-run.reg') /y | Out-Null
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$targets = @(
    'MicrosoftEdgeAutoLaunch_32A84EF72E10597AC239A668A4DE0237',
    'OneDrive', 'Opera Stable', 'Opera Browser Assistant',
    'RobloxPlayerBeta', 'JacCode_9254C7E1B48C101B753A'
)
foreach ($t in $targets) {
    if (Get-ItemProperty -Path $runKey -Name $t -ErrorAction SilentlyContinue) {
        Remove-ItemProperty -Path $runKey -Name $t -Force -ErrorAction SilentlyContinue
        $log += "startup: removed Run entry '$t'"
    }
}

$sf = [Environment]::GetFolderPath('Startup')
$bk = Join-Path $backup 'Startup'
New-Item -ItemType Directory -Force -Path $bk | Out-Null
Get-ChildItem -Path $sf -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item $_.FullName -Destination $bk -Force
    Remove-Item $_.FullName -Force
    $log += "startup: moved folder item '$($_.Name)' to backup"
}

# ---- 2. power plan ------------------------------------------------------
$high = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
powercfg /setactive $high 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { $log += "power: active scheme -> High performance" }
else { $log += "power: FAILED (exit $LASTEXITCODE) - may need admin" }

# ---- 3. visual effects --------------------------------------------------
try {
    if (-not (Test-Path $veKey)) { New-Item -Path $veKey -Force | Out-Null }
    Set-ItemProperty -Path $veKey -Name VisualFXSetting -Value 2 -Type DWord
    Set-ItemProperty -Path $twKey -Name EnableTransparency -Value 0 -Type DWord
    $log += "visual: VisualFXSetting=2 (best performance), transparency off"
} catch { $log += "visual: FAILED $_" }

# ---- 4. hibernation -----------------------------------------------------
powercfg /h off 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { $log += "hibernate: disabled" }
else { $log += "hibernate: FAILED (exit $LASTEXITCODE) - needs elevation" }

$log | ForEach-Object { $_ }
$log | Set-Content (Join-Path $backup 'applied.log') -Encoding UTF8
