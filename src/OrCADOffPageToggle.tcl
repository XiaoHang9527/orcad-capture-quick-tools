# OrCAD Capture 16.6 / Tcl 8.4. Native off-page graphic replacement.
# No NewOffPageConnector/DeleteOffPageConnector fallback: those can leave
# dangling editor objects in older Capture builds. Test on a saved COPY first.
namespace eval ::OffPageDirection {
    variable Busy 0
    variable LogFile ""
}

proc ::OffPageDirection::Null {o} {expr {$o eq "" || $o eq "NULL"}}
proc ::OffPageDirection::Check {s stage} {
    if {![$s Succeeded]} {
        set msg [DboTclHelper_sMakeCString]
        $s Message $msg
        error "$stage: [DboTclHelper_sGetConstCharPtr $msg] (code [$s Code])"
    }
}
# DboState is mutable. A completed iterator leaves code 1022 (normal EOF),
# which must not be checked as the result of an unrelated property read.
# Accept 1022 ONLY for Next* returning NULL; all other failures remain fatal.
proc ::OffPageDirection::Next {iterator method} {
    set s [DboState]
    set o [$iterator $method $s]
    if {[Null $o] && [$s Code] == 1022} {return NULL}
    Check $s $method
    return $o
}
proc ::OffPageDirection::Read {o method} {
    set s [DboState]
    set value [$o $method $s]
    Check $s $method
    return $value
}
proc ::OffPageDirection::Text {o method} {
    set value [DboTclHelper_sMakeCString]
    Check [$o $method $value] $method
    return [DboTclHelper_sGetConstCharPtr $value]
}
proc ::OffPageDirection::PropertyValue {o name} {
    set value [DboTclHelper_sMakeCString]
    Check [$o GetEffectivePropStringValue [DboTclHelper_sMakeCString $name] $value] "Read property $name"
    return [DboTclHelper_sGetConstCharPtr $value]
}
proc ::OffPageDirection::SetPropertyVerified {o name value} {
    if {![catch {PropertyValue $o $name} current] && $current eq $value} {return}
    set s [$o SetEffectivePropStringValue [DboTclHelper_sMakeCString $name] [DboTclHelper_sMakeCString $value]]
    if {![$s Succeeded] && [$s Code] != 1} {Check $s "Write property $name"}
    if {[PropertyValue $o $name] ne $value} {error "Property value not retained: $name"}
}
proc ::OffPageDirection::XY {p} {
    list [DboTclHelper_sGetCPointX $p] [DboTclHelper_sGetCPointY $p]
}
proc ::OffPageDirection::Point {xy} {
    DboTclHelper_sMakeCPoint [lindex $xy 0] [lindex $xy 1]
}
proc ::OffPageDirection::Delta {a b} {
    list [expr {[lindex $a 0]-[lindex $b 0]}] [expr {[lindex $a 1]-[lindex $b 1]}]
}
proc ::OffPageDirection::Target {name} {
    switch -- [string toupper $name] {
        OFFPAGELEFT-L {return OFFPAGELEFT-R}
        OFFPAGELEFT-R {return OFFPAGELEFT-L}
        OFFPAGELEFT/L {return OFFPAGELEFT/R}
        OFFPAGELEFT/R {return OFFPAGELEFT/L}
        default {error "Unsupported off-page symbol: $name"}
    }
}
proc ::OffPageDirection::Log {message} {
    variable LogFile
    puts "Off-page toggle: $message"
    if {$LogFile ne ""} {
        set f [open $LogFile a]
        fconfigure $f -encoding utf-8
        puts $f $message
        close $f
    }
}

