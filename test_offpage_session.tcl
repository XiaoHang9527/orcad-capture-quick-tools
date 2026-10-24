# Isolated Tcl 8.4 test, never load into Capture. No native design operations.
source [file join [file dirname [info script]] src OrCADOffPageToggle.tcl]
proc assert {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message}}
set ::OffPageDirection::LogFile ""
set ::binds {}; set ::gets {}; set ::mode normal; set ::cached 0; set ::cachedSource OFFPAGELEFT-R
set ::sequence 0
proc DboState {} {return testState}
proc testState {method args} {if {$method eq "Succeeded"} {return 1}; error $method}
proc DboTclHelper_sMakeCString {args} {return [lindex $args 0]}
proc DboSession {option pointer} {
    assert {$option eq "-this"} "Must wrap borrowed session, never create a session"
    lappend ::binds $pointer
    if {$::mode eq "fail"} {error "Mock wrapper registration failed"}
    if {$::mode eq "noop"} {return $pointer}
    interp alias {} $pointer {} testSession $pointer
    return $pointer
}
proc testSession {pointer method path state} {
    assert {$method eq "GetLib"} "Borrowed session must not be deleted or mutated"
    lappend ::gets [list $pointer $path]
    if {$::mode eq "getfail"} {error "Mock library read error"}
    return library
}
proc library {method symbol state} {
    assert {$method eq "GetSymbol"} "Unexpected library operation"
    return $symbol
}
rename ::OffPageDirection::Connectors ::OffPageDirection::SavedConnectors
proc ::OffPageDirection::Connectors {page} {if {$::cached} {return connector}; return {}}
rename ::OffPageDirection::Text ::OffPageDirection::SavedText
proc ::OffPageDirection::Text {object method} {
    if {$method eq "GetSourceSymbolName"} {return $::cachedSource}
    if {$method eq "GetSourceLibName"} {return $::sourcePath}
    error $method
}
proc connector {method args} {
    switch $method {
        GetSymbol {return cachedSymbol}
        GetId {return 1}
        IsObjLocked {return 0}
        default {error "Unexpected connector operation: $method"}
    }
}
set root [file join $::env(TEMP) OrCADSessionTest-[pid]-[clock clicks]]
file mkdir $root
set ::sourcePath [file join $root capsym.olb]
set f [open $::sourcePath {WRONLY CREAT EXCL}]; puts $f MOCK; close $f

# Reproduce the reported error: global pointer exists but has no Tcl command.
set ::DboSession_s_pDboSession _sessionA_p_DboSession
set result [::OffPageDirection::Resolve design {page} $::sourcePath OFFPAGELEFT-R]
assert {$result eq "OFFPAGELEFT-R" && $::binds eq {_sessionA_p_DboSession}} "Unwrapped session was not initialized"
assert {[llength $::gets]==1} "Lookup should run exactly once"
::OffPageDirection::Resolve design {page} $::sourcePath OFFPAGELEFT-R
assert {[llength $::binds]==1 && [llength $::gets]==2} "Callable session needlessly rewrapped or lookup retried"

# A changed native session must be read fresh, not cached between operations.
set ::DboSession_s_pDboSession _sessionB_p_DboSession
::OffPageDirection::Resolve design {page} $::sourcePath OFFPAGELEFT-R
assert {[lindex $::binds end] eq "_sessionB_p_DboSession" && [lindex [lindex $::gets end] 0] eq "_sessionB_p_DboSession"} "Old session retained"
rename _sessionB_p_DboSession {}
::OffPageDirection::Resolve design {page} $::sourcePath OFFPAGELEFT-R
assert {[llength $::binds]==3} "Removed Tcl wrapper not recreated"
rename DboSession savedSessionConstructor
::OffPageDirection::Resolve design {page} $::sourcePath OFFPAGELEFT-R
assert {[llength $::gets]==5} "Existing callable session should not require constructor"
rename savedSessionConstructor DboSession

