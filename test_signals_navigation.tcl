# Deterministic Signals controller tests. Never run mocks inside Capture.
source [file join [file dirname [info script]] src OrCADQuickTools.core.tcl]
proc assert {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message}}
set ::selection wireA; set ::active 1; set ::page pageA
set ::calls {}; set ::logs {}; set ::notices {}; set ::statuses 0; set ::deleted 0
set ::refreshFailure 0; set ::refreshChanges 0; set ::menuFailure 0
set ::contextResult signals-invoked
set ::statusReadable 1
array set ::types {wireA 20 wireB 20 part 13 alias 23}
array set ::ids {wireA 101 wireB 202}
array set ::names {wireA NET_A wireB NET_B}
proc IsSchematicViewActive {} {return $::active}
proc GetActivePage {} {return $::page}
proc GetSelectedObjects {} {return $::selection}
proc DboBaseObject_GetObjectType {object} {return $::types($object)}
proc DboState {} {incr ::statuses; return mockStatus}
proc mockStatus {method args} {
    if {$method eq "-delete"} {incr ::deleted; return}
    if {$method eq "OK"} {return $::statusReadable}
    error $method
}
proc DboTclHelper_sMakeCString {} {return mockCString}
proc DboTclHelper_sGetConstCharPtr {text} {return $::text}
proc wireA {method args} {return [wireMethod wireA $method $args]}
proc wireB {method args} {return [wireMethod wireB $method $args]}
proc wireMethod {object method args} {
    switch -- $method {
        GetId {return $::ids($object)}
        GetNetName {set ::text $::names($object); return}
        default {error "Unexpected DB call (must not edit design): $method"}
    }
}
rename ::SignalsNavigation::StartContext ::SignalsNavigation::OriginalStartContext
proc ::SignalsNavigation::StartContext {resultFile} {
    lappend ::calls [list context [lindex $::selection 0]]
    if {$::refreshFailure} {error "native context helper unavailable"}
    if {$::refreshChanges} {set ::selection wireB}
    set f [open $resultFile w]; puts -nonewline $f $::contextResult; close $f
}
proc settle {} {after 90 {set ::settled 1}; vwait ::settled}
proc MenuCommand {id} {
    lappend ::calls [list menu $id [lindex $::selection 0]]
    if {$::menuFailure} {error "native Signals error"}
}
rename ::SignalsNavigation::Log ::SignalsNavigation::OriginalLog
proc ::SignalsNavigation::Log {message} {lappend ::logs $message}
rename ::SignalsNavigation::Notice ::SignalsNavigation::OriginalNotice
proc ::SignalsNavigation::Notice {message} {lappend ::notices $message}

assert {[::SignalsNavigation::Enabler]} "Single wire not enabled"
set ::selection part
assert {![::SignalsNavigation::Enabler]} "Part must not dispatch Signals"
set ::selection alias
assert {![::SignalsNavigation::Enabler]} "Alias text must not be mistaken for a wire"
set ::selection {}
assert {![::SignalsNavigation::Enabler]} "Empty selection enabled"
set ::selection {wireA wireB}
assert {![::SignalsNavigation::Enabler]} "Ambiguous multi-selection enabled"
::SignalsNavigation::Run
assert {$::SignalsNavigation::Pending eq "" && [llength $::calls]==0 && [llength $::notices]==0} "Invalid selection dispatched or opened a usage popup"
assert {[string first {see Alt+F1} [join $::logs]] >= 0} "Invalid selection usage log missing"
set ::selection wireA; set ::active 0
assert {![::SignalsNavigation::Enabler]} "Non-schematic view enabled"
set ::active 1

set ::statusReadable 0
::SignalsNavigation::Run
assert {$::SignalsNavigation::Pending eq "" && [llength $::calls]==0 && [llength $::notices]==1} "Network read error was hidden"
set ::statusReadable 1; set ::notices {}

::SignalsNavigation::Run
assert {[llength $::calls]==0 && $::SignalsNavigation::Pending ne ""} "Native command ran inside shortcut callback"
update idletasks
assert {$::calls eq {{context wireA}} && $::SignalsNavigation::Busy} "Context launch did not defer native dispatch"
::SignalsNavigation::Run
assert {$::calls eq {{context wireA}}} "Duplicate opened another popup"
settle
assert {$::calls eq {{context wireA}} && !$::SignalsNavigation::Busy} "Signals acknowledgement dispatched a duplicate native command"
assert {$::SignalsNavigation::Pending eq ""} "Timer leaked"
assert {[llength $::notices]==0} "First successful Signals request opened a usage popup"
assert {[string first {pane result not verified} [join $::logs]] >= 0} "Dispatch misrepresented as pane readback"

set ::selection wireB; set ::calls {}
::SignalsNavigation::Run
update idletasks
settle
assert {$::calls eq {{context wireB}}} "Subsequent network reused old wire ID or dispatched twice"
assert {[llength $::notices]==0} "Subsequent Signals request opened a usage popup"
assert {[string first {requested net=NET_B} [join $::logs]] >= 0} "Requested network diagnostic missing"
puts "PASS: Signals strict selection, deferred helper, A/B requests, menu action acknowledged without duplicate 14844 (pane not simulated)"

