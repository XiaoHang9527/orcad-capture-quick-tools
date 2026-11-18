# Standalone Tcl 8.4 mocks. Never load this file into Capture.
source [file join [file dirname [info script]] src OrCADQuickTools.core.tcl]
source [file join [file dirname [info script]] src OrCADPartPreview.tcl]
# A generic test-only field exercises literal slashes and user customization.
rename ::PartPreview::Fields ::PartPreview::PublicDefaultFields
proc ::PartPreview::Fields {} {
    return [linsert [::PartPreview::PublicDefaultFields] 2 [list "\u81EA\u5B9A\u4E49\u5C5E\u6027" {User_P/N} {}]]
}
proc assert {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message}}
set ::strings 0; set ::states 0; set ::stringDeletes 0; set ::stateDeletes 0
set ::selection partA; set ::active 1; set ::page pageA
set ::events {}; set ::output {}; set ::session {}; set ::reads {}; set ::fault 0
array set ::type {partA 13 partB 13 wire 20 label 23}
array set ::ids {partA 101 partB 202}
array set ::properties {
    partA,Reference R301
    partA,Value 10K
    partA,User_P/N {EXAMPLE-001;$test[3]}
    {partA,PCB Footprint} 0402
    partA,Description {1%, 1/16W}
    partA,Manufacturer Example
    partB,Reference C302
    partB,Value 100nF
}
proc IsSchematicViewActive {} {return $::active}
proc GetSelectedObjects {} {if {$::fault} {error "Test selection unavailable"}; return $::selection}
proc GetActivePage {} {return $::page}
proc DboBaseObject_GetObjectType {object} {return $::type($object)}
proc RegisterAction args {lappend ::events $args}
proc DboTclHelper_sMakeCString {{value {}}} {
    set pointer cs[incr ::strings]; set ::buffer($pointer) $value; return $pointer
}
proc DboTclHelper_sGetConstCharPtr {pointer} {return $::buffer($pointer)}
proc DboTclHelper_sDeleteCString {pointer} {
    assert {[info exists ::buffer($pointer)]} "Double-freed string"
    unset ::buffer($pointer); incr ::stringDeletes
}
proc DboState {} {
    set id st[incr ::states]; set ::okay($id) 1
    interp alias {} $id {} stateCommand $id
    return $id
}
proc stateCommand {id method args} {
    switch -- $method {
        OK {return $::okay($id)}
        -delete {unset ::okay($id); rename $id {}; incr ::stateDeletes}
        default {error "Unexpected state method: $method"}
    }
}
proc partA {method args} {return [partCommand partA $method $args]}
proc partB {method args} {return [partCommand partB $method $args]}
proc partCommand {object method arguments} {
    switch -- $method {
        GetId {return $::ids($object)}
        GetEffectivePropStringValue {
            set name $::buffer([lindex $arguments 0]); set value [lindex $arguments 1]
            lappend ::reads $name
            set status [DboState]
            if {[info exists ::properties($object,$name)]} {set ::buffer($value) $::properties($object,$name)} \
            else {set ::okay($status) 0}
            return $status
        }
        GetReference {set ::buffer([lindex $arguments 0]) $::fallbackReference; return}
        GetPartValue {set ::buffer([lindex $arguments 0]) fallbackValue; return}
        default {error "Unexpected database method, must never write: $method"}
    }
}
proc DboState_WriteToSessionLog {pointer} {lappend ::session $::buffer($pointer)}
rename ::PartPreview::Emit ::PartPreview::RealEmit
proc ::PartPreview::Emit {message} {lappend ::output $message}
set ::fallbackReference R999
set ::PartPreview::Preference [file join $::env(TEMP) OrCADPreviewTest-[pid]-[clock clicks] enabled]

