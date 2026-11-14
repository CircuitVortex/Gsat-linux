# Undo apply.ps1 exactly: restore startup entries, power scheme, visual settings.
$ErrorActionPreference = 'Continue'
$root   = Split-Path -Parent $MyInvocation.MyCommand.Path
$backup = Join-Path $root 'backup'
if (-not (Test-Path $backup)) { throw "no backup directory at $backup - nothing to revert" }
$state = Get-Content (Join-Path $backup 'state.json') -Raw | ConvertFrom-Json

# startup Run entries
$reg = Join-Path $backup 'hkcu-run.reg'
if (Test-Path $reg) {
    reg import $reg *> $null
    if ($LASTEXITCODE -eq 0) { "restored: HKCU Run entries" }
}
# startup folder shortcuts
$bk = Join-Path $backup 'Startup'
if (Test-Path $bk) {
    $sf = [Environment]::GetFolderPath('Startup')
    Get-ChildItem $bk -File | ForEach-Object {
        Copy-Item $_.FullName -Destination $sf -Force
        "restored: $($_.Name)"
    }
}
# power scheme
if ($state.powerScheme) {
    powercfg /setactive $state.powerScheme *> $null
    if ($LASTEXITCODE -eq 0) { "restored: power scheme $($state.powerScheme)" }
}
# visual settings
$veKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
$twKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
if ($null -ne $state.visualFXSetting) { Set-ItemProperty -Path $veKey -Name VisualFXSetting -Value $state.visualFXSetting -Type DWord }
if ($null -ne $state.enableTransparency) { Set-ItemProperty -Path $twKey -Name EnableTransparency -Value $state.enableTransparency -Type DWord }
"restored: visual effects"

# hibernation: cannot know prior state, so leave it - tell the user
"note: hibernation is not auto-restored. Re-enable with:  powercfg /h on   (elevated)"
"log out / log back in for visual and startup changes to take effect"
