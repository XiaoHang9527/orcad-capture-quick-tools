# Deterministic controller tests: no Capture process, hook, or filesystem writes.
source [file join [file dirname [info script]] src OrCADWheelZoom.tcl]
proc assert {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message}}
rename exec nativeExec
proc exec args {lappend ::launches $args; if {$::failLaunch} {error "launch failure"}; return 123}
rename file nativeFile
proc file {method args} {
    if {$method == "exists"} {return [expr {[lindex $args 0] == "mock/OrCADWheelZoom.exe" ? $::helperExists : [info exists ::files([lindex $args 0])]}]}
    if {$method == "mtime"} {return [expr {[clock seconds] - $::statusAge}]}
    if {$method == "mkdir"} {return}
    return [eval [linsert $args 0 nativeFile $method]]
}
rename ::OrCADWheel::ReadText ::OrCADWheel::NativeReadText
rename ::OrCADWheel::WriteText ::OrCADWheel::NativeWriteText
proc ::OrCADWheel::ReadText {path} {return $::files($path)}
proc ::OrCADWheel::WriteText {path value} {
    if {$::failWrite && $path == "mock-state"} {error "file temporarily locked"}
    set ::files($path) $value
}
rename ::OrCADWheel::Log ::OrCADWheel::NativeLog
proc ::OrCADWheel::Log {message} {lappend ::controllerLogs $message}
proc IsSchematicViewActive {} {return $::schematic}
proc tk_messageBox args {lappend ::messages $args; return ok}
set ::launches {}; set ::messages {}; set ::failLaunch 0
set ::failWrite 0; set ::controllerLogs {}
set ::helperExists 1; set ::statusAge 0; set ::schematic 1
set ::OrCADWheel::Directory mock
set ::OrCADWheel::StateFile mock-state
set ::OrCADWheel::Preference mock-preference

# Replace the heartbeat's file writer with the shared, mocked WriteText path.
::OrCADWheel::Enable 1
assert {$::OrCADWheel::Enabled && !$::OrCADWheel::Running} "Enable claimed ready before acknowledgment"
assert {[llength $::messages] == 0} "Premature success dialog"
assert {$::files(mock-state) == "hover 1"} "Hover state missing"
assert {[llength $::launches] == 1} "Helper should launch once"
::OrCADWheel::Enable
assert {[llength $::launches] == 1} "Duplicate helper launch"
after cancel $::OrCADWheel::CheckTimer
set ::files(mock-state.status) "running received=0 remapped=0"
::OrCADWheel::CheckStarted 0 1
assert {$::OrCADWheel::Running && [llength $::messages] == 0} "Startup failed or opened a usage popup"
assert {$::files(mock-preference) == 1} "Enable preference missing"
after cancel $::OrCADWheel::Timer
set ::schematic 0
::OrCADWheel::Heartbeat
assert {$::files(mock-state) == "hover 0"} "Controller must permit native hover checks when an edit owns focus"
::OrCADWheel::Toggle
assert {!$::OrCADWheel::Enabled && !$::OrCADWheel::Running} "Disable did not clear state"
assert {$::OrCADWheel::Timer == "" && $::OrCADWheel::CheckTimer == ""} "Timers leaked"
assert {$::files(mock-preference) == 0} "Disable preference missing"
assert {[llength $::messages] == 0} "Mouse navigation toggle opened a usage popup"
set count [llength $::launches]
::OrCADWheel::AutoStart
assert {[llength $::launches] == $count} "Ignored disabled preference"

# Toggle on must not treat Tcl return status as an error or show early success.
set ::messages {}
::OrCADWheel::Toggle
assert {$::OrCADWheel::Enabled && [llength $::messages] == 0} "Toggle startup error"
after cancel $::OrCADWheel::CheckTimer
::OrCADWheel::CheckStarted 25 1
assert {!$::OrCADWheel::Enabled && [llength $::messages] == 1} "Timeout was not reported"

::OrCADWheel::Enable
after cancel $::OrCADWheel::CheckTimer
set ::files(mock-state.status) "error: hook failed"
::OrCADWheel::CheckStarted 0 0
assert {!$::OrCADWheel::Enabled} "Native startup error not handled"