set ::selection wireA; set ::calls {}
::SignalsNavigation::Run
set ::selection wireB
update idletasks
assert {[llength $::calls]==0} "Changed selection dispatched stale request"
set ::selection wireA
::SignalsNavigation::Run
set ::page pageB
update idletasks
assert {[llength $::calls]==0} "Changed page dispatched stale request"
set ::page pageA
set snapshot [::SignalsNavigation::Snapshot]
set ::refreshChanges 1
::SignalsNavigation::Refresh $snapshot
settle
assert {$::calls eq {{context wireA}} && $::SignalsNavigation::Pending eq ""} "Refresh changing selection still dispatched"
set ::refreshChanges 0; set ::selection wireA; set ::calls {}
::SignalsNavigation::Refresh $snapshot
set ::selection wireB
settle
assert {$::calls eq {{context wireA}}} "Selection changed after refresh still dispatched"

set ::selection wireA; set ::calls {}
::SignalsNavigation::Run
set ::selection wireB
::SignalsNavigation::Run
update idletasks
settle
assert {$::calls eq {{context wireB}}} "Repeated keypress did not replace pending request"
puts "PASS: changed selection/page, post-refresh change, and superseded requests cancel safely"

set ::selection wireA; set ::calls {}; set ::notices {}; set ::refreshFailure 1
::SignalsNavigation::Run
update idletasks
assert {$::calls eq {{context wireA}} && [llength $::notices]==1 && !$::SignalsNavigation::Busy} "Context launch failure dispatched Signals"
set ::refreshFailure 0; set ::contextResult {error: native popup missing}; set ::calls {}; set ::notices {}
::SignalsNavigation::Run
update idletasks
settle
assert {$::calls eq {{context wireA}} && [llength $::notices]==1 && !$::SignalsNavigation::Busy} "Failed context acknowledgement dispatched Signals"
set ::contextResult {}; set ::calls {}; set ::notices {}
::SignalsNavigation::Run
update idletasks
set callback [lindex [after info $::SignalsNavigation::Pending] 0]
after cancel $::SignalsNavigation::Pending
::SignalsNavigation::PollContext [lindex $callback 1] [lindex $callback 2] 110
assert {$::calls eq {{context wireA}} && [llength $::notices]==1 && !$::SignalsNavigation::Busy && $::SignalsNavigation::Pending eq ""} "Timed out helper dispatched Signals or leaked busy state"
set ::contextResult context-ready; set ::calls {}; set ::notices {}
::SignalsNavigation::Run
update idletasks
settle
assert {$::calls eq {{context wireA}} && [llength $::notices]==1 && $::SignalsNavigation::Pending eq ""} "Old helper context-ready was accepted or dispatched"
set ::contextResult {error: menu action uncertain}; set ::calls {}; set ::notices {}
::SignalsNavigation::Run
update idletasks
settle
assert {$::calls eq {{context wireA}} && [llength $::notices]==1} "Uncertain native menu action retried with 14844"
assert {$::statuses==$::deleted} "DboState leaked"
set items [::QuickToolsHelp::ShortcutItems]
assert {[lindex [lindex $items end] 0] eq "Alt+S" && [lindex [lindex $items end] 2] eq "::SignalsNavigation::Run"} "Registry/menu/help action missing"
puts "PASS: helper errors/timeouts and old acknowledgement rejected; no fallback 14844; DB statuses released; no design writes"

set ::contextResult signals-invoked-menu-open; set ::calls {}; set ::notices {}; set ::selection wireA
::SignalsNavigation::Run
update idletasks
settle
assert {$::calls eq {{context wireA}} && [llength $::notices]==1 && !$::SignalsNavigation::Busy && $::SignalsNavigation::Pending eq ""} "Residual menu acknowledgement retried Signals or leaked state"
assert {[string first "Signals \u5DF2\u8C03\u7528" [lindex $::notices 0]] >= 0} "Residual menu falsely reported failed action"
assert {[string first {no action retry} [join $::logs]] >= 0} "Residual menu cleanup diagnostic missing"
set ::contextResult signals-invoked
puts "PASS: Signals invoked with residual menu is acknowledged once; cleanup warning distinct from action failure"

# Inspect the real launcher with a mocked exec: no child/UI actions. The ready
# marker MUST be absent while exec runs and published only after its return.
set ::OrCADQuickTools::ScriptDirectory [pwd]
set launchResult [file join [pwd] signals-launch-[pid]-[clock clicks].result]
rename exec ::savedExec
proc exec {args} {
    set ::launchArguments $args
    assert {![file exists "$::launchResult.ready"]} "Ready marker published before exec returned"
    return 12345
}
::SignalsNavigation::OriginalStartContext $launchResult
rename exec {}
rename ::savedExec exec
set f [open "$launchResult.ready" r]; set marker [read $f]; close $f
assert {$marker eq "capture-ready-v17"} "Wrong launch protocol"
assert {[lrange $::launchArguments end-4 end] eq {< NUL >& NUL &}} "Helper did not detach standard handles"
file delete "$launchResult.ready"
puts "PASS: GUI launch readiness published only after background exec returns; standard handles detached"
