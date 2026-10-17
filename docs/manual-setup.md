# 手动配置与故障排查

## 手动安装

1. 安装 AutoHotkey v2.0.30 x64 和 Deskflow 1.27.0。先配置 Windows 服务端和 Mac 客户端，并确认原生切屏正常。
2. 完全退出 Deskflow。将 `src/DeskflowMacKeys.ahk` 复制到自己长期保留的目录，例如 `%LOCALAPPDATA%\Programs\DeskflowMacKeys`。
3. 在 VS Code／Cursor 的 `keybindings.json` 数组中合并 `examples/editor-keybindings.json` 中的四条规则，先备份，避免 F13/F14 冲突。不要直接覆盖整个文件。
4. 打开 Deskflow 的设置，在进入本机、离开本机时运行命令的选项中分别启用并填写下面的命令。路径需要替换为实际的**完整绝对路径**。

进入 Windows：

```text
"C:/Program Files/AutoHotkey/v2/AutoHotkey64.exe" /ErrorStdOut "C:/Users/<用户名>/AppData/Local/Programs/DeskflowMacKeys/DeskflowMacKeys.ahk" enter
```

离开 Windows：

```text
"C:/Program Files/AutoHotkey/v2/AutoHotkey64.exe" /ErrorStdOut "C:/Users/<用户名>/AppData/Local/Programs/DeskflowMacKeys/DeskflowMacKeys.ahk" leave
```

不要在命令中保留 `<用户名>`、`%LOCALAPPDATA%` 等占位符：Deskflow 通过 QProcess 直接启动程序，不应依赖 shell 展开变量。

GUI 会保存到 `Deskflow.conf` 的 `[core]` 段，键名为：

```ini
enableEnterCommand=true
enterCommand=...
enableExitCommand=true
exitCommand=...
```

这段是字段说明，不是可直接覆盖配置的文件。GUI 命令中的引号与配置文件中的 QSettings 转义格式不同；手动配置优先使用 GUI。不要把回调写进 `deskflow-server.conf`。

5. 保存并重启 Deskflow，然后用 AutoHotkey v2 启动脚本。先在 Windows 测试复制粘贴，再松开修饰键切到 Mac，测试后回到 Windows。
6. 如果需要登录自启动，在当前用户的启动文件夹创建两个快捷方式：一个启动 Deskflow，另一个以 AutoHotkey64.exe 打开脚本。安装器可以自动完成这些步骤。

手动安装没有 `installation.json`，不适用本仓库自动卸载器。

## 从先前手工安装的版本迁移

如果现有配置已经工作正常，只备份仓库即可，不必重新安装。

需要迁移到仓库安装器时：

1. 在 Deskflow 设置中取消启用“进入／离开时运行命令”，并清空这两条属于 DeskflowMacKeys 的命令，然后退出 Deskflow。
2. 退出 AHK 托盘映射进程。
3. 将旧运行目录改名保存为本地备份，移除指向旧脚本的映射启动快捷方式。
4. 备份 VS Code／Cursor 的 `keybindings.json`，仅移除先前为本方案加入的四条 F13/F14 规则。保留其他个人快捷键。
5. 按 README 运行安装器。屏幕布局、证书和信任关系保持原配置。

首次手工部署留下的 `Disable-MacKeys.ps1` 带有当时机器路径，不放入本仓库作为通用卸载器。本仓库只包含参数化的安装／卸载脚本。

## 故障定位

| 现象 | 检查顺序 |
|---|---|
| Windows 的 Command+C 没反应 | AHK 托盘进程 → 是否手动暂停 → 键盘的左 Command 是否确实发出 LWin → 前台应用是否管理员运行 |
| Mac 上 Command 变成 Ctrl | `state.ini` 是否 `LocalScreen=0` → Deskflow 离开回调路径 → 是否还有 PowerToys／其他改键脚本做全局交换 |
| 回 Windows 后不恢复 | 是否手动暂停 → 进入回调路径 → `events.log` 是否出现 `Deskflow enter` |
| VS Code／Cursor 无法复制 | 是否添加 F13/F14 规则 → 当前是否使用其他 Profile 或便携版 User 目录 → F13/F14 是否被其他规则占用 |
| 终端复制变成中断 | 当前是不是已适配的终端；其他终端可能落入通用 Ctrl+C 路径，需要增加进程识别与对应复制键 |
| Command+L 锁屏 | 这是保留的 Windows 行为；地址栏使用 Ctrl+L |
| Command+Z／重做与预期不同 | 应用可能使用不同的撤销／重做键，或已自定义 Ctrl 快捷键 |
| 无法切屏 | 先暂停 AHK，检查 Deskflow 原生连接、计算机名称、屏幕布局、网络和证书 |
| 重装后无法连接 Mac | 新机器的地址和证书可能变了；重新核对和配对，不复用旧证书私钥 |
| 安装器提示已有回调 | 安装器会保留其他回调；先人工整合或移除本方案旧命令，再安装 |
| 卸载提示文件被修改 | 对照本地备份，仅移除本次 F13/F14 规则或启动项；不要用旧备份覆盖后来的个人设置 |

映射脚本一次只适配当前用户会话中的一个 `deskflow-core.exe`；不要同时启动多个 Deskflow 服务端实例。普通桌面模式是已验证方式；将 Deskflow 改为系统服务或提升权限运行后，应重新验证回调能否到达当前用户会话。

## 备份范围

重装所需的通用脚本和说明在 GitHub 仓库中。本机 `state.ini`、`installation.json`、日志、编辑器备份和 Deskflow 证书不应提交。

`installation.json` 用于当前安装的撤回，不是迁移到新电脑的配置模板。重装时重新安装依赖、建立 Deskflow 连接，然后运行安装器生成新记录。
