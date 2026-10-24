# OrCAD Capture Quick Tools

OrCAD Capture 原理图快捷工具集。最新公开版：**2026.10.24**，安装仅需 **TCL + EXE 两个文件**。

[下载最新双文件安装包](downloads/OrCADQuickTools-2026.10.24-runtime.zip?raw=true) · [校验值与安装说明](downloads/README.md) · [中文快捷操作速查](快捷操作速查.md) · [扩展指南](EXTENDING.md)

作者：小航；联系方式（VX）：`XiaoHang_Sky`。工具内按 `Alt+F1` 查看中文帮助。下载目录仅保留当前安装包，Git 提交历史保留。

## 本版内容

- **12 个快捷键**，注册、菜单与帮助共享同一配置表。全设计 PIN—网络导出使用 `Alt+Shift+F6`；`Alt+F6` 仍只导出所选器件。
- 全设计导出模块 **0.1.2**：遍历当前 DSN 的所有 schematic／原理图页；无网络引脚兼容 NULL 与 1021/1043 状态，真实读取异常仍停止，不静默漏引脚。
- 跨页图形切换 **0.2.5**：补齐查库时的原生会话 Tcl 包装与预检，不删除或缓存借用会话。
- 单击器件参数预览 **0.1**：只读显示位号、Value、封装、描述、物料编码和厂家；空字段跳过。公开版只有通用字段，可在本机配置自定义属性。
- 鼠标辅助程序 **0.21**（`wheel-0.21-signals-reusable`）：滚轮缩放、右键平移及 Signals 进程复用、菜单识别优化。不承诺零延迟、无菜单闪现或必然提速。
- `Alt+F1` 帮助已精简；普通首次使用说明不弹窗，真正错误、批量修改确认仍保留。

## 快捷操作

| 快捷键 / 操作 | 功能 | 范围 |
| --- | --- | --- |
| `Alt+F1` | 显示中文快捷帮助 | 原理图窗口 |
| `Alt+F2` | 在 Value 开头添加 `NC,` | 所选器件 |
| `Alt+F3` | 去掉 Value 开头的 `NC,` | 所选器件 |
| `Alt+F5` | 切换跨页符号输入/输出图形，保留网络名称 | 所选跨页符号 |
| `Alt+F6` | 导出所选器件 PIN—网络表为 XLSX | 所选器件 |
| `Alt+Shift+F6` | 导出全部器件 PIN—网络表为 XLSX | 当前 DSN 全部页 |
| `Alt+F7` | 统一标题栏 Doc，Title 同步实际页名 | 当前设计全部页 |
| `Alt+F8` | 按位置重排器件位号 | 当前页 |
| `Alt+F9` | 使用现有 Page Number 重排全部位号 | 当前设计全部页 |
| `Alt+F10` | 重置 Page Number / Page Count，不改位号 | 当前设计全部页 |
| `Alt+R` | 修正新增器件位号到当前页号段，其他器件不动 | 所选器件 |
| `Alt+S` | 打开所选网络的原生 Signals 导航 | 单选一根导线 |
| 直接滚动鼠标滚轮 | 上滚放大、下滚缩小，无需 Ctrl | 可见绘图区 |
| 按住右键拖动 | 画布跟随鼠标平移，松开停止 | 可见绘图区 |
| 单击器件本体 | 在 Command Window / Session Log 显示参数 | 单个器件 |

菜单入口：`Accessories → 快捷工具`，包括鼠标导航和单击器件参数预览两个开关。开关状态会记住。

`Alt+Shift+F6` 与 `Shift+Alt+F6` 是同一组合。此前 `Ctrl+Alt+F6` 执行后出现过全屏十字光标；用户确认单按 F6 可恢复。新组合是否仍连带触发原生光标切换尚待实机确认，也可通过菜单执行。工具不自动发送 F6 或强制改变光标偏好。

`Alt+F4` 不属于本工具，`Alt+F11` 跨页引用刷新已撤回。BOM 自动过滤、BOM/库属性同步、全网络单节点检查不是本版功能。

## 安装与更新