# Work only with typed objects returned by the page iterator. Never cast
# arbitrary selections (labels, parts, wires) to off-page connector pointers.
proc ::OffPageDirection::Connectors {page} {
    set s [DboState]
    set it [$page NewOffPageConnectorsIter $s]
    Check $s NewOffPageConnectorsIter
    if {[Null $it]} {error "Cannot enumerate off-page connectors"}
    set result {}
    set code [catch {
        for {set o [Next $it NextOffPageConnector]} {![Null $o]} {set o [Next $it NextOffPageConnector]} {
            lappend result $o
        }
    } message]
    delete_DboPageOffPageConnectorsIter $it
    if {$code} {error $message}
    return $result
}
proc ::OffPageDirection::Pages {design} {
    set s [DboState]
    set views [$design NewViewsIter $s $::IterDefs_SCHEMATICS]
    Check $s NewViewsIter
    if {[Null $views]} {error "Cannot enumerate design schematics"}
    set result {}
    set pages NULL
    set code [catch {
        for {set v [Next $views NextView]} {![Null $v]} {set v [Next $views NextView]} {
            set sch [DboViewToDboSchematic $v]
            set pages [Read $sch NewPagesIter]
            if {[Null $pages]} {error "Cannot enumerate schematic pages"}
            for {set p [Next $pages NextPage]} {![Null $p]} {set p [Next $pages NextPage]} {lappend result $p}
            delete_DboSchematicPagesIter $pages
            set pages NULL
        }
    } message]
    if {![Null $pages]} {delete_DboSchematicPagesIter $pages}
    delete_DboLibViewsIter $views
    if {$code} {error $message}
    return $result
}
proc ::OffPageDirection::LibrarySymbol {lib name} {
    set s [DboState]
    set sym [$lib GetSymbol [DboTclHelper_sMakeCString $name] $s]
    if {![Null $sym] && [$s Succeeded]} {return $sym}
    # Cached symbol names can differ from source symbol names. Do not guess
    # their suffixes or reinterpret an opaque DboOffPageSymbol pointer.
    return NULL
}
proc ::OffPageDirection::Resolve {design pages source target} {
    # Reuse the design's actual symbol definitions, including old library
    # paths that no longer exist on this computer.
    foreach page $pages {
        foreach o [Connectors $page] {
            if {[string equal -nocase [Text $o GetSourceSymbolName] $target] &&
                [string equal -nocase [string map {\\ /} [Text $o GetSourceLibName]] [string map {\\ /} $source]]} {
                set s [DboState]
                set sym [$o GetSymbol $s]
                Check $s GetSymbol
                if {![Null $sym]} {return $sym}
            }
        }
    }
    # Do not substitute a stock symbol for a slash-named custom library part.
    set paths [list $source]
    if {[string match OFFPAGELEFT-* $target]} {
        lappend paths [file join [file dirname [info nameofexecutable]] library capsym.olb]
    }
    foreach path $paths {
        if {$path eq "" || ![file isfile $path]} {continue}
        set s [DboState]
        set lib [$::DboSession_s_pDboSession GetLib [DboTclHelper_sMakeCString $path] $s]
        if {[Null $lib] || ![$s Succeeded]} {continue}
        set sym [LibrarySymbol $lib $target]
        if {![Null $sym]} {return $sym}
    }
    error "Cannot find counterpart $target in this design or its source library: $source. Place one counterpart from the same library first, then retry."
}

