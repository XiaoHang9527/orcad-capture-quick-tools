# Pure Tcl 8.4 API mock. This does NOT validate Capture's native C++ behavior.
source [file join [file dirname [info script]] src OrCADOffPageToggle.tcl]
proc assert {value message} {if {!$value} {error $message}}
set ::statusSerial 0
proc DboState {} {
    set s mockStatus[incr ::statusSerial]
    set ::statusCode($s) 0
    interp alias {} $s {} mockStatus $s
    return $s
}
proc mockStatus {s method args} {
    switch $method {
        Succeeded {return [expr {$::statusCode($s)==0}]}
        Code {return $::statusCode($s)}
        Message {return ""}
        default {error "Unexpected status method $method"}
    }
}
proc good {method args} {switch $method {Succeeded {return 1} Code {return 0} default {return ""}}}
proc bad {method args} {switch $method {Succeeded {return 0} Code {return 99} default {return ""}}}
proc codeOne {method args} {switch $method {Succeeded {return 0} Code {return 1} default {return ""}}}
set ::cstringSerial 0
proc DboTclHelper_sMakeCString {args} {
    if {[llength $args]} {return [lindex $args 0]}
    set ref cs[incr ::cstringSerial]
    set ::cstring($ref) ""
    return $ref
}
proc DboTclHelper_sGetConstCharPtr {value} {
    if {[info exists ::cstring($value)]} {return $::cstring($value)}
    return $value
}
proc DboTclHelper_sMakeCPoint {x y} {list $x $y}
proc DboTclHelper_sGetCPointX {xy} {lindex $xy 0}
proc DboTclHelper_sGetCPointY {xy} {lindex $xy 1}
proc DboTclHelper_sMakeLOGFONT {} {return font}
proc DboTclHelper_sEvalPage {page} {}
proc DboGraphicInstanceToDboNetSymbolInstance {o} {return $o}
proc DboNetSymbolInstanceToDboOffPageConnector {o} {return $o}
proc DboBaseObject_GetObjectType {o} {$o GetObjectType}
proc GetActivePage {} {return page}
proc GetSelectedObjects {} {return $::selection}
proc UnSelectAll {} {set ::selection {}}
proc Menu args {}
set ::messages {}
proc tk_messageBox args {lappend ::messages $args; return cancel}
proc delete_DboPageOffPageConnectorsIter args {}
proc delete_DboUserPropsIter args {}
proc delete_DboDisplayPropsIter args {}
set ::DboValue_NOROTATION 0
set ::DboValue_NINETY 1
set ::DboValue_ONEEIGHTY 2
set ::DboValue_TWOSEVENTY 3
set ::DboLib_DEFAULT_FONT_PROPERTY 0
set ::OffPageDirection::LogFile ""

# CString references require an adapter, kept separate from the code under test.
rename ::OffPageDirection::Text ::OffPageDirection::NativeText
proc ::OffPageDirection::Text {o method} {$o $method}
rename ::OffPageDirection::Pages ::OffPageDirection::NativePages
proc ::OffPageDirection::Pages {d} {return page}