foreach bad {missing NULL {}} {
    catch {unset ::DboSession_s_pDboSession}
    if {$bad ne "missing"} {set ::DboSession_s_pDboSession $bad}
    set count [llength $::gets]
    assert {[catch {::OffPageDirection::Resolve design {page} $::sourcePath OFFPAGELEFT-R} why]} "Absent session was accepted"
    assert {[string first {Capture session} $why]>=0 && [llength $::gets]==$count} "Absent session was used or unclear error returned"
}
set ::DboSession_s_pDboSession _unbound_p_DboSession
foreach mode {fail noop} {
    set ::mode $mode; set count [llength $::gets]
    assert {[catch {::OffPageDirection::Resolve design {page} $::sourcePath OFFPAGELEFT-R} why]} "Wrapper failure was ignored"
    assert {[string first {Capture session} $why]>=0 && [llength $::gets]==$count} "Failed wrapper reached GetLib"
}
set ::mode normal
rename DboSession savedSessionConstructor
assert {[catch {::OffPageDirection::Resolve design {page} $::sourcePath OFFPAGELEFT-R} why]} "Missing wrapper API was accepted"
assert {[string first {Capture session} $why]>=0} "Missing API error is unclear"
rename savedSessionConstructor DboSession
set ::mode getfail
set ::DboSession_s_pDboSession _sessionA_p_DboSession
set count [llength $::gets]
assert {[catch {::OffPageDirection::Resolve design {page} $::sourcePath OFFPAGELEFT-R} why]} "Native GetLib exception hidden"
assert {[llength $::gets]==$count+1 && [string first {Mock library read error} $why]>=0} "GetLib retried or cause lost"

# Cache-first resolution stays independent of any global session API.
set ::mode normal; set ::cached 1
unset ::DboSession_s_pDboSession
set count [llength $::gets]
assert {[::OffPageDirection::Resolve design {page} $::sourcePath OFFPAGELEFT-R] eq "cachedSymbol"} "Cached counterpart no longer works"
assert {[llength $::gets]==$count} "Cache fast path accessed session"
assert {[catch {::OffPageDirection::Target O-L-I}]} "O-L-I support must not be added"
assert {[::OffPageDirection::Target OFFPAGELEFT-R] eq "OFFPAGELEFT-L"} "Existing pair changed"

# Exercise the actual Execute preflight: no unselection/replacement/DB writes
# may occur when session initialization fails during counterpart resolution.
proc GetActivePage {} {return page}
proc GetSelectedObjects {} {return connector}
proc DboBaseObject_GetObjectType {object} {return 38}
proc page {method args} {
    if {$method eq "GetContainingLib"} {return design}
    incr ::writes; error "Unexpected native page write: $method"
}
proc UnSelectAll {} {incr ::unselects}
rename ::OffPageDirection::Pages ::OffPageDirection::SavedPages
proc ::OffPageDirection::Pages {design} {return page}
rename ::OffPageDirection::Snapshot ::OffPageDirection::SavedSnapshot
proc ::OffPageDirection::Snapshot {object} {
    return [list source OFFPAGELEFT-L name TEST_NET library $::sourcePath rotation 0 mirror 0 location {0 0} hotspot {0 10}]
}
set ::cachedSource OFFPAGELEFT-L; set ::cached 1
set ::DboSession_s_pDboSession _still_unbound_p_DboSession
set ::mode fail; set ::writes 0; set ::unselects 0
set count [llength $::gets]
assert {[catch {::OffPageDirection::Execute} why] && [string first {Capture session} $why]>=0} "Execute did not reject broken session"
assert {$::writes==0 && $::unselects==0 && [llength $::gets]==$count} "Session failure mutated design or selection"
file delete $::sourcePath
file delete $root
puts "PASS: unwrapped/removed/replaced sessions, absent/broken wrapper, GetLib no retry, cache fast path, Execute failure before writes; borrowed session never deleted; O-L-I unchanged"