proc ::OffPageDirection::Basis {o} {
    set zero [XY [$o GetOffsetGraphicPoint [Point {0 0}]]]
    set x [XY [$o GetOffsetGraphicPoint [Point {10 0}]]]
    set y [XY [$o GetOffsetGraphicPoint [Point {0 10}]]]
    return [list [Delta $x $zero] [Delta $y $zero]]
}
proc ::OffPageDirection::Reflected {basis} {
    list [Delta {0 0} [lindex $basis 0]] [lindex $basis 1]
}
proc ::OffPageDirection::WireId {o} {
    set s [DboState]
    set wire [$o GetWire $s]
    Check $s GetWire
    if {[Null $wire]} {return ""}
    set id [$wire GetId $s]
    Check $s GetWireId
    return $id
}
proc ::OffPageDirection::Snapshot {o} {
    array set r {}
    set r(id) [Read $o GetId]
    set r(name) [Text $o GetName]
    set r(source) [Text $o GetSourceSymbolName]
    set r(library) [Text $o GetSourceLibName]
    set r(symbol) [Read $o GetSymbol]
    set r(location) [XY [Read $o GetLocation]]
    set r(hotspot) [XY [Read $o GetOffsetHotSpot]]
    set r(rotation) [Read $o GetRotation]
    set r(mirror) [Read $o GetMirror]
    set r(color) [Read $o GetColor]
    set r(basis) [Basis $o]
    set r(wire) [WireId $o]
    set r(users) {}
    set it [Read $o NewUserPropsIter]
    if {![Null $it]} {
        set code [catch {
            for {set prop [Next $it NextUserProp]} {![Null $prop]} {set prop [Next $it NextUserProp]} {
                lappend r(users) [list [Text $prop GetName] [Text $prop GetStringValue]]
            }
        } message]
        delete_DboUserPropsIter $it
        if {$code} {error $message}
    }
    set r(display) {}
    set r(displayValues) {}
    set it [Read $o NewDisplayPropsIter]
    if {![Null $it]} {
        set code [catch {
            for {set prop [Next $it NextProp]} {![Null $prop]} {set prop [Next $it NextProp]} {
                set name [Text $prop GetName]
                # IREF may not be in NewUserPropsIter. Preserve its underlying
                # value, not a formatted label copied into an unrelated field.
                # An unreadable value aborts here, before any replacement.
                if {[string equal -nocase $name IREF]} {
                    lappend r(displayValues) [list $name [PropertyValue $o $name]]
                }
                set font [DboTclHelper_sMakeLOGFONT]
                Check [$prop GetFont $::DboLib_DEFAULT_FONT_PROPERTY $font] GetFont
                lappend r(display) [list $name [XY [Read $prop GetLocation]] \
                    [Read $prop GetRotation] [Read $prop GetColor] [Read $prop GetDisplayType] $font]
            }
        } message]
        delete_DboDisplayPropsIter $it
        if {$code} {error $message}
    }
    return [array get r]
}
proc ::OffPageDirection::SetVerified {o setter getter value {kind scalar}} {
    if {$kind eq "text"} {
        set before [Text $o $getter]
        set argument [DboTclHelper_sMakeCString $value]
    } elseif {$kind eq "point"} {
        set before [XY [Read $o $getter]]
        set argument [Point $value]
    } else {
        set before [Read $o $getter]
        set argument $value
    }
    # Capture can return code 1 for a setter. Avoid no-op writes altogether;
    # never assume that code 1 by itself means success.
    if {$before eq $value} {return}
    set result [$o $setter $argument]
    if {$kind eq "text"} {
        set after [Text $o $getter]
    } elseif {$kind eq "point"} {
        set after [XY [Read $o $getter]]
    } else {set after [Read $o $getter]}
    if {![$result Succeeded] && [$result Code] != 1} {Check $result $setter}
    if {$after ne $value} {error "$setter not retained: expected=$value actual=$after code=[$result Code]"}
    if {![$result Succeeded]} {Log "$setter code=[$result Code], verified actual value=$after"}
}
proc ::OffPageDirection::Orient {o basis snapshot} {
    array set r $snapshot
    SetVerified $o SetRotation GetRotation $r(rotation)
    SetVerified $o SetMirror GetMirror $r(mirror)
    if {[Basis $o] eq $basis} {return}
    # Toggle the local reflection first. If Capture mirrors the other local
    # axis, one half-turn completes the desired reflection. No 8-state trial
    # loop on live objects. The final basis MUST match the requested basis.
    SetVerified $o SetMirror GetMirror [expr {!$r(mirror)}]
    set actual [Basis $o]
    if {$actual eq $basis} {return}
    set opposite [list [Delta {0 0} [lindex $basis 0]] [Delta {0 0} [lindex $basis 1]]]
    if {$actual ne $opposite} {error "Unsupported native mirror transform; stopping"}
    set rotations [list $::DboValue_NOROTATION $::DboValue_NINETY $::DboValue_ONEEIGHTY $::DboValue_TWOSEVENTY]
    set index [lsearch -exact $rotations $r(rotation)]
    if {$index < 0} {error "Unknown saved rotation: $r(rotation)"}
    SetVerified $o SetRotation GetRotation [lindex $rotations [expr {($index+2)%4}]]
    if {[Basis $o] ne $basis} {error "Cannot preserve the connector's wire side at this orientation"}
}
proc ::OffPageDirection::RestoreProperties {o snapshot} {
    array set r $snapshot
    SetVerified $o SetName GetName $r(name) text
    SetVerified $o SetColor GetColor $r(color)
    foreach pair $r(users) {
        SetPropertyVerified $o [lindex $pair 0] [lindex $pair 1]
    }
    if {[info exists r(displayValues)]} {
        foreach pair $r(displayValues) {SetPropertyVerified $o [lindex $pair 0] [lindex $pair 1]}
    }
    set failures {}
    foreach item $r(display) {
        foreach {name xy rot color type font} $item break
        # Process every saved display property, including during recovery.
        # Do not let a failure on IREF prevent restoring the Name label.
        if {[catch {RestoreDisplay $o $item} why]} {lappend failures "$name: $why"}
    }
    if {[llength $failures]} {error "Display restoration failed: $failures"}
}
proc ::OffPageDirection::RestoreDisplay {o item} {
        foreach {name xy rot color type font} $item break
        set s [DboState]
        set p [$o GetDisplayProp [DboTclHelper_sMakeCString $name] $s]
        set created 0
        if {[Null $p]} {
            # GetDisplayProp may leave a not-found status. Use a new DboState
            # for creation. No pointers owned by the deleted instance are used.
            set createStatus [DboState]
            set p [$o NewDisplayProp $createStatus [DboTclHelper_sMakeCString $name] [Point $xy] $rot $font $color]
            if {[Null $p]} {error "Cannot recreate missing display property: $name"}
            Check $createStatus "NewDisplayProp $name"
            set lookupStatus [DboState]
            set retained [$o GetDisplayProp [DboTclHelper_sMakeCString $name] $lookupStatus]
            Check $lookupStatus "Read recreated display property $name"
            if {[Null $retained]} {error "Capture did not retain recreated display property: $name"}
            set p $retained
            set created 1
            Log "Recreated display property: $name"
        } else {Check $s "GetDisplayProp $name"}
        SetVerified $p SetLocation GetLocation $xy point
        SetVerified $p SetRotation GetRotation $rot
        SetVerified $p SetColor GetColor $color
        SetVerified $p SetDisplayType GetDisplayType $type
        # NewDisplayProp already received the saved font.
        if {!$created} {Check [$p SetFont $font] SetDisplayFont}
}
proc ::OffPageDirection::Verify {o snapshot expected basis} {
    array set r $snapshot
    set s [DboState]
    if {[Text $o GetName] ne $r(name)} {error "Net name did not survive replacement"}
    if {![string equal -nocase [Text $o GetSourceSymbolName] $expected]} {error "Capture did not retain symbol $expected"}
    if {[XY [$o GetOffsetHotSpot $s]] ne $r(hotspot)} {error "Connection point moved"}
    if {[Basis $o] ne $basis} {error "Graphic orientation did not change as requested"}
    if {[WireId $o] ne $r(wire)} {error "Wire attachment changed"}
    foreach pair $r(users) {
        set value [DboTclHelper_sMakeCString]
        Check [$o GetEffectivePropStringValue [DboTclHelper_sMakeCString [lindex $pair 0]] $value] ReadUserProperty
        if {[DboTclHelper_sGetConstCharPtr $value] ne [lindex $pair 1]} {error "User property did not survive: [lindex $pair 0]"}
    }
    if {[info exists r(displayValues)]} {
        foreach pair $r(displayValues) {
            if {[PropertyValue $o [lindex $pair 0]] ne [lindex $pair 1]} {error "Display backing value changed: [lindex $pair 0]"}
        }
    }
    foreach item $r(display) {
        foreach {name xy rot color type font} $item break
        set p [$o GetDisplayProp [DboTclHelper_sMakeCString $name] $s]
        if {[Null $p]} {error "Missing display property: $name"}
        if {[XY [$p GetLocation $s]] ne $xy || [$p GetRotation $s] != $rot ||
            [$p GetColor $s] != $color || [$p GetDisplayType $s] != $type} {
            error "Display property changed: $name"
        }
    }
}
proc ::OffPageDirection::Replace {page object snapshot symbol name basis currentIdVar} {
    upvar 1 $currentIdVar currentId
    array set r $snapshot
    set s [DboState]
    Log "Replacing id=$currentId name=$r(name) $r(source) -> $name"
    # Native replacement owns the original object's lifetime. Never dereference
    # 'object' again after this call, even when Capture returns an error status.
    set fresh [$page ReplaceGraphicInst $object $symbol [DboTclHelper_sMakeCString $r(name)] $s]
    if {[Null $fresh]} {error "Native ReplaceGraphicInst returned NULL"}
    if {[$fresh GetObjectType] != 38} {error "Replacement is not an off-page connector"}
    set ns [DboGraphicInstanceToDboNetSymbolInstance $fresh]
    set o [DboNetSymbolInstanceToDboOffPageConnector $ns]
    set idStatus [DboState]
    set currentId [$o GetId $idStatus]
    # Restore/check the net name BEFORE orientation, location or style. The
    # native packageName argument is the instance name, not the library name.
    SetVerified $o SetName GetName $r(name) text
    Check $s ReplaceGraphicInst
    Orient $o $basis $snapshot
    set hot [XY [$o GetOffsetHotSpot $idStatus]]
    set loc [XY [$o GetLocation $idStatus]]
    set shift [Delta $r(hotspot) $hot]
    set position [list [expr {[lindex $loc 0]+[lindex $shift 0]}] [expr {[lindex $loc 1]+[lindex $shift 1]}]]
    SetVerified $o SetLocation GetLocation $position point
    RestoreProperties $o $snapshot
    DboTclHelper_sEvalPage $page
    Verify $o $snapshot $name $basis
    Log "Verified id=$currentId name=$r(name) hotspot=$r(hotspot) symbol=$name"
    return $o
}

