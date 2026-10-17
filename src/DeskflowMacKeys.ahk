#Requires AutoHotkey v2.0.30 64-bit
#SingleInstance Off
#NoTrayIcon

; Physical left Command is LWin on this keyboard in Windows.
; No modifier swap: when remote, all normal keys pass through to Deskflow.
; Run with enter/leave for Deskflow, or pause/resume/toggle/status/exit.
SetWorkingDir A_ScriptDir
DetectHiddenWindows true
SetTitleMatchMode 3
A_MenuMaskKey := "vkE8"
ControlTitle := "DeskflowMacKeys.Control." A_UserName
ControlMessage := 0x8056
StatePath := A_ScriptDir "\state.ini"
LogPath := A_ScriptDir "\events.log"
LocalScreen := true
ManualPause := false
LastEvent := 0
CoreIdentity := ""
AltHeld := false

if A_Args.Length {
    mode := StrLower(A_Args[1])
    if mode = "validate" {
        ; Parse and register the actual hotkeys with all conditions false.
        ManualPause := true
        RegisterKeys()
        ExitApp 0
    }
    modes := Map("enter", 1, "leave", 2, "pause", 3, "resume", 4,
        "toggle", 5, "status", 6, "exit", 7)
    if !modes.Has(mode)
        ExitApp 2
    eventTime := ProcessCreated(ProcessExist())
    controller := WinExist(ControlTitle)
    if !controller && (mode = "enter" || mode = "leave") {
        Run('"' A_AhkPath '" /ErrorStdOut "' A_ScriptFullPath '"', A_ScriptDir, "Hide")
        controller := WinWait(ControlTitle, , 5)
    }
    if !controller
        ExitApp 3
    try {
        result := SendMessage(ControlMessage, modes[mode], eventTime, , "ahk_id " controller, , , , 3000)
        try FileAppend result "`n", "*"
        ExitApp 0
    } catch {
        ExitApp 4
    }
}

; Keep a single resident even if two transition helpers start simultaneously.
MutexHandle := DllCall("CreateMutexW", "Ptr", 0, "Int", 0,
    "Str", "Local\DeskflowMacKeys." A_UserName, "Ptr")
if !MutexHandle || A_LastError = 183
    ExitApp

CoreIdentity := GetCoreIdentity()
ManualPause := IniRead(StatePath, "state", "ManualPause", 0) + 0
if IniRead(StatePath, "state", "CoreIdentity", "") = CoreIdentity {
    LocalScreen := IniRead(StatePath, "state", "LocalScreen", 1) + 0
    LastEvent := IniRead(StatePath, "state", "LastEvent", 0) + 0
}
; With no server, Windows is necessarily local.
if CoreIdentity = ""
    LocalScreen := true
RegisterKeys()
OnMessage(ControlMessage, ReceiveControl)
OnExit(Cleanup)
A_TrayMenu.Delete()
A_TrayMenu.Add("Pause / resume mappings (Ctrl+Alt+F12)", TogglePause)
A_TrayMenu.Add("Open status", (*) => Run('notepad.exe "' StatePath '"'))
A_TrayMenu.Add("Open event log", (*) => Run('notepad.exe "' LogPath '"'))
A_TrayMenu.Add()
A_TrayMenu.Add("Exit mappings", (*) => ExitApp())
A_IconHidden := false
SaveState("started")
; Publish only once the message handler and key conditions are ready.
WinSetTitle ControlTitle, "ahk_id " A_ScriptHwnd
SetTimer WatchCore, 500
Persistent

MappingOn(*) {
    global LocalScreen, ManualPause
    return LocalScreen && !ManualPause
}

RegularContext(*) {
    return MappingOn() && !IsConsole()
}

ActiveExe() {
    try return StrLower(WinGetProcessName("A"))
    catch
        return ""
}

IsConsole() {
    exe := ActiveExe()
    if exe = "windowsterminal.exe" || exe = "wezterm-gui.exe" || exe = "alacritty.exe"
        return true
    try return WinGetClass("A") = "ConsoleWindowClass"
    catch
        return false
}

RegisterKeys() {
    ; Emergency hotkey is local-only, so it too passes through while on Mac.
    HotIf (*) => LocalScreen
    Hotkey "^!F12", TogglePause
    HotIf MappingOn
    Hotkey "$<#c", CopyOrPaste.Bind(false)
    Hotkey "$<#v", CopyOrPaste.Bind(true)
    Hotkey "$<#Tab", SwitchWindow.Bind(false)
    Hotkey "$<#+Tab", SwitchWindow.Bind(true)
    Hotkey "$<#q", SendKeys.Bind("!{F4}")
    Hotkey "$<#m", (*) => WinMinimize("A")
    Hotkey "$<#Space", SendKeys.Bind("#s")
    Hotkey "$<#+4", SendKeys.Bind("#+s")
    HotIf RegularContext
    for key, output in Map(
        "x", "^x", "a", "^a", "z", "^z", "+z", "^y",
        "s", "^s", "+s", "^+s", "f", "^f", "n", "^n", "+n", "^+n",
        "o", "^o", "p", "^p", "t", "^t", "w", "^w", "+t", "^+t",
        "r", "^r", "=", "^=", "+=", "^+{=}", "-", "^-", "0", "^0",
        "Left", "{Home}", "Right", "{End}", "+Left", "+{Home}", "+Right", "+{End}",
        "Up", "^{Home}", "Down", "^{End}", "+Up", "^+{Home}", "+Down", "^+{End}")
        Hotkey "$<#" key, SendKeys.Bind(output)
    ; LWin+L is intentionally untouched: Windows' lock shortcut is reserved.
    HotIf SwitcherContext
    Hotkey "$*Tab", (*) => SwitchWindow(GetKeyState("Shift", "P"))
    HotIf
}

