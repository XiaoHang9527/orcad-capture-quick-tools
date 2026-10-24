# 最新双文件安装包

当前公开版：**2026.10.24**。本目录仅保留本版，不再提供旧安装 ZIP；Git 提交历史不改写。

[下载 OrCADQuickTools-2026.10.24-runtime.zip](OrCADQuickTools-2026.10.24-runtime.zip?raw=true)

压缩包内仅有两个文件：

- `OrCADQuickTools.tcl`：12 个快捷键、精简中文帮助、参数预览和全部导出/编辑模块；全设计导出 0.1.2、跨页切换 0.2.5。
- `OrCADWheelZoom.exe`：滚轮/右键平移及 Signals 辅助，版本 `wheel-0.21-signals-reusable`。

公开版只配置通用属性，不含组织专用属性名、实际工程、BOM、日志、截图、备份或测试脚本。本机专用配置请另行保管。

## 安装

1. 保存设计并关闭 Capture，备份原工具及本机自定义配置。
2. 将两个文件放入**实际运行版本**的 `tools\capture\tclscripts\capAutoLoad`，不要放到另一套 16.6/17.4 路径。
3. 移出本工具旧独立模块、重命名备份；勿删除 Capture 自带脚本，也不要把 src/source/test 文件放进自动加载目录。
4. 两文件配套更新后重启，按 Alt+F1 核对。全设计导出为 **Alt+Shift+F6**，所选器件导出仍为 Alt+F6。

如果全设计导出报 WriteWorkbook 参数数量错误，在 Capture 中执行：

```tcl
puts [info args ::OrCADPinNetXlsx::WriteWorkbook]
```

本版应为 `pOutputFile pRows pTitle`；只有前两个表示运行时仍在使用旧接口，需排查重复脚本或安装路径并重启。本版无需 Microsoft Excel，WPS 可打开生成的 XLSX。

## SHA-256

| 文件 | SHA-256 |
| --- | --- |
| OrCADQuickTools-2026.10.24-runtime.zip | `467f4c358085b3c0e57f5253d99e8f6fb83042271c21eb6a88be50f87725728b` |
| OrCADQuickTools.tcl（解压后） | `af453302d7b7ca250ad6719ee943768de5528a51780ff90034542367d248ae2b` |
| OrCADWheelZoom.exe（解压后） | `b6b57b7e48ec12866e0c56927d5f9605edef8d895ab8a6660534720c94933d29` |

## 验证范围

Tcl 8.4 各模块模拟、双文件加载与 XLSX 包结构测试通过；x86/x64 各 463 项策略/ABI 检查、各 9 项只读监听生命周期检查及 Signals 复用服务动作替身测试通过。这些测试不向 Capture 发送命令，不等于所有软件版本实机验证。

主要开发环境为 16.6。旧版 0.20 的 Signals 曾由用户确认在 17.4、Ctrl+F2 下可用；0.21 提速效果、全设计大工程及新导出快捷键的十字光标行为仍需实测，不承诺无菜单闪现或固定响应速度。

更多内容见 [README](../README.md)、[中文速查](../快捷操作速查.md)、[更新记录](../CHANGELOG.md)。