proc reset {} {
    array unset ::data
    array unset ::dead
    set ::serial 0
    set ::writes 0
    set ::badTarget 0
    set ::failOnce 0
    set ::propertyIterError 0
    set ::readError 0
    set ::propertyCount 0
    set ::setterCodeOne 0
    set ::ignoreRotationOnce 0
    set ::setterCalls 0
    set ::displayCreates 0
    set ::createFails 0
    set ::irefReadFails 0
    set ::ignoreIrefWrite 0
    set ::selection {o1}
    foreach id {1 2} source {OFFPAGELEFT-L OFFPAGELEFT-R} {
        set ::data(o$id,id) $id
        set ::data(o$id,source) $source
        set ::data(o$id,name) {A[3];$net}
        set ::data(o$id,location) {100 200}
        set ::data(o$id,rotation) 0
        set ::data(o$id,mirror) 0
        set ::data(o$id,color) 2
        set ::data(o$id,irefDisplay) 0
        interp alias {} o$id {} object o$id
    }
    set ::data(o2,name) TARGET
}
proc transform {o xy} {
    set x [lindex $xy 0]; set y [lindex $xy 1]
    # Simulate a mirror on local Y, forcing Orient to combine it with rotation.
    if {$::data($o,mirror)} {set y [expr {-$y}]}
    switch $::data($o,rotation) {
        1 {set t $x; set x [expr {-$y}]; set y $t}
        2 {set x [expr {-$x}]; set y [expr {-$y}]}
        3 {set t $x; set x $y; set y [expr {-$t}]}
    }
    list [expr {$x+[lindex $::data($o,location) 0]}] [expr {$y+[lindex $::data($o,location) 1]}]
}
proc object {o method args} {
    if {[info exists ::dead($o)]} {error "DEREFERENCED DELETED OBJECT: $o"}
    if {[string match Set* $method]} {incr ::setterCalls}
    if {$method eq "SetRotation" && $::ignoreRotationOnce} {
        set ::ignoreRotationOnce 0
        return codeOne
    }
    if {$method eq "GetColor" && $::readError} {set ::statusCode([lindex $args 0]) $::readError}
    switch $method {
        GetObjectType {return 38}
        GetId {return $::data($o,id)}
        GetName {return $::data($o,name)}
        GetSourceSymbolName {return $::data($o,source)}
        GetSourceLibName {return /old/library/capsym.olb}
        GetSymbol {return $::data($o,source)}
        GetLocation {return $::data($o,location)}
        GetRotation {return $::data($o,rotation)}
        GetMirror {return $::data($o,mirror)}
        GetColor {return $::data($o,color)}
        GetOffsetGraphicPoint {return [transform $o [lindex $args 0]]}
        GetOffsetHotSpot {
            if {[string match *-L $::data($o,source)]} {return [transform $o {0 10}]}
            return [transform $o {10 10}]
        }
        GetWire {return wire}
        NewUserPropsIter {set ::propertyRemaining $::propertyCount; return userIterator}
        NewDisplayPropsIter {
            if {$::data($o,irefDisplay)} {
                set ::irefRemaining($o) 1
                interp alias {} irefIterator_$o {} irefNext $o
                return irefIterator_$o
            }
            set ::propertyRemaining $::propertyCount; return displayIterator
        }
        GetDisplayProp {
            if {$::data($o,irefDisplay) && [lindex $args 0] eq "IREF"} {
                interp alias {} iref_$o {} irefProperty $o
                return iref_$o
            }
            set ::statusCode([lindex $args 1]) 404
            return NULL
        }
        NewDisplayProp {
            set state [lindex $args 0]
            assert [expr {$::statusCode($state)==0}] "Creation reused lookup error status"
            incr ::displayCreates
            if {$::createFails > 0} {incr ::createFails -1; set ::statusCode($state) 99; return NULL}
            assert [expr {[lindex $args 1] eq "IREF"}] "Wrong recreated property"
            set ::data($o,irefDisplay) 1
            set ::data($o,dispLocation) [lindex $args 2]
            set ::data($o,dispRotation) [lindex $args 3]
            set ::data($o,dispFont) [lindex $args 4]
            set ::data($o,dispColor) [lindex $args 5]
            set ::data($o,dispType) 0
            interp alias {} iref_$o {} irefProperty $o
            return iref_$o
        }
        GetEffectivePropStringValue {
            if {[lindex $args 0] ne "IREF" || $::irefReadFails || ![info exists ::data($o,irefValue)]} {return bad}
            set ::cstring([lindex $args 1]) $::data($o,irefValue)
            return good
        }
        SetEffectivePropStringValue {
            if {!$::ignoreIrefWrite} {set ::data($o,irefValue) [lindex $args 1]}
            return good
        }
        IsObjLocked {return 0}
        SetName {set ::data($o,name) [lindex $args 0]}
        SetLocation {set ::data($o,location) [lindex $args 0]}
        SetRotation {set ::data($o,rotation) [lindex $args 0]}
        SetMirror {set ::data($o,mirror) [lindex $args 0]}
        SetColor {set ::data($o,color) [lindex $args 0]}
        default {error "Unexpected object method $method"}
    }
    if {$::setterCodeOne} {return codeOne}
    return good
}
proc wire {method args} {return 7}
proc page {method args} {
    switch $method {
        GetContainingLib {return design}
        MarkModified {return good}
        NewOffPageConnectorsIter {
            set ::iter {}
            foreach key [lsort [array names ::data *,id]] {
                set o [lindex [split $key ,] 0]
                if {![info exists ::dead($o)]} {lappend ::iter $o}
            }
            return iterator
        }
        GetOffPageConnectorFromID {
            foreach key [array names ::data *,id] {
                set o [lindex [split $key ,] 0]
                if {![info exists ::dead($o)] && $::data($key)==[lindex $args 0]} {return $o}
            }
            return NULL
        }
        ReplaceGraphicInst {
            incr ::writes
            if {$::failOnce} {set ::failOnce 0; return NULL}
            set old [lindex $args 0]
            set new n[incr ::serial]
            foreach key [array names ::data $old,*] {
                set field [lindex [split $key ,] 1]
                set ::data($new,$field) $::data($key)
            }
            set ::data($new,id) [expr {100+$::serial}]
            # Native replacement uses its third argument as the instance's
            # name. The old mock incorrectly preserved the old name here.
            set ::data($new,name) [lindex $args 2]
            # Reproduce native loss of both display metadata and IREF data.
            set ::data($new,irefDisplay) 0
            if {[info exists ::data($new,irefValue)]} {set ::data($new,irefValue) ""}
            if {!$::badTarget} {set ::data($new,source) [lindex $args 1]} else {set ::badTarget 0}
            set ::dead($old) 1
            interp alias {} $new {} object $new
            return $new
        }
        default {error "Unexpected page method $method"}
    }
}
proc iterator {method args} {
    if {![llength $::iter]} {set ::statusCode([lindex $args 0]) 1022; return NULL}
    set o [lindex $::iter 0]
    set ::iter [lrange $::iter 1 end]
    return $o
}
proc propertyNext {kind method s} {
    if {$::propertyIterError} {set ::statusCode($s) $::propertyIterError; return NULL}
    if {$::propertyRemaining > 0} {incr ::propertyRemaining -1; return ${kind}Property}
    set ::statusCode($s) 1022
    return NULL
}
interp alias {} userIterator {} propertyNext user
interp alias {} displayIterator {} propertyNext display
proc userProperty {method args} {
    switch $method {GetName {return Notes} GetStringValue {return Test} default {error $method}}
}
proc displayProperty {method args} {
    switch $method {
        GetName {return Name}
        GetLocation {return {5 6}}
        GetRotation - GetColor - GetDisplayType {return 0}
        GetFont {return good}
        default {error $method}
    }
}
proc invalidEnd {method s} {set ::statusCode($s) 1022; return nonNullObject}
proc cleanEnd {method s} {return NULL}
proc irefNext {o method s} {
    if {$::irefRemaining($o)} {
        set ::irefRemaining($o) 0
        interp alias {} iref_$o {} irefProperty $o
        return iref_$o
    }
    set ::statusCode($s) 1022; return NULL
}
proc irefProperty {o method args} {
    if {[info exists ::dead($o)]} {error "Stale display pointer used"}
    switch $method {
        GetName {return IREF}
        GetFont - SetFont {return good}
        GetLocation {return $::data($o,dispLocation)}
        GetRotation {return $::data($o,dispRotation)}
        GetColor {return $::data($o,dispColor)}
        GetDisplayType {return $::data($o,dispType)}
        SetLocation {set ::data($o,dispLocation) [lindex $args 0]}
        SetRotation {set ::data($o,dispRotation) [lindex $args 0]}
        SetColor {set ::data($o,dispColor) [lindex $args 0]}
        SetDisplayType {set ::data($o,dispType) [lindex $args 0]}
        default {error "Unexpected display method $method"}
    }
    return good
}
proc withIref {} {
    reset
    set ::data(o1,irefDisplay) 1
    set ::data(o1,irefValue) {[3,19]}
    set ::data(o1,dispLocation) {120 230}
    set ::data(o1,dispRotation) 1
    set ::data(o1,dispColor) 4
    set ::data(o1,dispType) 2
    set ::data(o1,dispFont) font
}
reset
set ::propertyCount 1
array set captured [::OffPageDirection::Snapshot o1]
assert [expr {[llength $captured(users)]==1 && [llength $captured(display)]==1}] "Non-empty property snapshot failed at normal EOF"
reset
array set captured [::OffPageDirection::Snapshot o1]
assert [expr {$captured(users) eq "" && $captured(display) eq ""}] "Empty property snapshot failed at normal EOF"
set ::propertyIterError 99
assert [catch {::OffPageDirection::Execute}] "Real iterator failure was swallowed"
assert [expr {$::writes==0}] "Read failure must abort before replacement"
reset
set ::readError 1022
assert [catch {::OffPageDirection::Snapshot o1}] "1022 outside iterator must remain an error"
assert [catch {::OffPageDirection::Next invalidEnd NextProp}] "1022 with a non-NULL result must fail"
assert [expr {[::OffPageDirection::Next cleanEnd NextProp] eq "NULL"}] "Successful NULL must be supported"
puts "PASS: normal 1022 EOF (empty/non-empty), genuine iterator error, non-iterator error, no writes on read failure"
reset
foreach name {OFFPAGELEFT-L OFFPAGELEFT-R OFFPAGELEFT/L OFFPAGELEFT/R} {
    assert [expr {[::OffPageDirection::Target [::OffPageDirection::Target $name]] eq $name}] "Pair involution failed"
}
assert [catch {::OffPageDirection::Target CUSTOM}] "Custom symbol must be rejected"
for {set rot 0} {$rot < 4} {incr rot} {
    foreach mirror {0 1} {
        reset
        set ::data(o1,rotation) $rot; set ::data(o1,mirror) $mirror
        set old [::OffPageDirection::Snapshot o1]
        array set r $old
        ::OffPageDirection::Execute
        set first n$::serial
        ::OffPageDirection::Verify $first $old OFFPAGELEFT-R [::OffPageDirection::Reflected $r(basis)]
        set ::selection [list $first]
        # The only L instance was replaced. Add a cached counterpart to mock
        # Capture's library cache without touching the live object.
        set ::data(o2,source) OFFPAGELEFT-L
        ::OffPageDirection::Execute
        ::OffPageDirection::Verify n$::serial $old OFFPAGELEFT-L $r(basis)
        assert [expr {$::data(n$::serial,location) eq $r(location)}] "Round trip moved symbol"
    }
}
puts "PASS: 8 rotations/mirrors, double toggle, special-character name, hotspot and wire preservation"
reset
set ::data(o1,source) CUSTOM
assert [catch {::OffPageDirection::Execute}] "Unsupported must fail"
assert [expr {$::writes==0}] "Unsupported selection mutated design"
reset
set ::selection {}
assert [catch {::OffPageDirection::Execute}] "Empty selection must fail"
assert [expr {$::writes==0}] "Empty selection mutated design"
reset
set ::data(o2,source) OFFPAGELEFT-L
assert [catch {::OffPageDirection::Execute}] "Missing counterpart must fail"
assert [expr {$::writes==0}] "Missing counterpart mutated design"
reset
set ::badTarget 1
assert [catch {::OffPageDirection::Execute}] "Silent replacement no-op must fail"
assert [expr {$::data(n$::serial,source) eq "OFFPAGELEFT-L"}] "Rollback failed"
reset
set ::failOnce 1
assert [catch {::OffPageDirection::Execute}] "Native NULL must fail"
assert [expr {$::data(o1,source) eq "OFFPAGELEFT-L" && $::writes==1}] "NULL should preserve unchanged original"
reset
set ::selection {o1 o2}
::OffPageDirection::Execute
assert [expr {$::writes==2 && $::data(n1,source) eq "OFFPAGELEFT-R" && $::data(n2,source) eq "OFFPAGELEFT-L"}] "Batch toggle failed"
puts "PASS: preflight abort, empty selection, native NULL, silent no-op, rollback, no stale-pointer reuse"
reset
::OffPageDirection::SetVerified o1 SetRotation GetRotation 0
assert [expr {$::setterCalls==0}] "No-op setter was called"
set ::setterCodeOne 1
set original [::OffPageDirection::Snapshot o1]
unset old
array set old $original
::OffPageDirection::Execute
::OffPageDirection::Verify n$::serial $original OFFPAGELEFT-R [::OffPageDirection::Reflected $old(basis)]
assert [expr {$::data(n$::serial,name) eq $old(name)}] "Native replacement used library name instead of net name"
puts "PASS: no-op writes skipped; setter code 1 accepted only after matching readback; native instance name preserved"
reset
set ::ignoreRotationOnce 1
set original [::OffPageDirection::Snapshot o1]
array set old $original
assert [catch {::OffPageDirection::Execute} why] "Code 1 with wrong readback must fail"
assert [expr {[string first "SetRotation not retained" $why]>=0}] "Unexpected failure: $why"
assert [expr {[string first "RESTORE FAILED" $why]<0}] "Independent recovery failed: $why"
::OffPageDirection::Verify n$::serial $original OFFPAGELEFT-L $old(basis)
assert [expr {$::data(n$::serial,rotation)==$old(rotation) && $::data(n$::serial,mirror)==$old(mirror) && $::data(n$::serial,location) eq $old(location)}] "Recovery did not restore exact saved geometry"
puts "PASS: forward orientation error restores original symbol, net name and geometry without reusing Orient"
withIref
set original [::OffPageDirection::Snapshot o1]
array set saved $original
::OffPageDirection::Execute
::OffPageDirection::Verify n$::serial $original OFFPAGELEFT-R [::OffPageDirection::Reflected $saved(basis)]
assert [expr {$::displayCreates==1 && $::data(n$::serial,irefValue) eq {[3,19]}}] "IREF display/value not restored"
assert [expr {$::data(n$::serial,dispFont) eq "font"}] "Saved font not passed to creation"
puts "PASS: native IREF loss recreated with original value, position, rotation, color, visibility and font argument"
withIref
set original [::OffPageDirection::Snapshot o1]
array set saved $original
set ::createFails 1
assert [catch {::OffPageDirection::Execute} why] "Creation error must not report success"
assert [expr {[string first "RESTORE FAILED" $why]<0}] "IREF recovery failed: $why"
::OffPageDirection::Verify n$::serial $original OFFPAGELEFT-L $saved(basis)
puts "PASS: display creation failure rolls back original symbol and recreates original IREF"
withIref
set ::irefReadFails 1
assert [catch {::OffPageDirection::Execute}] "Unreadable IREF must abort"
assert [expr {$::writes==0}] "Unreadable IREF must fail before replacement"
withIref
set ::ignoreIrefWrite 1
assert [catch {::OffPageDirection::Execute}] "Ignored IREF value write must fail"
withIref
set ::createFails 2
assert [catch {::OffPageDirection::Execute} why] "Repeated creation failure must not report success"
assert [expr {[string first "RESTORE FAILED" $why]>=0}] "Incomplete IREF recovery must be reported"
puts "PASS: unreadable/lost backing value and unrecoverable display failure remain errors"

