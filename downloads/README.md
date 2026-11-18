# 最新双文件安装包

当前版本为 **2026.11.18**。本目录提供本版安装包与校验值。

[下载 OrCADQuickTools-2026.11.18-runtime.zip](OrCADQuickTools-2026.11.18-runtime.zip?raw=true)

压缩包内仅有两个文件：

- `OrCADQuickTools.tcl`：12 个快捷键、精简中文帮助、参数预览和全部导出/编辑模块；全设计导出 0.1.2、跨页切换 0.2.5。
- `OrCADWheelZoom.exe` 提供滚轮、右键平移及 Signals 辅助，文件版本 `0.23.0.0`。

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

打包脚本自动生成 [安装 ZIP 校验值](OrCADQuickTools-2026.11.18-runtime.zip.sha256) 和 [解压后两个文件的校验值](OrCADQuickTools-2026.11.18-files.sha256)。

## 验证范围

Tcl 8.4.15 与 8.6.5 均通过模块模拟、双文件加载和 XLSX 结构测试。x86/x64 均通过辅助程序策略、ABI、Signals 监听及服务生命周期测试。Roslyn 两次编译的辅助程序 SHA-256 一致。

Capture 实机仍需在工程副本中验证未编号器件、自定义位号后缀和跨页字体。

更多内容见 [README](../README.md)、[中文速查](../快捷操作速查.md)、[更新记录](../CHANGELOG.md)。
