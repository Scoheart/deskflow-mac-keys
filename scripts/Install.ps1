# Run in a normal PowerShell session. Dependencies must already be installed.
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)][string]$DeskflowSettings,
    [string]$DeskflowExe,
    [string]$AutoHotkeyExe,
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\DeskflowMacKeys'),
    [switch]$SkipEditors,
    [switch]$NoStartup,
    [switch]$NoStart
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$repo = Split-Path $PSScriptRoot -Parent
$settingsPath = (Resolve-Path -LiteralPath $DeskflowSettings).Path
$InstallDir = [IO.Path]::GetFullPath($InstallDir)
$ahk = Find-AutoHotkey $AutoHotkeyExe
$source = Join-Path $repo 'src\DeskflowMacKeys.ahk'
$target = Join-Path $InstallDir 'DeskflowMacKeys.ahk'
$manifestPath = Join-Path $InstallDir 'installation.json'
if ($DeskflowExe) { $DeskflowExe = (Resolve-Path -LiteralPath $DeskflowExe).Path }
if (Test-Path -LiteralPath $manifestPath) {
    $existing = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($existing.Status -eq 'Installed' -and $existing.DeskflowSettings -eq $settingsPath -and
        (Test-Path -LiteralPath $target) -and (Get-FileHash -LiteralPath $target).Hash -eq (Get-FileHash -LiteralPath $source).Hash) {
        Write-Output 'This version is already installed. No files changed.'
        return
    }
    throw 'An installation manifest already exists. Uninstall the old/partial installation first.'
}
if (Test-Path -LiteralPath $target) { throw 'A legacy runtime exists here. Disable/remove the old integration first, or choose a new -InstallDir.' }
$settings = [IO.File]::ReadAllText($settingsPath)
if ((Get-IniField $settings 'core' 'coreMode').Value -ne '2') { throw 'Configure this Windows computer as a Deskflow server first (coreMode=2).' }
$fields = Get-CallbackFields $ahk $target
$original = [ordered]@{}
foreach ($key in $fields.Keys) { $original[$key] = Get-IniField $settings 'core' $key }
foreach ($key in @('enterCommand','exitCommand')) {
    if ($original[$key].Present -and $original[$key].Value.Trim('"').Length) {
        throw 'Existing enter/exit commands detected. Preserve or remove them manually before installation.'
    }
}
$updatedSettings = $settings
foreach ($key in $fields.Keys) { $updatedSettings = Set-IniField $updatedSettings 'core' $key $fields[$key] }