# Exercise the real hotkey callback without pre-acknowledging a first-use flag.
reset
set ::messages {}
set original [::OffPageDirection::Snapshot o1]
array set saved $original
::OffPageDirection::Run
assert [expr {[llength $::messages]==0 && $::writes==1 && !$::OffPageDirection::Busy}] "First hotkey use prompted or failed"
::OffPageDirection::Verify n$::serial $original OFFPAGELEFT-R [::OffPageDirection::Reflected $saved(basis)]
set ::selection [list n$::serial]
set ::data(o2,source) OFFPAGELEFT-L
::OffPageDirection::Run
assert [expr {[llength $::messages]==0 && $::writes==2 && !$::OffPageDirection::Busy}] "Repeated hotkey use prompted or failed"
::OffPageDirection::Verify n$::serial $original OFFPAGELEFT-L $saved(basis)
reset
set ::data(o1,source) CUSTOM
::OffPageDirection::Run
assert [expr {[llength $::messages]==1 && $::writes==0 && !$::OffPageDirection::Busy}] "Hotkey failure must still show an error and release busy state"
set errorDialog [lindex $::messages 0]
assert [expr {[lindex $errorDialog [expr {[lsearch -exact $errorDialog -icon]+1}]] eq "error"}] "Failure dialog is not an error"
puts "PASS: first/repeated Alt+F5 execute silently; names and geometry verified; actual error popup retained"
