# Close Deskflow and the mappings first. Never deletes dependencies or backups.
[CmdletBinding(SupportsShouldProcess=$true)]
param([string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\DeskflowMacKeys'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$InstallDir = [IO.Path]::GetFullPath($InstallDir)
$manifestPath = Join-Path $InstallDir 'installation.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'No installation.json found. Use the manual removal instructions for a legacy installation.' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.SchemaVersion -ne 1 -or $manifest.InstallDir -ne $InstallDir) { throw 'Unrecognized installation manifest.' }
if (-not $PSCmdlet.ShouldProcess($InstallDir, 'Restore unchanged settings/shortcuts and remove the runtime script')) { return }
Assert-AppsClosed $InstallDir $manifest.DeskflowExe
$conflicts = @()
$text = [IO.File]::ReadAllText($manifest.DeskflowSettings)
$fieldsMatch = $true
foreach ($field in $manifest.InstalledFields.PSObject.Properties) {
    $current = Get-IniField $text 'core' $field.Name
    $old = $manifest.OriginalFields.($field.Name)
    $isInstalled = $current.Present -and $current.Value -eq $field.Value
    $isOriginal = $current.Present -eq $old.Present -and $current.Value -eq $old.Value
    if (-not $isInstalled -and -not $isOriginal) { $fieldsMatch = $false }
}
if (-not $fieldsMatch) {
    throw 'Deskflow callbacks changed since installation. Keep the runtime; resolve callbacks manually before retrying uninstall.'
}
foreach ($field in $manifest.OriginalFields.PSObject.Properties) {
    $text = Set-IniField $text 'core' $field.Name $field.Value.Value $field.Value.Present
}
Write-Utf8 $manifest.DeskflowSettings $text
foreach ($file in (@($manifest.Editors) + @($manifest.Shortcuts))) {
    if (-not (Test-Path -LiteralPath $file.Path)) { continue }
    $currentHash = (Get-FileHash -LiteralPath $file.Path).Hash
    if ($file.Existed -and (Test-Path -LiteralPath $file.Backup) -and $currentHash -eq (Get-FileHash -LiteralPath $file.Backup).Hash) { continue }
    if ($currentHash -ne $file.InstalledHash) {
        $conflicts += $file.Path
        Write-Warning ("Changed after installation; preserved: " + $file.Path)
        continue
    }
    if ($file.Existed) { Copy-Item -LiteralPath $file.Backup -Destination $file.Path -Force }
    else { Remove-Item -LiteralPath $file.Path }
}
if ($conflicts.Count) {
    Write-Warning 'Resolve the preserved editor rules/shortcuts manually, then run uninstall again. Runtime and manifest kept for reference.'
    return
}
$script = Join-Path $InstallDir 'DeskflowMacKeys.ahk'
if (Test-Path -LiteralPath $script) {
    if ((Get-FileHash -LiteralPath $script).Hash -eq $manifest.RuntimeHash) { Remove-Item -LiteralPath $script }
    else { Write-Warning 'The runtime script was edited; kept the file. Callbacks and startup integration have been removed.' }
}
Move-Item -LiteralPath $manifestPath -Destination (Join-Path $manifest.BackupDir 'installation.uninstalled.json') -Force
Write-Output 'Mappings removed. Deskflow and AutoHotkey remain installed; local backups were kept.'
