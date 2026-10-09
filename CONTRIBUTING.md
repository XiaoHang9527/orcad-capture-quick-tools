# 参与更新

欢迎通过 Issue 记录问题或提出新功能建议。

提交问题时建议包含：

- OrCAD Capture 的具体版本；
- 操作步骤和使用的快捷键；
- 预期结果与实际结果；
- Capture Command Window 中的相关输出；
- 已脱敏的截图或最小示例工程。

提交代码前，按涉及的功能运行测试：

- `test_page_auto_annotate.tcl`：页码、位号、中文帮助与菜单。
- `test_offpage_toggle.tcl`：跨页符号替换及失败恢复，首次与连续快捷操作无说明弹窗，真实失败仍有错误提示。
- `test_wheel_zoom.tcl`：鼠标组件启动、回执、心跳、偏好与关闭，成功开关不弹说明，启动失败仍提示。
- `test_signals_navigation.tcl`：单选导线、延后启动、启动前换页/改选取消、结果回执、错误日志、禁止重复分派 14844，以及只有后台启动返回后才发布握手标记。不能将模拟请求的 A/B 网络变化当作原生 Signals 面板刷新已验证；原生验证须另行观察真实列表及 Capture 查找日志，0.17 的本机实测记录见 CHANGELOG。
- `test_wheel_zoom_native.ps1`：分别编译并运行 x86/x64 鼠标导航策略、消息编码和结构布局测试。
- `test_tcl_bundle.ps1`：在双文件隔离目录中实际加载合并 Tcl，检查注册/菜单/帮助、扩展冲突、重复加载、单次自动启动和 XLSX 文件内容。

Tcl 测试建议使用 Capture 安装附带的 Tcl 8.4 解释器，在源码目录运行；不要在正在编辑真实设计的 Capture 中执行 mock 测试。测试脚本不可放进 `capAutoLoad`。

开发优先修改 `src` 下的四个 Tcl 模块，再运行 `build_tcl_bundle.ps1` 生成根目录合并入口。新增功能按 `EXTENDING.md` 在共享配置中登记，不重复编写注册、帮助和菜单。直接修改生成文件后须同步回源模块，否则下次构建会覆盖修改。

`build_wheel_zoom.ps1` 编译鼠标辅助程序；`package_release.ps1` 生成双文件安装 ZIP 和含说明/源码的开发分享包。仅 `OrCADQuickTools.tcl` 与 `OrCADWheelZoom.exe` 用于安装。默认复用已有 EXE，修改 C# 后先编译或加 `-RebuildMouseHelper`。输出在 `dist`，不覆盖旧分享包，不自动发布 GitHub。

避免把实际工程、BOM、日志、私人截图或个人路径提交到仓库。模拟测试通过仍需设计副本实机验证；请分别记录“模拟测试通过”和“用户实机确认”，不要混为一谈。

