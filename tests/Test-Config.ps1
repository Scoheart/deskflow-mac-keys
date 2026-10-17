# Offline tests: no processes started, no real settings or startup items changed.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'scripts\Common.ps1')
$script:checks = 0
function Assert-That([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $caught = $false
    try { & $Action | Out-Null } catch { $caught = $true }
    Assert-That $caught $Message
}

foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.ps1' -Recurse) {
    $parseErrors = $null; $tokens = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    Assert-That ($parseErrors.Count -eq 0) ('PowerShell parse errors: ' + $file.Name + ': ' + ($parseErrors | Out-String))
}

$ini = "[core]`r`ncoreMode=2`r`ncomputerName=Test-PC`r`n`r`n[other]`r`nenterCommand=keep-me`r`ncustom=a=b`r`n"
$fields = Get-CallbackFields 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' 'D:\User Files\Keys\DeskflowMacKeys.ahk'
$changed = $ini
foreach ($key in $fields.Keys) { $changed = Set-IniField $changed 'core' $key $fields[$key] }
Assert-That ($changed.Contains("custom=a=b`r`n")) 'Unrelated values must survive.'
Assert-That ((Get-IniField $changed 'other' 'enterCommand').Value -eq 'keep-me') 'Wrong section modified.'
Assert-That ((Get-IniField $changed 'core' 'enterCommand').Value -eq $fields.enterCommand) 'Enter command escaped incorrectly.'
Assert-That ($fields.enterCommand.Contains('\"C:/Program Files/AutoHotkey')) 'QSettings quote escaping is missing.'
Assert-That ($fields.exitCommand.EndsWith(' leave"')) 'Leave command incorrect.'
$again = Set-IniField $changed 'core' 'enterCommand' $fields.enterCommand
Assert-That ($again -eq $changed) 'Repeated writes must be idempotent.'
$changed = Set-IniField $changed 'core' 'computerName' 'Later-PC'
foreach ($key in $fields.Keys) { $changed = Set-IniField $changed 'core' $key '' $false }
Assert-That ((Get-IniField $changed 'core' 'computerName').Value -eq 'Later-PC') 'Rollback lost a later unrelated edit.'
Assert-That (-not (Get-IniField $changed 'core' 'enterCommand').Present) 'Rollback failed to remove its own key.'
Assert-Throws { Set-IniField "[core]`nx=1`nx=2`n" 'core' 'x' '3' } 'Duplicate keys must be rejected.'
Assert-Throws { Get-IniField "[core]`nx=1`n[core]`nx=2`n" 'core' 'x' } 'Duplicate sections must be rejected.'

$rules = Get-Content -LiteralPath (Join-Path $root 'examples\editor-keybindings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$fixtures = @(
    '[]',
    "// Empty`n[`n] // final comment",
    '[{"key":"ctrl+n","command":"custom.new"}]',
    "[`n {`"key`":`"ctrl+n`",`"command`":`"custom.new`",}, // keep, comment`n]",
    '[{"key":"ctrl+n","command":"https://example.test/a//b/*literal*/,]"}]',
    '[/* block,comment */{"key":"ctrl+n","command":"a\"b"},/* tail */]'
)
foreach ($fixture in $fixtures) {
    $original = ConvertFrom-Json -InputObject (Get-JsoncText $fixture)
    $updated = Add-EditorBindings $fixture $rules
    $result = ConvertFrom-Json -InputObject (Get-JsoncText $updated)
    $oldCount = if ($null -eq $original) { 0 } else { @($original).Count }
    Assert-That (@($result).Count -eq $oldCount + 4) ('Wrong editor binding count: ' + $fixture)
    if ($oldCount) { Assert-That ($result[0].command -eq @($original)[0].command) 'Original command modified.' }
    Assert-That ($result[-1].when -eq 'terminalFocus && isWindows') 'Terminal context must be Windows-only.'
    if ($fixture.Contains('keep, comment')) { Assert-That ($updated.Contains('keep, comment')) 'Comment content changed.' }
}
Assert-Throws { Add-EditorBindings '[{"key":"f13","command":"mine"}]' $rules } 'Existing F13 must not be overwritten.'
Assert-Throws { Add-EditorBindings '{"key":"f13"}' $rules } 'Wrong JSON root must fail.'
Assert-Throws { Add-EditorBindings '[invalid]' $rules } 'Invalid JSON must fail.'
Assert-Throws { Get-JsoncText '[ /* unclosed' } 'Unclosed comments must fail.'
Write-Output ("PASS: $script:checks configuration checks. No live keyboard or application settings changed.")
