# 双文件安装包

最新版本：**2026.10.10 / 鼠标辅助组件 0.20**；主要开发环境：OrCAD Capture 16.6 / Tcl 8.4。

[下载最新 OrCADQuickTools-2026.10.10-v0.20-runtime.zip](OrCADQuickTools-2026.10.10-v0.20-runtime.zip?raw=true)

压缩包中仅包含以下两个运行文件，不含工程、BOM、日志、截图、备份或测试脚本：

- `OrCADQuickTools.tcl`：11 个快捷键、中文帮助、菜单和合并功能模块；跨页图形切换模块 0.2.4。
- `OrCADWheelZoom.exe`：滚轮缩放、右键拖动及 Signals 辅助；版本 `wheel-0.20-signals-key-independent`。

0.20 不再固定等待 Alt/S 松开；允许启动时已按住的快捷键重复/首次释放，Signals 返回后立即尝试收起本次匹配菜单。菜单收尾内部等待上限 60 毫秒，不是总显示时间保证，不承诺完全无闪现。默认绑定仍是 Alt+S；Ctrl+F2 等自定义绑定及 Capture 17.4 实机效果待用户确认。

保存设计并关闭 Capture，备份旧工具，再将两文件放入同一 `capAutoLoad` 目录。旧独立模块须移出自动加载目录，勿删除软件自带脚本。重启后按 `Alt+F1` 查看帮助。首次使用修改功能仍建议在设计副本上验证。

已将 TCL 自定义为 Ctrl+F2 的用户：可保留自己的兼容 TCL，仅更新包内 0.20 EXE 并重启测试，避免覆盖自定义绑定。不要对源码做不受控的全局替换；后续完整升级须自行合并配置。

2026.10.10 安装包已通过 Tcl 8.4 隔离加载、XLSX 内容及各功能模拟回归；C# x86/x64 各 433 项策略/结构检查、9 项只读临时监听生命周期检查通过。模拟测试不代表所有 Capture 版本或自定义快捷键已实机验证。

## SHA-256 校验值

| 文件 | SHA-256 |
| --- | --- |
| OrCADQuickTools-2026.10.10-v0.20-runtime.zip | `2e13ce17570d80fc0bf77792870dae96fd58d360ce4cfd845505c10405cfa6b6` |
| OrCADQuickTools.tcl（0.20 包，解压后） | `1fd13ecfc7d8c694ecd08a9311a0b556750f54e9ef69d96d6fc893bbe9f6a83b` |
| OrCADWheelZoom.exe（0.20 包，解压后） | `cb7bfdb73ae9730957966bce5bb4721fe20898b8d57f454e41a03a98a04a33f3` |

## 历史版本 / 回退

[下载 2026.10.09 / 0.17 安装包](OrCADQuickTools-2026.10.09-runtime.zip?raw=true)。回退前保存设计并关闭 Capture，备份当前工具后替换两个文件。

| 文件 | SHA-256 |
| --- | --- |
| OrCADQuickTools-2026.10.09-runtime.zip | `d86589d46d55883f6a36775e85395b40e7099f02b54aead31e310233e7ba85d9` |
| OrCADQuickTools.tcl（解压后） | `1ea0e3cd6a9c2c4c0872cdd0d3a9f5cbd35696245749f60a128cea8c0701a5db` |
| OrCADWheelZoom.exe（解压后） | `3f9b53f4b0b86d1c9cfda1f04af8cb22d055283828138e483a192ab0050a6afd` |

更多说明见仓库 [README](../README.md)、[快捷操作速查](../快捷操作速查.md) 和 [更新记录](../CHANGELOG.md)。