# Recovery is intentionally separate from forward replacement: never call
# Orient while rolling back. Attempt independent saved fields even if one
# fails, particularly the net name. Do not stop recovery at a style error.
proc ::OffPageDirection::RestoreOriginal {page o saved idVar} {
    upvar 1 $idVar id
    array set r $saved
    set failures {}
    if {[catch {SetVerified $o SetName GetName $r(name) text} why]} {lappend failures "name: $why"}
    if {![string equal -nocase [Text $o GetSourceSymbolName] $r(source)]} {
        set s [DboState]
        set fresh [$page ReplaceGraphicInst $o $r(symbol) [DboTclHelper_sMakeCString $r(name)] $s]
        # Old o is invalid from this point. Never try it after a native failure.
        if {[Null $fresh]} {error "RestoreGraphicInst returned NULL; cannot safely reuse original object"}
        if {[$fresh GetObjectType] != 38} {error "Restoration did not return an off-page connector"}
        set o [DboNetSymbolInstanceToDboOffPageConnector [DboGraphicInstanceToDboNetSymbolInstance $fresh]]
        set id [Read $o GetId]
        if {[catch {Check $s RestoreGraphicInst} why]} {lappend failures $why}
    }
    foreach action [list \
        [list SetVerified $o SetName GetName $r(name) text] \
        [list SetVerified $o SetRotation GetRotation $r(rotation)] \
        [list SetVerified $o SetMirror GetMirror $r(mirror)] \
        [list SetVerified $o SetLocation GetLocation $r(location) point] \
        [list RestoreProperties $o $saved]] {
        if {[catch {eval $action} why]} {lappend failures $why}
    }
    if {[catch {DboTclHelper_sEvalPage $page} why]} {lappend failures $why}
    if {[catch {Verify $o $saved $r(source) $r(basis)} why]} {lappend failures $why}
    if {[llength $failures]} {error "Recovery errors: $failures"}
    Log "RESTORED id=$id name=$r(name) symbol=$r(source) rotation=$r(rotation) mirror=$r(mirror) location=$r(location)"
}