::PartPreview::Initialize
::PartPreview::Initialize
assert {[llength $::events]==1 && [lindex [lindex $::events 0] 0] eq "_cdnOrSchViewCmdComplete"} "Click event not registered once"
assert {[::PartPreview::NeedsCallback OnLButtonUp] && ![::PartPreview::NeedsCallback ZoomIn]} "Wrong trigger"
::PartPreview::OnCommand OnLButtonUp
assert {[llength $::output]==0 && $::PartPreview::Pending ne ""} "Preview read database in mouse callback"
::PartPreview::OnCommand OnLButtonUp
update idletasks
assert {[llength $::output]==1} "Burst click callbacks did not coalesce"
set first [lindex $::output 0]
assert {[string first {EXAMPLE-001;$test[3]} $first] >= 0} "Custom value damaged or evaluated as Tcl"
assert {[string first "\u81EA\u5B9A\u4E49\u5C5E\u6027\uFF1A" $first] >= 0 && [lsearch -exact $::reads User_P/N] >= 0} "Literal custom property key missing"
assert {[string first {0402} $first] >= 0 && [string first {1%, 1/16W} $first] >= 0} "Other fields missing"
::PartPreview::OnCommand OnLButtonUp; update idletasks
assert {[llength $::output]==1} "Same part spammed the log"
set ::properties(partA,User_P/N) NEW-PN
::PartPreview::OnCommand OnLButtonUp; update idletasks
assert {[llength $::output]==2 && [string first NEW-PN [lindex $::output end]] >= 0} "Same-part property edit not reflected"
set ::selection partB
::PartPreview::OnCommand OnLButtonUp; update idletasks
assert {[llength $::output]==3 && [string first C302 [lindex $::output end]] >= 0} "Second component not displayed"
assert {[string first "\u81EA\u5B9A\u4E49\u5C5E\u6027" [lindex $::output end]] < 0} "Absent custom property not skipped"
set count [llength $::output]
foreach selected [list {} wire label {partA partB}] {
    set ::selection $selected; ::PartPreview::OnCommand OnLButtonUp; update idletasks
    assert {[llength $::output]==$count} "Invalid selection printed properties"
}
set ::selection partB
::PartPreview::OnCommand OnLButtonUp; update idletasks
assert {[llength $::output]==$count+1} "Reselect after blank click not displayed"
set count [llength $::output]
set ::active 0; ::PartPreview::OnCommand OnLButtonUp; update idletasks
assert {[llength $::output]==$count} "Non-schematic preview ran"
set ::active 1; set ::page pageB
::PartPreview::OnCommand OnLButtonUp; update idletasks
assert {[llength $::output]==$count+1} "Same ID on different page suppressed"
set ::selection partA
::PartPreview::OnCommand OnLButtonUp
set ::selection partB
update idletasks
assert {[string first R301 [lindex $::output end]] < 0} "Deferred callback retained stale part pointer"
set ::DboBaseObject_PLACED_INSTANCE 99; set ::type(partB) 99
::PartPreview::OnCommand OnLButtonUp; update idletasks
assert {[llength [::PartPreview::Identity]]==3} "Native placed-instance enum ignored"
unset ::DboBaseObject_PLACED_INSTANCE; set ::type(partB) 13

set ::selection partA
set ::properties(partA,Description) "Line1\nLine2\t[binary format c 0]Text"
::PartPreview::OnCommand OnLButtonUp; update idletasks
assert {[string first {Line1 Line2 Text} [lindex $::output end]] >= 0} "Multiline/control chars not sanitized"
assert {[string length [::PartPreview::Clean [string repeat A 2000]]]==1003} "Unbounded field output"
unset ::properties(partA,Reference)
::PartPreview::OnCommand OnLButtonUp; update idletasks
assert {[string first R999 [lindex $::output end]] >= 0} "Native getter fallback failed"
set temporary [DboTclHelper_sMakeCString BAD]
::PartPreview::FreeString $temporary
assert {$::strings==$::stringDeletes && $::states==$::stateDeletes} "Temporary pointers leaked"

set ::fault 1
::PartPreview::OnCommand OnLButtonUp; update idletasks
assert {!$::PartPreview::Busy && $::PartPreview::Pending eq ""} "Read failure leaked busy/timer"
set ::fault 0
::PartPreview::OnCommand OnLButtonUp
::PartPreview::Toggle
assert {!$::PartPreview::Enabled && $::PartPreview::Pending eq "" && ![::PartPreview::NeedsCallback OnLButtonUp]} "Disable did not cancel preview"
set count [llength $::output]
::PartPreview::OnCommand OnLButtonUp; update idletasks
assert {[llength $::output]==$count} "Disabled feature still printed"
set f [open $::PartPreview::Preference r]; set saved [read $f]; close $f
assert {$saved eq "0"} "Preference not persisted"
set testPreference $::PartPreview::Preference
source [file join [file dirname [info script]] src OrCADPartPreview.tcl]
set ::PartPreview::Preference $testPreference
# Re-source reloads only procedure bodies, never re-registers or resets enabled.
::PartPreview::Initialize
assert {!$::PartPreview::Enabled && [llength $::events]==1} "Reload duplicated event or reset preference"
rename ::PartPreview::Emit {}
rename ::PartPreview::RealEmit ::PartPreview::Emit
::PartPreview::Emit "\u81EA\u5B9A\u4E49\u5C5E\u6027\uFF1AEXAMPLE-TEST"
assert {[llength $::session]==1 && [string first EXAMPLE-TEST [lindex $::session 0]] >= 0} "Session log output missing"
assert {$::strings==$::stringDeletes && $::states==$::stateDeletes} "Log output leaked pointers"
set ::PartPreview::Initialized 0; set ::PartPreview::Enabled 1
::PartPreview::Initialize
assert {!$::PartPreview::Enabled} "Startup ignored saved disabled preference"
::PartPreview::Toggle
set f [open $::PartPreview::Preference r]; set saved [read $f]; close $f
assert {$saved eq "1" && $::PartPreview::Enabled} "Enable preference not saved"
file delete $::PartPreview::Preference
file delete [file dirname $::PartPreview::Preference]
assert {$::PartPreview::Pending eq "" && !$::PartPreview::Busy} "Preview leaked idle callbacks"
puts "PASS: native click/deferred reads, generic custom fields, aliases/fallback, dedup/changed properties, invalid selections, enum, errors, reload/preference, log and pointer cleanup; no database writes"
