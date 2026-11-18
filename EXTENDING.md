# 扩展新的快捷操作

## 文件布局

运行时只有两个文件：`OrCADQuickTools.tcl` 和 `OrCADWheelZoom.exe`，同目录安装。

合并后的 Tcl 是可读的明文源码，不使用加密、压缩或运行时解包。文件顶部有模块目录；正文依次为核心操作/快捷键配置、XLSX 导出、跨页图形替换、鼠标导航控制、只读单击参数预览、全设计 PIN—网络采集；最后统一初始化。各模块有 BEGIN / END 分隔标记，功能函数继续使用各自的命名空间。

开发源码保存在 `src`：

| 文件 | 负责内容 |
| --- | --- |
| `src/OrCADQuickTools.core.tcl` | 公共函数、快捷操作、配置列表、菜单/帮助及初始化 |
| `src/OrCADPinNetXlsx.tcl` | XLSX 写入 |
| `src/OrCADOffPageToggle.tcl` | 跨页连接符图形替换 |
| `src/OrCADWheelZoom.tcl` | 鼠标导航控制 |
| `src/OrCADPartPreview.tcl` | 单击器件的只读参数显示、字段配置及菜单开关 |
| `src/OrCADDesignPinNetExport.tcl` | 当前 DSN 全部页面的 PIN—网络表采集与保存 |

开发时优先修改 `src`，再执行 `build_tcl_bundle.ps1` 生成根目录的 `OrCADQuickTools.tcl`。生成文件也能直接修改，但下次构建会覆盖它：直接修改后必须同步回相应 `src` 模块。

## 新增一个快捷键

只调整单击参数预览字段时，修改 `::PartPreview::Fields` 即可，不需要增加快捷键或改 EXE。每项三个字段：中文显示名（源码用 Unicode 转义）、优先顺序的属性键列表、可选原生读取方法。通用示例为 `[list "Custom field" {User_P/N} {}]`，属性键按字面名称读取。组织专用配置请仅保存在本机，不要提交到公开仓库。构建后运行 `test_part_preview.tcl` 与双文件集成测试。不要在回调中清空日志、调用 `sReleaseAllCreatedPtrs` 或修改器件属性；不得注销共享 `_cdnOrSchViewCmdComplete` 事件，以免影响其他插件。

下面仅为结构示例，不会默认启用或新增快捷键。

### 1. 在核心模块内增加独立命名空间和函数

```tcl
namespace eval ::MyNewTool {}

proc ::MyNewTool::Enabler {} {
    # 只有原理图视图有效时才启用。实际功能可增加选择对象检查。
    return [IsSchematicViewActive]
}

proc ::MyNewTool::Run {} {
    # 在这里实现功能；写入前检查作用范围，失败时明确报错。
    puts "My new tool executed."
}
```

源代码中的中文界面文字使用 `\uXXXX` 转义，避免 Capture 16.6 默认编码差异。中文注释可放在文档中；构建脚本要求模块源码为 ASCII 文本。

### 2. 在 ActionDefinitions 中增加一项配置

`::OrCADQuickTools::ActionDefinitions` 位于合并 Tcl 的靠前位置，是唯一的键盘功能配置列表。每项六个字段：

| 字段 | 说明 |
| --- | --- |
| ActionName | 稳定的内部动作名称；更新函数时保持名称与绑定不变，重新装入时保留原注册 ID |
| Hotkey | 快捷键，如 Alt+F12；先确认不冲突 |
| Label | 中文菜单和帮助文字 |
| Enabler | 判断功能是否可用的函数 |
| Callback | 执行功能的函数 |
| Context | Capture 的注册上下文，现有操作使用 Schematic |

按快捷键顺序把下面的示例条目加入 `return [list ...]`，注意相邻行的续行反斜杠：

```tcl
[list "My New Tool" "Alt+F12" \
    "\u65B0\u529F\u80FD" \
    "::MyNewTool::Enabler" "::MyNewTool::Run" "Schematic"]
```

注册、Accessories 菜单和 Alt+F1 帮助会自动读取此列表，不要另写一份 `RegisterAction`。初始化会检查重复动作名、重复快捷键（不区分大小写）、缺失函数和字段数量，并在改变原注册之前拒绝错误配置。

Capture 16.6 同一会话反复注销/注册可能留下失效的快捷键。当前注册器更新函数体但保留原动作 ID 和共享菜单事件；若改动快捷键、回调名称或注册上下文，应保存设计后重启，不要用反复 `UnregisterAction` 修复。

不要占用 Alt+F4；Alt+F11 跨页引用刷新已经撤回，不应未经验证再次启用。

### 3. 如果新增独立源码模块

将文件放进 `src`，在 `build_tcl_bundle.ps1` 的 `$modules` 列表中添加它，并在 `package_release.ps1` 的 `$sourceNames` 中登记。新模块会嵌入同一个入口文件，不增加运行时安装文件。必须在全部模块定义完成后才调用初始化；不要在新模块顶层执行原理图修改。

### 4. 构建、测试和打包

```powershell
.\build_tcl_bundle.ps1
.\test_tcl_bundle.ps1
.\test_wheel_zoom_native.ps1
.\package_release.ps1
```

涉及位号/页码、跨页替换、鼠标控制时，还应分别运行相应 Tcl 模拟测试，并在设计副本内验证。测试 Tcl 只在独立解释器中运行，禁止装入真实 Capture 的自动加载目录。

修改 C# 鼠标辅助程序后先运行 `build_wheel_zoom.ps1`，或打包时使用 `package_release.ps1 -RebuildMouseHelper`。默认打包保留已有 EXE，不重新编译已验证的鼠标程序。

打包同时生成仅含两个运行文件的 `*-runtime.zip` 和包含说明/源码/测试的完整分享包。不要把开发源码、测试脚本或旧模块重新复制回自动加载目录。

## 读取与写入 Capture 数据库

`::QuickToolsDbo::String` 适用于通过 CString 输出参数返回文本的 API。`Read` 适用于接收 DboState 并直接返回对象或数值的 API。两者都检查 Capture 返回的状态。

```tcl
set value [::QuickToolsDbo::String $part GetPartValue]
set ref [::QuickToolsDbo::String $part GetEffectivePropStringValue Reference]
set package [::QuickToolsDbo::Read $part GetPackage]
foreach pin [::QuickToolsDbo::Objects $part NewPinsIter NextPin delete_DboPartInstPinsIter] {
    set number [::QuickToolsDbo::String $pin GetPinNumber]
}
```

`Objects` 会释放迭代器，并在重复返回同一对象或遇到异常状态时停止。正常结束为空对象且调用成功，或者为空对象且状态为 1022。网络查询中的 1021 和 1043 只在网络查询返回空对象时才可按缺失处理。

`WriteStrings $object $method 1 ...` 会释放入参 CString，并要求写入方法返回有效状态。修改设计后仍需读回确认。批量写入先完成预检，再保存原值，以便失败时恢复。枚举返回的器件、引脚和缓存封装是 Capture 持有的对象。
