# Deskflow Mac Keys

让连接在 **Windows 服务端**上的键盘使用常见 macOS 风格快捷键；通过 Deskflow 切到 Mac 时自动暂停映射，回到 Windows 自动恢复。

适用于：键鼠留在 Windows、习惯使用键盘左侧 **Command / Win**、希望与一台或多台 Mac 共用输入设备的场景。

```text
键盘和鼠标 → Windows（Deskflow 服务端 + AutoHotkey）
                 │
                 ├─ 鼠标在 Windows：左 Command+C → Ctrl+C
                 └─ 鼠标在 Mac：暂停映射 → Mac 原生 Command+C
```

本仓库保存可重装的脚本、配置示例和说明。安装器不下载第三方程序，也不包含设备证书、信任指纹、IP 地址、运行日志或个人编辑器配置。

## 1. 重装前准备

| 组件 | 本方案验证版本 | 获取方式 |
|---|---|---|
| Windows | Windows 11 x64 | 运行服务端 |
| AutoHotkey | **v2.0.30 x64** | [官方发布页](https://github.com/AutoHotkey/AutoHotkey/releases/tag/v2.0.30) |
| Deskflow | **v1.27.0** | [官方发布页](https://github.com/deskflow/deskflow/releases/tag/v1.27.0) |
| PowerShell | Windows PowerShell 5.1 | Windows 自带 |

AutoHotkey 脚本要求 v2.0.30 或更新的 v2 x64；不能使用 v1。Deskflow 1.27.0 提供本方案依赖的进入／离开命令回调；其他版本需要重新验证。

1. Windows 安装 AutoHotkey v2；Windows 和 Mac 都安装 Deskflow。Windows 便携版也可以。
2. Windows 选择“使用此计算机的键盘和鼠标”，作为服务端。
3. 在服务器布局中添加 Mac，名称必须与 Mac 上 Deskflow 显示的名称完全一致。放到实际屏幕所在的方向；多台 Mac 按实际布局添加。
4. Mac 选择客户端，填入 Windows 当前的局域网地址。在 macOS 系统设置中按 Deskflow 提示授予所需权限，并核对双方证书指纹。
5. 先确认两台电脑能正常切屏，再安装快捷键映射。

键盘在 Windows 下的**左 Command 必须被识别为 LWin**。若双模键盘切换了硬件模式，需要先确认实际键位。保留 Mac 的 `super → super`、`ctrl → ctrl`、`alt → alt`，不交换 Command 和 Control。

## 2. 下载仓库

使用 Git 克隆，或在 GitHub 选择 **Code → Download ZIP** 并解压。私有仓库需要先登录有权限的账号。

```powershell
git clone https://github.com/Scoheart/deskflow-mac-keys.git
cd deskflow-mac-keys
```

以下命令在仓库根目录的普通 PowerShell 中运行。无需管理员权限。

## 3. 安装联动

### 找到 Deskflow 配置

以 Deskflow 启动日志中的 **`initial settings file:`** 为准，它指向需要修改的 `Deskflow.conf`。

- 便携版通常是：`<Deskflow目录>\settings\Deskflow.conf`。
- 普通用户安装通常是：`%APPDATA%\Deskflow\Deskflow.conf`。
- **不要把 `deskflow-server.conf` 传给安装脚本**，它只负责屏幕布局。

配置前从托盘菜单**完全退出 Deskflow**；如果映射脚本已运行，再退出其 H 图标。关闭主窗口可能只会最小化到托盘。

### 运行安装脚本

将下面的两个路径替换成你新电脑上的实际路径：

```powershell
$deskflowDir = 'D:\Apps\Deskflow\deskflow-1.27.0-win-x64-portable'

# 先预览：只检查配置和显示计划，不写入文件、不启动映射
.\scripts\Install.ps1 `
  -DeskflowSettings "$deskflowDir\settings\Deskflow.conf" `
  -DeskflowExe "$deskflowDir\deskflow.exe" `
  -WhatIf

# 执行安装
.\scripts\Install.ps1 `
  -DeskflowSettings "$deskflowDir\settings\Deskflow.conf" `
  -DeskflowExe "$deskflowDir\deskflow.exe"
```

如果 PowerShell 因执行策略阻止本地脚本，先审阅源码；也可按[手动配置说明](docs/manual-setup.md)操作，无需更改执行策略。

安装脚本会：

1. 检查 Windows 已配置为服务端、AutoHotkey 可用，并验证 AHK 脚本。
2. 把运行脚本安装到 `%LOCALAPPDATA%\Programs\DeskflowMacKeys`。
3. 备份现有配置，只更新 `Deskflow.conf` 的四个进入／离开回调字段，保留屏幕布局和其他配置。
4. 给已存在的 VS Code／Cursor 默认用户目录追加四条 F13/F14 复制粘贴规则，保留原内容；遇到冲突会停止并提示。
5. 创建映射的登录自启动和 start/pause/resume/exit 快捷方式。传入 `-DeskflowExe` 时，也会设置 Deskflow 登录自启动并启动它。
6. 启动映射脚本，写入本地 `installation.json` 和备份，供以后卸载。

安装器不会覆盖已有的进入／离开命令。完全相同且由此安装器管理的版本重复安装会直接返回；更新版本前先卸载旧版本。

可选参数：

| 参数 | 用途 |
|---|---|
| `-AutoHotkeyExe '完整路径'` | AutoHotkey 不在常见安装位置时指定 `AutoHotkey64.exe` |
| `-InstallDir '完整路径'` | 自定义运行目录；卸载时传入同一路径 |
| `-NoStartup` | 不创建登录自启动项，仍会创建运行目录内的控制快捷方式 |
| `-NoStart` | 只安装，稍后手动启动 Deskflow 和映射 |
| `-SkipEditors` | 不改编辑器文件；VS Code／Cursor 的复制粘贴规则需手动合并 |

**当前电脑已有先前安装的版本时，不要再次直接运行安装器。** 本次仓库整理不会改动正在工作的配置。旧版本没有 `installation.json`，迁移时按[旧版迁移说明](docs/manual-setup.md#从先前手工安装的版本迁移)处理。

## 4. 常用快捷键

以下 Command 均指 **左 Command / 左 Win**，仅在 Windows 本地且未手动暂停时生效。

| 快捷键 | Windows 行为 |
|---|---|
| Command+C / V / X / A | 复制 / 粘贴 / 剪切 / 全选 |
| Command+Z / Shift+Z | 撤销 / 重做（Ctrl+Z / Ctrl+Y） |
| Command+S / Shift+S | 保存 / 另存为 |
| Command+F / N / O / P | 查找 / 新建 / 打开 / 打印 |
| Command+T / W / Shift+T | 新标签 / 关闭标签或文档 / 恢复标签 |
| Command+R | 刷新 |
| Command+加号 / 减号 / 0 | 放大 / 缩小 / 重置缩放 |
| Command+Tab / Shift+Tab | 正向 / 反向切换 Windows 窗口 |
| Command+Q | 关闭当前窗口（Alt+F4） |
| Command+M | 最小化当前窗口 |
| Command+Space | Windows 搜索 |
| Command+Shift+4 | Windows 区域截图 |
| Command+左 / 右 | 行首 / 行尾；再加 Shift 可选择文本 |
| Command+上 / 下 | 文档开头 / 末尾；再加 Shift 可选择文本 |
| **Ctrl+Alt+F12** | 在 Windows 上手动暂停／恢复 |

**Command+L 仍然会锁定 Windows**，浏览器地址栏请用 Ctrl+L。单独按 Command 仍打开开始菜单。右 Command、原有 Ctrl 和 Alt/Option 未作全局替换。

这些映射使用 Windows 应用已有的快捷键，菜单不会变成 macOS 样式。Command+Q 关闭的是当前窗口，Command+Tab 切换的是 Windows 窗口，不能保证与 macOS 的“退出整个应用／按应用切换”一致。应用自定义了 Ctrl 快捷键时，结果也会随之变化。

## 5. 终端和编辑器

- Windows Terminal：Command+C/V 使用 Ctrl+Shift+C/V，原有 Ctrl+C 仍可中断命令。
- 传统控制台：使用 Ctrl+Insert / Shift+Insert，效果取决于控制台支持。
- VS Code／Cursor：Command+C/V 发送 F13/F14，应用根据 `terminalFocus` 路由到编辑器或终端复制粘贴操作。
- 独立终端仅保留专门的复制粘贴及窗口类映射，其他文本类映射不启用；内置终端的其他组合仍由编辑器快捷键配置决定。
- 自定义配置文件、便携版编辑器或其他编辑器，需要手动合并 [editor-keybindings.json](examples/editor-keybindings.json)。这些规则带有 `isWindows` 条件。

没有 F13/F14 实体键也能使用，AHK 会生成这两个键。若编辑器设了 `terminal.integrated.sendKeybindingsToShell` 等覆盖选项，需另行检查；详见 [VS Code 官方说明](https://code.visualstudio.com/docs/terminal/advanced#_keyboard-shortcuts-and-the-shell)。

## 6. 暂停、诊断与卸载

手动暂停可以用 Ctrl+Alt+F12、托盘 H 图标菜单，或运行目录里的 `pause.lnk`。**暂停状态会保存，切回 Windows 不会取消手动暂停**；使用 `resume.lnk` 恢复。

退出进程只暂时停止映射；下次 Deskflow 切屏回调可能重新启动它。持续停用请使用暂停，彻底移除请卸载。

状态和日志位于安装目录：

| 文件 | 内容 |
|---|---|
| `state.ini` | `LocalScreen`、`ManualPause`、`MappingsEnabled` 和最近状态 |
| `events.log` | 进入／离开和控制事件；不记录按键或剪贴板内容，超过 1 MiB 轮换 |
| `callbacks.txt` | 当前机器可直接粘贴到 Deskflow GUI 的命令 |
| `installation.json`、`backups/` | 仅保存在本机的安装记录和配置备份 |

卸载前，先完全退出 Deskflow，再退出映射：

```powershell
.\scripts\Uninstall.ps1 -WhatIf
.\scripts\Uninstall.ps1
```

卸载会恢复本次修改的回调字段、编辑器配置和快捷方式；如果检测到后来修改过的文件，会保留并提示人工处理。它不卸载 AutoHotkey 或 Deskflow，也不删除备份。已修改的回调会阻止自动卸载，避免留下失效命令。

## 7. 联动原理与验证范围

Deskflow 进入 Windows 时执行 `DeskflowMacKeys.ahk enter`，离开时执行 `leave`。短命辅助进程向唯一的 AHK 常驻进程发送通知，常驻进程通过条件热键决定是否拦截 Command 组合。鼠标在远端时，普通键盘事件交给 Deskflow。

状态按 Deskflow 核心进程的 PID 和创建时间保存；核心进程停止／重启时重置为 Windows 本地。回调也带有辅助进程创建时间，迟到的旧通知不会覆盖新状态。回调是异步启动，存在短暂延迟；跨屏前应松开修饰键，尤其不要一直按住 Command+Tab 跨屏。

2026-10-18 的原始部署已由用户实测 Windows/Mac 复制粘贴和往返切屏，并用实际回调日志核对。仓库新增安装辅助脚本另有离线配置测试；并不代表每个应用、每个组合、每种键盘或每个 Deskflow 版本都经过实机验证。

管理员窗口、安全桌面、远程桌面和游戏可能有额外限制。普通权限 AHK 不保证拦截管理员应用；本方案不会修改系统锁屏、安全桌面或全局扫描码映射。

运行仓库测试（不改变当前键盘映射、不修改真实应用配置）：

```powershell
.\tests\Test-Config.ps1
```

## 文件结构

```text
src/DeskflowMacKeys.ahk           常驻映射和 Deskflow 回调入口
scripts/Install.ps1              安装、备份、设置回调和自启动
scripts/Uninstall.ps1            根据安装记录恢复配置
scripts/Common.ps1               INI、JSONC 和路径处理
examples/editor-keybindings.json 编辑器复制粘贴规则
examples/deskflow-server.conf     脱离本机名称的布局示例
docs/manual-setup.md             手动安装、旧版迁移和故障排查
tests/Test-Config.ps1             配置转换与保护行为测试
```

相关官方资料：[Deskflow 回调实现](https://github.com/deskflow/deskflow/blob/v1.27.0/src/lib/deskflow/Computer.cpp)、[AutoHotkey 条件热键](https://github.com/AutoHotkey/AutoHotkeyDocs/blob/v2/docs/lib/HotIf.htm)。