::OrCADWheel::Enable
after cancel $::OrCADWheel::CheckTimer
set ::files(mock-state.status) running
::OrCADWheel::CheckStarted 0 0
after cancel $::OrCADWheel::Timer
set ::statusAge 10
::OrCADWheel::Heartbeat
assert {$::OrCADWheel::Enabled && $::OrCADWheel::Running} "One stale sample disabled navigation"
set before [llength $::launches]
after cancel $::OrCADWheel::Timer
::OrCADWheel::Heartbeat
assert {[llength $::launches] == $before} "Recovery before repeated confirmation"
after cancel $::OrCADWheel::Timer
::OrCADWheel::Heartbeat
assert {$::OrCADWheel::Enabled && !$::OrCADWheel::Running && $::OrCADWheel::Recovering} "Dead helper not supervised"
assert {[llength $::launches] == $before + 2} "Recovery must stop then launch exactly once"
assert {[lindex [lindex $::launches end-1] 1] == "--stop"} "Recovery did not stop old helper first"
after cancel $::OrCADWheel::Timer
::OrCADWheel::Heartbeat
assert {[llength $::launches] == $before + 2} "Recovery launched twice before acknowledgment"
after cancel $::OrCADWheel::CheckTimer
set ::files(mock-state.status) running
::OrCADWheel::CheckStarted 0 0
assert {$::OrCADWheel::Running && !$::OrCADWheel::Recovering} "Recovery did not acknowledge"
assert {[string match {*Recovery acknowledged*} [join $::controllerLogs]]} "Missing recovery diagnostic"
set ::statusAge 0

# File sharing races pause/retry; they never clear user intent or stop the helper.
set ::failWrite 1
set before [llength $::launches]
after cancel $::OrCADWheel::Timer
::OrCADWheel::Heartbeat
assert {$::OrCADWheel::Enabled && $::OrCADWheel::Running && $::OrCADWheel::WriteFailures == 1} "Transient write turned tool off"
assert {$::OrCADWheel::Timer ne "" && [llength $::launches] == $before} "Write failure stopped helper or lost timer"
set ::failWrite 0
after cancel $::OrCADWheel::Timer
::OrCADWheel::Heartbeat
assert {$::OrCADWheel::WriteFailures == 0} "Successful write did not reset failures"
assert {[string match {*writes resumed*} [join $::controllerLogs]]} "Missing write recovery diagnostic"

# Failed automatic recovery keeps preference and retries with bounded backoff.
set ::failLaunch 1; set ::OrCADWheel::NextRecovery 0
::OrCADWheel::Recover "test native failure"
assert {$::OrCADWheel::Enabled && !$::OrCADWheel::Running && !$::OrCADWheel::Recovering} "Failed recovery disabled user intent"
set before [llength $::launches]
::OrCADWheel::Recover "test repeated failure"
assert {[llength $::launches] == $before} "Backoff did not prevent restart storm"
set ::failLaunch 0; set ::OrCADWheel::NextRecovery 0
::OrCADWheel::Recover "test retry"
assert {$::OrCADWheel::Recovering} "Recovery retry not started"
after cancel $::OrCADWheel::CheckTimer
::OrCADWheel::CheckStarted 25 0
assert {$::OrCADWheel::Enabled && !$::OrCADWheel::Running && !$::OrCADWheel::Recovering} "Recovery timeout disabled preference"
set ::OrCADWheel::NextRecovery 0
set before [llength $::launches]
::OrCADWheel::Recover "fourth attempt in minute"
assert {[llength $::launches] == $before && $::OrCADWheel::NextRecovery > [clock seconds]} "Per-minute recovery cap missing"
set ::OrCADWheel::RecoveryWindow [expr {[clock seconds] - 61}]
set ::OrCADWheel::NextRecovery 0
::OrCADWheel::Recover "new recovery window"
assert {$::OrCADWheel::Recoveries == 1 && $::OrCADWheel::Recovering} "Recovery window did not reset"
after cancel $::OrCADWheel::CheckTimer
set ::files(mock-state.status) running
::OrCADWheel::CheckStarted 0 0
::OrCADWheel::Disable
set before [llength $::launches]
::OrCADWheel::Heartbeat
::OrCADWheel::Recover "user switched off"
assert {[llength $::launches] == $before && $::OrCADWheel::Timer eq ""} "Explicit off was automatically re-enabled"

set ::helperExists 0
assert {[catch {::OrCADWheel::Enable}]} "Missing executable not rejected"
set ::helperExists 1; set ::failLaunch 1
assert {[catch {::OrCADWheel::Enable}]} "Launch error not propagated"
assert {!$::OrCADWheel::Enabled} "Launch error left controller enabled"
puts "PASS: wheel startup, runtime fault retry, supervised recovery/backoff, diagnostics, view gate, persistence and shutdown"
