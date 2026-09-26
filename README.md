# OrCAD Capture Quick Tools

面向 Cadence OrCAD Capture 的 Tcl 快捷工具集合。目前主要在 **OrCAD Capture 16.6** 上开发和验证，后续会继续增加原理图效率功能。

## 功能与快捷键

| 快捷键 | 功能 |
| --- | --- |
| `Alt+F1` | 显示中文快捷键帮助 |
| `Alt+F2` | 给所选器件的 Value 前添加 `NC,` |
| `Alt+F3` | 删除所选器件 Value 开头的 `NC,` |
| `Alt+R` | 将所选新增器件修正到当前页的位号段 |
| `Alt+F6` | 将所选器件的引脚—网络关系导出为 `.xlsx` |
| `Alt+F7` | 批量同步所有页面标题栏的项目名和页面标题 |
| `Alt+F8` | 从左到右、从上到下重新排列当前页器件位号 |
| `Alt+F9` | 使用现有 `Page Number` 重新排列所有页面器件位号 |
| `Alt+F10` | 根据页面名称顺序重置 `Page Number / Page Count`，不修改位号 |

所有功能也可以从 `Accessories → 快捷工具` 菜单中查看和执行。

## 安装

将以下两个文件复制到 Capture 的自动加载目录：

- `OrCADQuickTools.tcl`
- `OrCADPinNetXlsx.tcl`

OrCAD Capture 16.6 的常见目录：

```text
C:\Cadence\Cadence_SPB_16.6\tools\capture\tclscripts\capAutoLoad\
```

重启 Capture，打开任意原理图页，然后按 `Alt+F1` 检查脚本是否加载成功。

也可以在 Capture 的 Command Window 中临时加载：

```tcl
source {C:/Cadence/Cadence_SPB_16.6/tools/capture/tclscripts/capAutoLoad/OrCADQuickTools.tcl}
```

## 使用说明

### NC 标记

框选一个或多个器件后：

- `Alt+F2`：`10K` → `NC,10K`
- `Alt+F3`：`NC,10K` → `10K`

只处理器件实例，选中的导线、文字等对象会被忽略。

### 修正新增器件位号

在当前页选中新增器件后按 `Alt+R`。例如第 3 页已有 `R301`、`R302`，新增器件是 `R3002`，修正后会变成 `R303`。

### 导出引脚—网络表

选择器件后按 `Alt+F6`，直接生成标准 `.xlsx` 文件，不依赖 Microsoft Excel，可使用 WPS 打开。器件引脚按自然数字顺序排列，例如 `1、2、3……10、11`。

### 同步标题栏

按 `Alt+F7` 后输入项目名：

- 所有标题栏的 `Doc` 更新为输入的项目名；
- 每页标题栏的 `Title` 与该页实际 Page Name 同步。

### 页码与位号

- `Alt+F8`：只重排当前页位号。
- `Alt+F9`：使用标题栏现有的 `Page Number` 重排所有页位号，不改页码。
- `Alt+F10`：只重置 `Page Number / Page Count`，不改位号。

如果需要同时更新页码和全部位号，请依次执行：

1. `Alt+F10`
2. `Alt+F9`

页面名称支持自然排序，例如 `P2 < P10`、`2 < 10`；没有数字时按名称排序。每种位号前缀在每页独立编号，例如第 3 页使用 `R301–R399`、`C301–C399`。

## 安全说明

- 修改原理图前请先备份设计文件。
- 页码和位号写入后都会进行读回校验；失败时脚本会尝试恢复原值。
- 单页同一前缀最多支持 99 个位号。
- 多单元器件会继续共用同一个位号。
- 复用层次原理图目前会停止自动重排，避免错误修改 occurrence 数据。
- PCB、ECO 或外部网表已经依赖现有位号时，请谨慎使用位号重排功能。

## 文件

- `OrCADQuickTools.tcl`：主程序和快捷键注册。
- `OrCADPinNetXlsx.tcl`：无需 Excel 的纯 Tcl XLSX 写入模块。
- `test_page_auto_annotate.tcl`：页码、位号及菜单功能的模拟测试。

## 兼容性

- 已验证：Cadence OrCAD Capture 16.6、Tcl 8.4。
- 其他 Capture 版本可能需要调整 Tcl API 或安装路径，欢迎提交 Issue 反馈。

