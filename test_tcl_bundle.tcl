# Pure Tcl 8.4 integration test; never run this mock inside Capture.
proc assert {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message}}
set ::registrations {}; set ::unregistrations {}; set ::menus {}
proc RegisterAction args {lappend ::registrations $args}
proc UnregisterAction args {lappend ::unregistrations $args}
proc AddAccessoryMenu args {lappend ::menus $args}
if {[info exists ::env(ORCAD_BUNDLE_TEST_ENTRY)]} {
    set entry $::env(ORCAD_BUNDLE_TEST_ENTRY)
} else {set entry [file join [file dirname [info script]] OrCADQuickTools.tcl]}
set output $::env(ORCAD_BUNDLE_TEST_XLSX)
source $entry
assert {[string first "\u53F3\u952E\u5355\u51FB\uFF1A\u4ECD\u663E\u793A\u539F\u6709\u83DC\u5355" [::QuickToolsHelp::ShortcutText]] < 0} "Native right-click description must not appear in help"
assert {[string first "Alt+S\uFF1A\u5355\u9009\u4E00\u6839\u5BFC\u7EBF" [::QuickToolsHelp::ShortcutText]] >= 0} "Signals usage missing from help"
assert {[string first "Alt+F5\uFF1A\u9009\u4E2D\u8DE8\u9875\u7B26\u53F7\u672C\u4F53" [::QuickToolsHelp::ShortcutText]] >= 0} "Off-page usage missing from help"
assert {[string first "\u4FEE\u6539\u8BBE\u8BA1\u524D\u8BF7\u5907\u4EFD" [::QuickToolsHelp::ShortcutText]] >= 0} "Backup guidance missing from help"
assert {[string first "\u4F5C\u8005\uFF1A\u5C0F\u822A" [::QuickToolsHelp::ShortcutText]] >= 0} "Help author name missing"
assert {[string first "\u8054\u7CFB\u65B9\u5F0F\uFF08VX\uFF09\uFF1AXiaoHang_Sky" [::QuickToolsHelp::ShortcutText]] >= 0} "Help author WeChat missing"
assert {[llength $::registrations] == 13} "Expected eleven actions plus two shared menu callbacks"
assert {[llength $::unregistrations] == 0} "Do not unregister native accelerators on load"
set hotkeys {}
foreach registration [lrange $::registrations 0 10] {lappend hotkeys [lindex $registration 2]}
assert {$hotkeys eq {Alt+F1 Alt+F2 Alt+F3 Alt+F5 Alt+F6 Alt+F7 Alt+F8 Alt+F9 Alt+F10 Alt+R Alt+S}} "Merged hotkeys changed"
foreach command {::OrCADPinNetXlsx::WriteWorkbook ::OffPageDirection::Run ::OrCADWheel::Toggle} {
    assert {[llength [info commands $command]] == 1} "Embedded module missing"
}
assert {$::OrCADWheel::Directory eq [file dirname $entry]} "Helper directory is not the merged entry directory"
assert {![file exists [file join [file dirname $entry] OrCADPinNetXlsx.tcl]]} "Test must exclude separate XLSX module"
assert {![file exists [file join [file dirname $entry] OrCADOffPageToggle.tcl]]} "Test must exclude separate off-page module"
assert {![file exists [file join [file dirname $entry] OrCADWheelZoom.tcl]]} "Test must exclude separate mouse module"
::QuickToolsHelp::AddAccessoryMenus
assert {[llength $::menus] == 12} "Merged menu changed"