# Plan and validate editor changes before writing any files.
$rules = Get-Content -LiteralPath (Join-Path $repo 'examples\editor-keybindings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$editorPlans = @()
if (-not $SkipEditors) {
    foreach ($app in @('Code','Cursor')) {
        $userDir = Join-Path $env:APPDATA ($app + '\User')
        if (-not (Test-Path -LiteralPath $userDir -PathType Container)) { continue }
        $file = Join-Path $userDir 'keybindings.json'
        $existed = Test-Path -LiteralPath $file
        $text = if ($existed) { [IO.File]::ReadAllText($file) } else { "[`n]`n" }
        $editorPlans += @{ App=$app; Path=$file; Existed=$existed; Text=(Add-EditorBindings $text $rules) }
    }
}
Write-Output "Runtime: $InstallDir"
Write-Output "Deskflow settings: $settingsPath"
Write-Output "AutoHotkey: $ahk"
Write-Output ('Editor files: ' + $editorPlans.Count)
if (-not $PSCmdlet.ShouldProcess($InstallDir, 'Install mappings, configure Deskflow callbacks, and create local backups')) { return }
Assert-AppsClosed $InstallDir $DeskflowExe

# This mode loads/validates the hotkey definitions and exits without a resident.
$validation = Start-Process -FilePath $ahk -ArgumentList ('/ErrorStdOut "' + $source + '" validate') -WindowStyle Hidden -Wait -PassThru
if ($validation.ExitCode -ne 0) { throw "AutoHotkey validation failed, exit $($validation.ExitCode)." }
$backupDir = Join-Path $InstallDir ('backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
Copy-Item -LiteralPath $settingsPath -Destination (Join-Path $backupDir 'Deskflow.before.conf')
$manifest = [ordered]@{
    SchemaVersion=1; Version='1.0.0'; Status='Installing'; Created=(Get-Date -Format o)
    InstallDir=$InstallDir; AutoHotkeyExe=$ahk; DeskflowSettings=$settingsPath; DeskflowExe=$DeskflowExe
    RuntimeHash=(Get-FileHash -LiteralPath $source).Hash
    OriginalFields=$original; InstalledFields=$fields; BackupDir=$backupDir; Editors=@(); Shortcuts=@()
}
function Save-Manifest { Write-Utf8 $manifestPath (ConvertTo-Json -InputObject $manifest -Depth 8) }
Save-Manifest
try {
    Copy-Item -LiteralPath $source -Destination $target
    foreach ($plan in $editorPlans) {
        $backup = Join-Path $backupDir ($plan.App + '.keybindings.json')
        if ($plan.Existed) { Copy-Item -LiteralPath $plan.Path -Destination $backup }
        Write-Utf8 $plan.Path $plan.Text
        $manifest.Editors += @{ Path=$plan.Path; Existed=$plan.Existed; Backup=$backup; InstalledHash=(Get-FileHash -LiteralPath $plan.Path).Hash }
        Save-Manifest
    }
    Write-Utf8 $settingsPath $updatedSettings
    $startupDir = [Environment]::GetFolderPath('Startup')
    $linkPlans = @()
    foreach ($mode in @('start','pause','resume','exit')) {
        $arg = if ($mode -eq 'start') { '' } else { ' ' + $mode }
        $linkPlans += @{ Path=(Join-Path $InstallDir ($mode + '.lnk')); Target=$ahk; Args=('/ErrorStdOut "' + $target + '"' + $arg); Dir=$InstallDir }
    }
    if (-not $NoStartup) {
        $linkPlans += @{ Path=(Join-Path $startupDir 'Deskflow Mac Keys.lnk'); Target=$ahk; Args=('/ErrorStdOut "' + $target + '"'); Dir=$InstallDir }
        if ($DeskflowExe) {
            $linkPlans += @{ Path=(Join-Path $startupDir 'Deskflow.lnk'); Target=$DeskflowExe; Args=''; Dir=(Split-Path $DeskflowExe -Parent) }
        }
    }
    foreach ($plan in $linkPlans) {
        $backup = Join-Path $backupDir ([guid]::NewGuid().ToString('N') + '.lnk')
        $existed = Test-Path -LiteralPath $plan.Path
        if ($existed) { Copy-Item -LiteralPath $plan.Path -Destination $backup }
        New-MacKeysShortcut $plan.Path $plan.Target $plan.Args $plan.Dir
        $manifest.Shortcuts += @{ Path=$plan.Path; Existed=$existed; Backup=$backup; InstalledHash=(Get-FileHash -LiteralPath $plan.Path).Hash }
        Save-Manifest
    }
    # Manual setup reference uses unescaped command lines (the GUI does the escaping).
    $prefix = '"' + $ahk + '" /ErrorStdOut "' + $target + '" '
    Write-Utf8 (Join-Path $InstallDir 'callbacks.txt') ("Enter Windows:`r`n" + $prefix + "enter`r`n`r`nLeave Windows:`r`n" + $prefix + "leave`r`n")
    $manifest.Status = 'Installed'
    Save-Manifest
} catch {
    $manifest.Status = 'Partial'
    Save-Manifest
    throw ('Installation stopped. Keep the backups and run Uninstall.ps1 before retrying. ' + $_.Exception.Message)
}
if (-not $NoStart) {
    if ($DeskflowExe) { Start-Process -FilePath $DeskflowExe -WorkingDirectory (Split-Path $DeskflowExe -Parent) -WindowStyle Hidden }
    Start-Process -FilePath $ahk -ArgumentList ('/ErrorStdOut "' + $target + '"') -WorkingDirectory $InstallDir -WindowStyle Hidden
}
Write-Output 'Installed. Test Command+C/V on Windows, switch to Mac, then return to Windows.'
Write-Output "Backup and installation manifest: $InstallDir"