1. 保存工程、关闭 Capture，备份旧工具和本机自定义配置。
2. 下载上方 ZIP，仅将 `OrCADQuickTools.tcl` 和 `OrCADWheelZoom.exe` 放入同一 `tools\capture\tclscripts\capAutoLoad` 目录。**17.4 必须使用实际运行的 17.4 安装目录，不要误放到另一版本路径。**
3. 将本工具旧的独立模块、重命名备份移出自动加载目录；不要删除 Capture 自带脚本。不要把 `src/source`、`test_*.tcl` 或开发分享包整体复制进去。
4. 同时更新两文件后重启 Capture，打开原理图，按 `Alt+F1` 核对新快捷键。
5. 组织专用字段和自定义绑定请自行迁移到本机源码后重新构建，不要将私有配置提交到公开仓库。

EXE 缺失时，鼠标增强和 Alt+S 不可用；其他纯 Tcl 操作仍可使用。0.21 的 Signals 复用需要匹配的新版 TCL 和 EXE，不要只换一个文件。关闭鼠标导航不影响 Signals。

同一会话重载 Tcl 会保留已注册动作，避免重复注册导致失效；改变绑定或修正混合版本后须重启，不依赖热加载清除旧状态。默认绑定可在 `::OrCADQuickTools::ActionDefinitions` 修改；不要全局替换所有文字。

## 使用与限制

### PIN—网络表

`Alt+F6` 导出选中器件，`Alt+Shift+F6` 无需选择即可读取当前一个 DSN 的全部页。生成标准 XLSX，WPS/Excel 均可打开，**无需安装 Microsoft Excel**，不调用 Office 自动化。

器件信息按区块显示一次，明细为 Pin Number / Pin Name / Net Name / Connection。引脚自然排序为 `1、2、3…10、11`，字母数字引脚为 `A2 < A10`。全设计导出按 schematic／page、位号自然排序，独立放置单元分组，避免同位号单元误合并。

保留 NC 器件及未连接引脚，未连接项标红；无引脚单元在完成统计中单列，不生成假引脚行。表中 Parts 是实际有引脚的分组数。读取与导出不修改原理图，不生成网表、不切换页面或改选择。

范围仅为当前 DSN，不合并多个 DSN，不展平重复层级 occurrence；检测到重复层级或无法核验时停止，不能把定义页冒充完整实例数据。真实读取异常停止，不保存不完整采集结果。大设计会增加临时内存与等待时间，取消保存不会遍历设计。

### 页码与位号

- 新增器件修正：第 3 页已有 R301/R302，误编号 R3002 可用 Alt+R 续编到空号。
- Alt+F8/F9 按从左到右、从上到下规划，每页、每种前缀独立编号：第 3 页 R301–R399，第 23 页 Q2301–Q2399；同页同前缀最多 99 个，多单元器件保持共用位号。
- 同时重置页码与位号：**Alt+F10 → 检查页码 → Alt+F9 → 检查位号**。
- 页名自然排序支持 P2 < P10、2 < 10，无数字按名称排序，不等于读取项目树任意手工排序。Title 不代替实际 Page Name，位号号段以 Page Number 为准。
- Alt+F7 处理标题栏 Doc 和 Title；其他自定义标题栏字段需要适配，不重命名工程或页面。

位号重排可能影响 PCB、ECO 及外部网表，首次请用工程副本验证。修改有校验和失败恢复，但不保证损坏设计可恢复。

### 跨页符号与 Signals

Alt+F5 须选符号本体，不是名称文字。支持 `OFFPAGELEFT-L ↔ OFFPAGELEFT-R`、`OFFPAGELEFT/L ↔ OFFPAGELEFT/R`；不增加任意自定义符号配对。只切换图形，保留网络名称/连接点，不修改引脚电气类型或刷新跨页引用页码。失败恢复提示仍保留；恢复失败时勿保存测试副本，应重开备份。

Alt+S 须单选一根导线并让鼠标停在该线上，按下并松开组合键。临时打开原生右键菜单、识别 Signals 后执行，不直接向绘图区盲发 14844，也不重复执行。仅选网络名文字、器件、总线或多选时不执行。