proc ::OffPageDirection::Execute {} {
    set page [GetActivePage]
    if {[Null $page]} {error "Open a schematic page first"}
    array set selected {}
    set s [DboState]
    foreach o [GetSelectedObjects] {
        if {[DboBaseObject_GetObjectType $o] == 38} {set selected([$o GetId $s]) 1}
    }
    if {![array size selected]} {error "Select the off-page SYMBOL itself, not only its text, then press Alt+F5"}
    set design [$page GetContainingLib]
    set pages [Pages $design]
    set plan {}
    array set symbols {}
    foreach o [Connectors $page] {
        set id [$o GetId $s]
        if {![info exists selected($id)]} {continue}
        if {[$o IsObjLocked]} {error "Selected off-page connector is locked: $id"}
        array set r [Snapshot $o]
        Log "SNAPSHOT id=$id name=[list $r(name)] source=$r(source) rotation=$r(rotation) mirror=$r(mirror) location=$r(location) hotspot=$r(hotspot)"
        set target [Target $r(source)]
        set key [list $r(library) $target]
        if {![info exists symbols($key)]} {set symbols($key) [Resolve $design $pages $r(library) $target]}
        set symbol $symbols($key)
        lappend plan [list $id [array get r] $symbol $target]
    }
    if {[llength $plan] != [array size selected]} {error "Selection is not confined to the current page"}
    # The user explicitly requested direct execution, including the first use.
    # Backup/usage guidance is in Alt+F1; validation and recovery stay enabled.
    # All lookups and snapshots completed before the first write. Clear editor
    # selection before replacement to avoid dangling selected-object pointers.
    UnSelectAll
    set journal {}
    set changed 0
    set currentId ""
    set inFlight 0
    set code [catch {
        foreach item $plan {
            set inFlight 0
            foreach {currentId snapshot symbol target} $item break
            array set r $snapshot
            set o [$page GetOffPageConnectorFromID $currentId]
            if {[Null $o]} {error "Selected object disappeared before replacement"}
            lappend journal [list $currentId $snapshot]
            set inFlight 1
            set new [Replace $page $o $snapshot $symbol $target [Reflected $r(basis)] currentId]
            set journal [lreplace $journal end end [list $currentId $snapshot]]
            set inFlight 0
            incr changed
        }
        Check [$page MarkModified] MarkModified
        DboTclHelper_sEvalPage $page
        Menu "View::Zoom::Redraw"
    } message]
    if {$code} {
        set details $::errorInfo
        Log "FAILED: $details"
        # The failing native call may already have returned a new object ID.
        if {$inFlight} {set journal [lreplace $journal end end [list $currentId $snapshot]]}
        set failures {}
        for {set i [expr {[llength $journal]-1}]} {$i >= 0} {incr i -1} {
            foreach {id saved} [lindex $journal $i] break
            array set old $saved
            if {[catch {
                set o [$page GetOffPageConnectorFromID $id]
                if {[Null $o]} {error "Cannot locate replacement id=$id"}
                if {[catch {Verify $o $saved $old(source) $old(basis)}]} {
                    RestoreOriginal $page $o $saved id
                }
            } why]} {lappend failures "$old(name): $why"}
        }
        catch {DboTclHelper_sEvalPage $page}
        catch {Menu "View::Zoom::Redraw"}
        if {[llength $failures]} {
            Log "RESTORE FAILURES: $failures"
            error "$message\n\nRESTORE FAILED: $failures\nClose this test copy WITHOUT saving and reopen your backup."
        }
        error "$message\n\nProcessed connectors restored. No success reported."
    }
    Log "SUCCESS: changed=$changed; names, connection points and wire IDs verified"
}
proc ::OffPageDirection::Run {} {
    variable Busy
    variable LogFile
    if {$Busy} {return}
    set Busy 1
    set code [catch {
        set LogFile [file join $::env(TEMP) OrCADOffPageToggle.log]
        Log "--- [clock format [clock seconds]] version=0.2.4 ---"
        Execute
    } message]
    set Busy 0
    if {$code} {
        catch {Log "ERROR: $message\n$::errorInfo"}
        tk_messageBox -type ok -icon error -title "Off-page Toggle - Alt+F5" \
            -message "\u8DE8\u9875\u7B26\u53F7\u66FF\u6362\u672A\u5B8C\u6210\uFF1A\n$message\n\n\u8BCA\u65AD\u65E5\u5FD7\uFF1A\n$LogFile"
    }
}
