# 双文件安装包

版本：2026.10.09；适用环境：OrCAD Capture 16.6 / Tcl 8.4。

[下载 OrCADQuickTools-2026.10.09-runtime.zip](OrCADQuickTools-2026.10.09-runtime.zip?raw=true)

压缩包中仅包含以下两个运行文件，不含工程、BOM、日志、截图、备份或测试脚本：

- `OrCADQuickTools.tcl`：11 个快捷键、中文帮助、菜单和合并功能模块；跨页图形切换模块 0.2.4。
- `OrCADWheelZoom.exe`：滚轮缩放、右键拖动及 Signals 辅助；版本 `wheel-0.17-signals-launch-handshake`。

保存设计并关闭 Capture，备份旧工具，再将两文件放入同一 `capAutoLoad` 目录。旧独立模块须移出自动加载目录，勿删除软件自带脚本。重启后按 `Alt+F1` 查看帮助。首次使用修改功能仍建议在设计副本上验证。

2026.10.09 安装包已通过 Tcl 8.4 隔离加载、XLSX 内容及各功能模拟回归；C# x86/x64 各 295 项策略/结构检查通过。模拟测试不代表所有 Capture 版本已实机验证。

## SHA-256 校验值

| 文件 | SHA-256 |
| --- | --- |
| OrCADQuickTools-2026.10.09-runtime.zip | `d86589d46d55883f6a36775e85395b40e7099f02b54aead31e310233e7ba85d9` |
| OrCADQuickTools.tcl（解压后） | `1ea0e3cd6a9c2c4c0872cdd0d3a9f5cbd35696245749f60a128cea8c0701a5db` |
| OrCADWheelZoom.exe（解压后） | `3f9b53f4b0b86d1c9cfda1f04af8cb22d055283828138e483a192ab0050a6afd` |

更多说明见仓库 [README](../README.md)、[快捷操作速查](../快捷操作速查.md) 和 [更新记录](../CHANGELOG.md)。
