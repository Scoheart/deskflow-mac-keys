Set-StrictMode -Version Latest

function Write-Utf8([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Get-IniField([string]$Text, [string]$Section, [string]$Key) {
    $pattern = '(?ms)^\[' + [regex]::Escape($Section) + '\]\r?\n(?<body>.*?)(?=^\[|\z)'
    $sections = [regex]::Matches($Text, $pattern)
    if ($sections.Count -gt 1) { throw "Duplicate INI section: $Section" }
    if ($sections.Count -eq 0) { return @{ Present = $false; Value = '' } }
    $fields = [regex]::Matches($sections[0].Groups['body'].Value, '(?m)^' + [regex]::Escape($Key) + '=(?<value>[^\r\n]*)')
    if ($fields.Count -gt 1) { throw "Duplicate INI key: $Section/$Key" }
    if ($fields.Count -eq 0) { return @{ Present = $false; Value = '' } }
    return @{ Present = $true; Value = $fields[0].Groups['value'].Value }
}

function Set-IniField([string]$Text, [string]$Section, [string]$Key, [string]$Value, [bool]$Present = $true) {
    $null = Get-IniField $Text $Section $Key
    $nl = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $pattern = '(?ms)^\[' + [regex]::Escape($Section) + '\]\r?\n(?<body>.*?)(?=^\[|\z)'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) {
        if (-not $Present) { return $Text }
        return $Text.TrimEnd() + $nl + $nl + "[$Section]" + $nl + "$Key=$Value" + $nl
    }
    $body = $match.Groups['body']
    $field = [regex]::Match($body.Value, '(?m)^' + [regex]::Escape($Key) + '=[^\r\n]*(?:\r?\n|$)')
    if ($field.Success) {
        $replacement = if ($Present) { "$Key=$Value" + $nl } else { '' }
        $newBody = $body.Value.Substring(0, $field.Index) + $replacement + $body.Value.Substring($field.Index + $field.Length)
    } elseif ($Present) {
        $newBody = $body.Value.TrimEnd() + $nl + "$Key=$Value" + $nl + $nl
    } else { return $Text }
    return $Text.Substring(0, $body.Index) + $newBody + $Text.Substring($body.Index + $body.Length)
}

function ConvertTo-QSettingsValue([string]$Value) {
    return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function Get-CallbackFields([string]$AhkExe, [string]$Script) {
    $prefix = '"' + $AhkExe.Replace('\', '/') + '" /ErrorStdOut "' + $Script.Replace('\', '/') + '" '
    return [ordered]@{
        enableEnterCommand = 'true'
        enterCommand = ConvertTo-QSettingsValue ($prefix + 'enter')
        enableExitCommand = 'true'
        exitCommand = ConvertTo-QSettingsValue ($prefix + 'leave')
    }
}

function Find-AutoHotkey([string]$ExplicitPath) {
    $candidates = @()
    if ($ExplicitPath) { $candidates = @($ExplicitPath) }
    else {
        foreach ($regPath in @('HKCU:\Software\AutoHotkey', 'HKLM:\Software\AutoHotkey')) {
            $entry = Get-ItemProperty -LiteralPath $regPath -ErrorAction SilentlyContinue
            if ($entry -and $entry.PSObject.Properties['InstallDir']) {
                $candidates += Join-Path $entry.InstallDir 'v2\AutoHotkey64.exe'
            }
        }
        $candidates += Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'
        $candidates += Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $item = Get-Item -LiteralPath $candidate
            if ($item.VersionInfo.ProductVersion -notmatch '^2\.') { continue }
            return $item.FullName
        }
    }
    throw 'AutoHotkey v2 x64 not found. Install v2.0.30 or newer, or pass -AutoHotkeyExe.'
}

# Replace JSONC comments with whitespace (same indexes), never strip inside strings.
function Get-JsoncText([string]$Text, [bool]$RemoveTrailingCommas = $true) {
    $chars = $Text.ToCharArray()
    $inString = $false
    for ($i = 0; $i -lt $chars.Length; $i++) {
        if ($inString) {
            if ($chars[$i] -eq '\') { $i++; continue }
            if ($chars[$i] -eq '"') { $inString = $false }
            continue
        }
        if ($chars[$i] -eq '"') { $inString = $true; continue }
        if ($chars[$i] -ne '/' -or $i + 1 -ge $chars.Length) { continue }
        if ($chars[$i + 1] -eq '/') {
            while ($i -lt $chars.Length -and $chars[$i] -ne "`n" -and $chars[$i] -ne "`r") {
                $chars[$i] = ' '; $i++
            }
            $i--
        } elseif ($chars[$i + 1] -eq '*') {
            $chars[$i] = ' '; $chars[$i + 1] = ' '; $i += 2
            $closed = $false
            while ($i -lt $chars.Length) {
                if ($chars[$i] -eq '*' -and $i + 1 -lt $chars.Length -and $chars[$i + 1] -eq '/') {
                    $chars[$i] = ' '; $chars[$i + 1] = ' '; $i++; $closed = $true; break
                }
                if ($chars[$i] -ne "`n" -and $chars[$i] -ne "`r") { $chars[$i] = ' ' }
                $i++
            }
            if (-not $closed) { throw 'Unclosed JSONC comment.' }
        }
    }
    if ($inString) { throw 'Unclosed JSON string.' }
    if (-not $RemoveTrailingCommas) { return -join $chars }
    # Ignore trailing commas, again outside strings only.
    $inString = $false
    for ($i = 0; $i -lt $chars.Length; $i++) {
        if ($inString) {
            if ($chars[$i] -eq '\') { $i++; continue }
            if ($chars[$i] -eq '"') { $inString = $false }
            continue
        }
        if ($chars[$i] -eq '"') { $inString = $true; continue }
        if ($chars[$i] -eq ',') {
            $j = $i + 1
            while ($j -lt $chars.Length -and [char]::IsWhiteSpace($chars[$j])) { $j++ }
            if ($j -lt $chars.Length -and ($chars[$j] -eq ']' -or $chars[$j] -eq '}')) { $chars[$i] = ' ' }
        }
    }
    return -join $chars
}

function Add-EditorBindings([string]$Text, [array]$Rules) {
    $clean = Get-JsoncText $Text
    if (-not $clean.Trim().StartsWith('[') -or -not $clean.Trim().EndsWith(']')) { throw 'keybindings.json must be an array.' }
    $entries = ConvertFrom-Json -InputObject $clean -ErrorAction Stop
    foreach ($entry in $entries) {
        if ($entry.PSObject.Properties['key'] -and $entry.key -match '^(f13|f14)$') {
            throw 'F13/F14 already configured. Merge editor bindings manually; use -SkipEditors for installation.'
        }
    }
    $end = $clean.LastIndexOf(']')
    $before = $Text.Substring(0, $end)
    # The original may already contain a trailing comma. Comments do not count.
    $needsComma = $null -ne $entries -and @($entries).Count -gt 0
    $commentsRemoved = Get-JsoncText $Text $false
    if ($commentsRemoved.Substring(0, $end).TrimEnd().EndsWith(',')) { $needsComma = $false }
    $block = if ($needsComma) { ",`n" } else { "`n" }
    $block += "    // BEGIN DeskflowMacKeys: Windows Command+C/V`n"
    $block += (($Rules | ForEach-Object { '    ' + (ConvertTo-Json -InputObject $_ -Compress) }) -join ",`n")
    $block += "`n    // END DeskflowMacKeys`n"
    $result = $before + $block + $Text.Substring($end)
    $null = ConvertFrom-Json -InputObject (Get-JsoncText $result) -ErrorAction Stop
    return $result
}

function New-MacKeysShortcut([string]$Path, [string]$Target, [string]$Arguments, [string]$WorkingDirectory) {
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($Path)
    $link.TargetPath = $Target
    $link.Arguments = $Arguments
    $link.WorkingDirectory = $WorkingDirectory
    $link.WindowStyle = 7
    $link.Save()
}

function Assert-AppsClosed([string]$InstallDir, [string]$DeskflowExe) {
    $sessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $df = @(Get-Process -Name 'deskflow','deskflow-core' -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sessionId })
    if ($df.Count) { throw 'Exit Deskflow completely from its tray menu before changing callbacks.' }
    $ahk = @(Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" | Where-Object {
        $_.CommandLine -and $_.CommandLine.Contains((Join-Path $InstallDir 'DeskflowMacKeys.ahk'))
    })
    if ($ahk.Count) { throw 'Exit the existing Deskflow Mac Keys tray process before installing/uninstalling.' }
}