0.21 首次启动 Signals 专用进程，后续复用，Capture 关闭后退出。收尾允许鼠标悬停，新点击、滚轮或按键等会取消；不移动指针，不模拟左键。日志 `pane result not verified` 只表示没有自动读回面板，不等于失败。首次请连续选两个不同网络核对真实列表。

### 单击参数与鼠标导航

参数预览只在原生单击完成事件后读取当前单个器件，无轮询、额外进程或设计写入。同一器件参数不变时不刷屏；字段/别名位于 `src/OrCADPartPreview.tcl` 的 `::PartPreview::Fields`，可按扩展指南在本机添加自定义项。公开版不包含组织专用属性键。

鼠标增强只作用于真实可见绘图区；项目树、表格、弹窗、其他软件及有修饰键时保留原操作。返回 Capture 绘图区无需先左键激活。平移受原生滚动范围限制，整页显示时可能无空间。

右键单击仍由原生输入回放，拖动不走该回放路径。新输入、切窗、弹窗会取消不安全的待处理操作。组件心跳异常时有限频恢复：至少间隔 10 秒、每分钟最多 3 次；手动关闭不会自动重开。不重启 Capture。

## 兼容性与错误排查

主要开发环境：Capture 16.6 / Tcl 8.4。旧版 0.20 的 Signals 已有用户确认在 17.4、Ctrl+F2 自定义绑定下可用；**不代表本版所有功能均已在 17.4 实机通过**。模拟回归测试与用户实测分开记录。

17.4 曾报告全设计导出报错：

```text
wrong # args: should be "::OrCADPinNetXlsx::WriteWorkbook pOutputFile pRows"
```

已在独立 Tcl 中复现：新版调用传三个参数，但运行时加载了只收两个参数的旧写入函数。它发生在写文件之前，不是 Excel 缺失或本次网络查询失败。具体哪个文件覆盖需检查该电脑的加载路径。

在 Capture Command Window 执行只读检查：

```tcl
puts [info args ::OrCADPinNetXlsx::WriteWorkbook]
```

本版应输出 `pOutputFile pRows pTitle`。少了 pTitle 时，完整更新合并 TCL、排查重复旧模块并重启，不要只剪贴新功能或直接删第三个参数来绕过错误。

| 问题 | 诊断位置 |
| --- | --- |
| 全设计导出、标题栏、页码/位号 | Capture Command Window |
| 所选器件导出失败 | `%TEMP%\OrCADPinNetExport.log` |
| 跨页图形替换 | `%TEMP%\OrCADOffPageToggle.log` |
| 鼠标导航 | `%TEMP%\OrCADWheelZoom-<PID>.log` 和 `OrCADWheelZoom-<PID>-controller.log` |
| Signals | `%TEMP%\OrCADSignalsNavigation.log` 和 `OrCADSignalsNavigation-native.log` |

反馈请提供软件版本、步骤、预期/实际结果及脱敏日志，不公开工程、BOM、截图或专用物料信息。

## 资源占用与开发

普通快捷功能按需执行；批量导出临时占用与设计大小有关。鼠标增强有常驻辅助程序及计时器；Signals 首次使用后增加一份复用进程，空闲无 Signals 输入监听，但不是零资源占用。关闭鼠标导航只停止该鼠标进程，不影响独立 Signals 服务。具体 CPU/内存应在实际电脑测量。

源码分六个 Tcl 模块，运行时不依赖独立源码文件：

- `build_tcl_bundle.ps1`：生成合并 TCL；`build_wheel_zoom.ps1`：编译 C# 辅助程序。
- `test_*.tcl`：各模块隔离模拟；`test_tcl_bundle.ps1`：双文件加载及真实 XLSX 包结构。
- `test_wheel_zoom_native.ps1`：x86/x64 策略及 ABI；可选只读监听生命周期、Signals 服务动作替身测试。
- `package_release.ps1`：生成安装 ZIP 和开发包；默认保留现有 EXE，修改 C# 后先编译。
- [扩展指南](EXTENDING.md)、[参与更新](CONTRIBUTING.md)、[更新记录](CHANGELOG.md)。

禁止把模拟测试加载进真实 Capture。仓库当前下载仅留最新版；本机备份、开发测试产物及提交历史不因清理下载而删除。