# Validate extension records and refuse errors before any registration changes.
set definitions [::OrCADQuickTools::ActionDefinitions]
proc ::BundleTestEnabler {} {return 1}
proc ::BundleTestRun {} {return}
set extra [list "Bundle Test Extension" "Alt+F12" "Test extension" ::BundleTestEnabler ::BundleTestRun Schematic]
::OrCADQuickTools::ValidateActions [concat $definitions [list $extra]]
set duplicate [lindex $definitions 0]
lset duplicate 0 "Different Action With Conflicting Key"
lset duplicate 1 "alt+f1"
assert {[catch {::OrCADQuickTools::ValidateActions [concat $definitions [list $duplicate]]}]} "Duplicate hotkey accepted"
set missing $extra; lset missing 4 ::CommandDoesNotExist
assert {[catch {::OrCADQuickTools::ValidateActions [list $missing]}]} "Missing callback accepted"
assert {[catch {::OrCADQuickTools::ValidateActions [list [list bad short]]}]} "Short action record accepted"
rename ::OrCADQuickTools::ActionDefinitions ::OrCADQuickTools::TestOriginalDefinitions
proc ::OrCADQuickTools::ActionDefinitions {} {return [concat [::OrCADQuickTools::TestOriginalDefinitions] [list $::extra]]}
assert {[llength [::QuickToolsHelp::ShortcutItems]] == 12} "Extension not shared with help/menu"
assert {[string first Alt+F12 [::QuickToolsHelp::ShortcutText]] >= 0} "Extension help missing"
set ::extra $duplicate
set count [llength $::registrations]
assert {[catch {::OrCADQuickTools::RegisterActions}]} "Invalid registry not rejected"
assert {[llength $::registrations] == $count} "Invalid registry partially changed registration"
rename ::OrCADQuickTools::ActionDefinitions {}
rename ::OrCADQuickTools::TestOriginalDefinitions ::OrCADQuickTools::ActionDefinitions

# A reload must preserve controller state/timers, never launch another helper.
set ::OrCADWheel::StateFile saved-state
set ::OrCADWheel::Enabled 1
set savedTimer [after 300000 {error "Test timer unexpectedly fired"}]
set ::OrCADWheel::Timer $savedTimer
source $entry
assert {[llength $::registrations] == 13 && [llength $::unregistrations] == 0} "Reload changed native accelerators/menu events"
assert {$::OrCADWheel::StateFile eq "saved-state" && $::OrCADWheel::Enabled == 1 && $::OrCADWheel::Timer eq $savedTimer} "Reload reset controller state"
after cancel $savedTimer
set ::OrCADWheel::Enabled 0; set ::OrCADWheel::Timer ""

# Centralized initialization schedules automatic startup only once.
proc IsSchematicViewActive {} {return 1}
rename ::OrCADWheel::AutoStart ::OrCADWheel::TestOriginalAutoStart
set ::startupCalls 0
proc ::OrCADWheel::AutoStart {} {incr ::startupCalls}
::OrCADWheel::Initialize
::OrCADWheel::Initialize
update idletasks
assert {$::startupCalls == 1} "Automatic helper startup scheduled more than once"
::OrCADQuickTools::Initialize
update idletasks
assert {$::startupCalls == 1} "Reload scheduled another helper startup"
rename ::OrCADWheel::AutoStart {}
rename ::OrCADWheel::TestOriginalAutoStart ::OrCADWheel::AutoStart
rename IsSchematicViewActive {}

# Actual export from the single entry, with numeric pin ordering and escaping.
set controlText "A[binary format c 0][binary format c 8][binary format c 11][binary format c 12][binary format c 14][binary format c 31]B"
assert {[::OrCADPinNetXlsx::XmlEscape $controlText] eq "AB"} "Normalized control-character regex changed behavior"
set rows [list \
    [list "P03. \u6D4B\u8BD5" U301 "=SUM(1,2)" 10 OUT "NET<&>" Connected] \
    [list "P03. \u6D4B\u8BD5" U301 "=SUM(1,2)" 2 IN "NET2" Connected] \
    [list "P03. \u6D4B\u8BD5" U301 "=SUM(1,2)" 1 GND "" Unconnected]]
::OrCADPinNetXlsx::WriteWorkbook $output $rows
assert {[file exists $output] && [file size $output] > 0} "Merged XLSX writer failed"
puts "PASS: two-file loading, eleven shortcuts, menu/help registry, safe extensions, reload state and XLSX creation"