SwitcherContext(*) {
    global AltHeld
    return MappingOn() && AltHeld && GetKeyState("LWin", "P")
}

SendKeys(keys, *) {
    SendInput keys
}

CopyOrPaste(paste, *) {
    exe := ActiveExe()
    if exe = "code.exe" || exe = "cursor.exe" {
        ; Companion keybindings route by terminalFocus, never send Ctrl+C to a shell.
        SendInput paste ? "{F14}" : "{F13}"
    } else if exe = "windowsterminal.exe" || exe = "wezterm-gui.exe" || exe = "alacritty.exe" {
        SendInput paste ? "^+v" : "^+c"
    } else if IsConsole() {
        SendInput paste ? "+{Insert}" : "^{Insert}"
    } else {
        SendInput paste ? "^v" : "^c"
    }
}

SwitchWindow(reverse, *) {
    global AltHeld
    ; Blind mode avoids restoring LWin into the Windows Alt-Tab switcher.
    AltHeld := true
    SendInput "{Blind}{LWin up}{LAlt down}" (reverse ? "+{Tab}" : "{Tab}")
    SetTimer ReleaseAltWhenDone, 15
}

ReleaseAltWhenDone(*) {
    global AltHeld
    if !MappingOn() || !GetKeyState("LWin", "P") {
        if AltHeld
            SendInput "{Blind}{LAlt up}"
        AltHeld := false
        SetTimer ReleaseAltWhenDone, 0
    }
}

TogglePause(*) {
    global ManualPause
    ManualPause := !ManualPause
    ReleaseAltWhenDone()
    SaveState("manual toggle")
}

ReceiveControl(mode, stamp, *) {
    global LocalScreen, ManualPause, LastEvent, CoreIdentity
    Critical
    if mode = 1 || mode = 2 {
        currentCore := GetCoreIdentity()
        if currentCore != CoreIdentity {
            CoreIdentity := currentCore
            LastEvent := 0
        }
        ; Ignore late callbacks from a previous server or an older transition.
        coreCreated := currentCore = "" ? 0 : StrSplit(currentCore, ":")[2] + 0
        if stamp <= LastEvent || stamp < coreCreated
            return -1
        LastEvent := stamp
        LocalScreen := mode = 1 || currentCore = ""
    } else if mode = 3
        ManualPause := true
    else if mode = 4
        ManualPause := false
    else if mode = 5
        ManualPause := !ManualPause
    else if mode = 7 {
        SetTimer (*) => ExitApp(), -20
        return 7
    }
    ReleaseAltWhenDone()
    SaveState(mode = 1 ? "Deskflow enter" : mode = 2 ? "Deskflow leave" : "control " mode)
    return MappingOn() ? 1 : LocalScreen ? 2 : 3
}

WatchCore(*) {
    global CoreIdentity, LocalScreen, LastEvent
    identity := GetCoreIdentity()
    if identity != CoreIdentity {
        ; A new server always starts on its primary (Windows) screen.
        CoreIdentity := identity
        LocalScreen := true
        LastEvent := 0
        ReleaseAltWhenDone()
        SaveState(identity = "" ? "Deskflow stopped" : "Deskflow restarted")
    }
}

GetCoreIdentity() {
    pid := ProcessExist("deskflow-core.exe")
    created := pid ? ProcessCreated(pid) : 0
    return created ? pid ":" created : ""
}

ProcessCreated(pid) {
    h := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr")
    if !h
        return 0
    created := Buffer(8), ended := Buffer(8), kernel := Buffer(8), user := Buffer(8)
    ok := DllCall("GetProcessTimes", "Ptr", h, "Ptr", created, "Ptr", ended, "Ptr", kernel, "Ptr", user)
    DllCall "CloseHandle", "Ptr", h
    return ok ? NumGet(created, 0, "Int64") : 0
}

SaveState(reason) {
    global StatePath, LogPath, LocalScreen, ManualPause, CoreIdentity, LastEvent
    active := MappingOn()
    A_IconTip := "Deskflow Mac Keys: " (active ? "Windows - ON" : LocalScreen ? "MANUAL PAUSE" : "Mac - PAUSED")
    text := "LocalScreen=" (LocalScreen ? 1 : 0) "`nManualPause=" (ManualPause ? 1 : 0)
        . "`nMappingsEnabled=" (active ? 1 : 0) "`nCoreIdentity=" CoreIdentity
        . "`nLastEvent=" LastEvent "`nResidentPID=" ProcessExist()
        . "`nUpdated=" FormatTime(, "yyyy-MM-dd HH:mm:ss") "`nReason=" reason
    IniWrite text, StatePath, "state"
    try {
        ; Bounded, transition-only log; no keys or clipboard contents are recorded.
        if FileExist(LogPath) && FileGetSize(LogPath) > 1048576
            FileMove LogPath, LogPath ".previous", 1
        FileAppend FormatTime(, "yyyy-MM-dd HH:mm:ss") " | " reason
            . " | local=" LocalScreen " paused=" ManualPause " enabled=" active "`n", LogPath, "UTF-8"
    }
}

Cleanup(*) {
    global AltHeld, MutexHandle
    if AltHeld
        SendInput "{Blind}{LAlt up}"
    if MutexHandle
        DllCall "CloseHandle", "Ptr", MutexHandle
}
