# OrCAD Capture 16.6 quick tools.
# Alt+F1: show all quick-tool shortcuts.
# Alt+F2: add "NC," to selected part values.
# Alt+F3: remove one leading "NC," from selected part values.
# Alt+F5: replace selected off-page input/output graphics, preserving names.
# Alt+F6: export selected part pin-to-net data to an Excel workbook.
# Alt+Shift+F6: export all placed parts on every page of the current DSN.
# Alt+F7: update every title block Doc and synchronize Title with Page Name.
# Alt+F8: reannotate the current page from left to right, top to bottom.
# Alt+F9: reannotate all pages by position using existing page numbers.
# Alt+F10: reset Page Number and Page Count only.
# Alt+R: move selected misplaced references into the current page range.
# Alt+S: open native Signals navigation for one selected scalar wire.

package require Tcl 8.4
set ::QuickToolsDboLoadFailed [catch {package require DboTclWriteBasic 16.3.0} ::QuickToolsDboLoadResult]

namespace eval ::OrCADQuickTools {
    variable ScriptDirectory [file dirname [info script]]
    if {![info exists RegisteredActions]} {variable RegisteredActions; array set RegisteredActions {}}
    if {![info exists MenuEventsRegistered]} {variable MenuEventsRegistered 0}
}

proc ::OrCADQuickTools::TempDirectory {} {
    foreach name {TMP TEMP USERPROFILE} {
        if {[info exists ::env($name)] && $::env($name) ne "" &&
            [file isdirectory $::env($name)] && [file writable $::env($name)]} {
            return [file normalize $::env($name)]
        }
    }
    return ""
}

proc ::OrCADQuickTools::TempPath {name} {
    set directory [TempDirectory]
    if {$directory eq ""} {return ""}
    return [file join $directory $name]
}

proc ::OrCADQuickTools::PreferencePath {name} {
    if {[info exists ::env(LOCALAPPDATA)] && $::env(LOCALAPPDATA) ne ""} {
        return [file join $::env(LOCALAPPDATA) OrCADQuickTools $name]
    }
    return [TempPath [file join OrCADQuickTools $name]]
}

# Read-only Capture calls. Fresh DboState objects distinguish an empty
# iterator from a failed read, even on interfaces that do not reset status.
namespace eval ::QuickToolsDbo {}
proc ::QuickToolsDbo::Null {object} {expr {$object eq "" || $object eq "NULL"}}
proc ::QuickToolsDbo::SchematicMode {} {
    if {![info exists ::IterDefs_SCHEMATICS]} {
        set detail ""
        if {$::QuickToolsDboLoadFailed} {set detail "\nDboTclWriteBasic: $::QuickToolsDboLoadResult"}
        error "Capture's schematic database iterator is unavailable. Run this command in OrCAD Capture with a design open.$detail"
    }
    return $::IterDefs_SCHEMATICS
}
proc ::QuickToolsDbo::Check {state stage} {
    if {![$state Succeeded]} {error "$stage failed (Capture status [$state Code])."}
}
proc ::QuickToolsDbo::Next {iterator method} {
    set state [DboState]
    set code [catch {
        set object [$iterator $method $state]
        # Success can accompany an empty result. 1022 is the documented end
        # of iteration, and only valid when no object was returned.
        if {![$state Succeeded] && !([Null $object] && [$state Code] == 1022)} {
            Check $state $method
        }
    } message]
    catch {$state -delete}
    if {$code} {error $message}
    return $object
}
proc ::QuickToolsDbo::Objects {owner create next destroy args} {
    set iterator ""
    set state [DboState]
    set code [catch {
        set iterator [eval [linsert $args 0 $owner $create $state]]
        Check $state $create
        if {[Null $iterator]} {error "$create returned no iterator."}
        set objects {}
        array set seen {}
        for {set object [Next $iterator $next]} {![Null $object]} {set object [Next $iterator $next]} {
            if {[info exists seen($object)]} {error "$next repeated an object."}
            set seen($object) 1
            lappend objects $object
        }
    } message]
    if {![Null $iterator]} {catch {$destroy $iterator}}
    catch {$state -delete}
    if {$code} {error $message}
    return $objects
}
proc ::QuickToolsDbo::Read {object method} {
    set state [DboState]
    set code [catch {
        set value [$object $method $state]
        Check $state $method
    } message]
    catch {$state -delete}
    if {$code} {error $message}
    return $value
}
proc ::QuickToolsDbo::FreeStrings {pointers} {
    foreach pointer $pointers {
        if {![Null $pointer]} {catch {DboTclHelper_sDeleteCString $pointer}}
    }
}
proc ::QuickToolsDbo::String {object method args} {
    set pointers {}
    set status ""
    set code [catch {
        foreach arg $args {lappend pointers [DboTclHelper_sMakeCString $arg]}
        set value [DboTclHelper_sMakeCString]
        lappend pointers $value
        set status [eval [linsert $pointers 0 $object $method]]
        if {![Null $status] && [namespace which -command $status] ne ""} {Check $status $method}
        set result [DboTclHelper_sGetConstCharPtr $value]
    } message]
    FreeStrings $pointers
    if {![Null $status] && [namespace which -command $status] ne ""} {catch {$status -delete}}
    if {$code} {error "$method: $message"}
    return $result
}
proc ::QuickToolsDbo::WriteStrings {object method requiredStatus args} {
    set pointers {}
    set status ""
    set code [catch {
        foreach arg $args {lappend pointers [DboTclHelper_sMakeCString $arg]}
        set status [eval [linsert $pointers 0 $object $method]]
        if {$requiredStatus || (![Null $status] && [namespace which -command $status] ne "")} {
            if {[Null $status] || ![$status OK]} {error "$method failed."}
        }
    } message]
    FreeStrings $pointers
    if {![Null $status] && [namespace which -command $status] ne ""} {catch {$status -delete}}
    if {$code} {error $message}
}
proc ::QuickToolsDbo::SchematicPages {design} {
    set pages {}
    foreach view [Objects $design NewViewsIter NextView delete_DboLibViewsIter [SchematicMode]] {
        set schematic [DboViewToDboSchematic $view]
        if {[Null $schematic]} {error "Cannot read a schematic view."}
        foreach page [Objects $schematic NewPagesIter NextPage delete_DboSchematicPagesIter] {
            lappend pages [list $schematic $page]
        }
    }
    return $pages
}

# =============================================================================
# EXTENSION POINT: add one record here for each new keyboard operation.
# Fields: stable ActionName, Hotkey, Chinese Label, Enabler, Callback, Context.
# This ordered registry drives Capture registration, menu and help together.
# Implement the new callback in its own namespace; do not duplicate RegisterAction.
# Chinese UI text uses Unicode escapes for Capture 16.6 encoding compatibility.
# =============================================================================
proc ::OrCADQuickTools::ActionDefinitions {} {
    return [list \
        [list "Show OrCAD Quick Tools Shortcut Help" "Alt+F1" \
            "\u663E\u793A\u672C\u5FEB\u6377\u952E\u5217\u8868" \
            "::QuickToolsHelp::Enabler" "::QuickToolsHelp::Show" "Schematic"] \
        [list "Add NC Prefix To Selected Part Values" "Alt+F2" \
            "\u7ED9\u6240\u9009\u5668\u4EF6 Value \u524D\u6DFB\u52A0 NC," \
            "::NCValuePrefix::Enabler" "::NCValuePrefix::Run" "Schematic"] \
        [list "Remove NC Prefix From Selected Part Values" "Alt+F3" \
            "\u5220\u9664\u6240\u9009\u5668\u4EF6 Value \u5F00\u5934\u7684 NC," \
            "::NCValuePrefix::Enabler" "::NCValuePrefix::Remove" "Schematic"] \
        [list "Toggle Selected Off Page Graphics" "Alt+F5" \
            "\u5207\u6362\u6240\u9009\u8DE8\u9875\u7B26\u53F7\u7684\u8F93\u5165/\u8F93\u51FA\u56FE\u5F62\uFF08\u4FDD\u7559\u540D\u79F0\uFF09" \
            "::OffPageDirection::Enabler" "::OrCADQuickTools::ToggleOffPage" "Schematic"] \
        [list "Export Selected Part Pin Net Table To Excel" "Alt+F6" \
            "\u5BFC\u51FA\u6240\u9009\u5668\u4EF6\u7684\u5F15\u811A-\u7F51\u7EDC\u8868 (XLSX)" \
            "::SelectedPinNetExport::Enabler" "::SelectedPinNetExport::Run" "Schematic"] \
        [list "Export All Design Part Pin Net Table To Excel" "Alt+Shift+F6" \
            "\u5BFC\u51FA\u5168\u8BBE\u8BA1\u5668\u4EF6\u7684\u5F15\u811A-\u7F51\u7EDC\u8868 (XLSX)" \
            "::DesignPinNetExport::Enabler" "::DesignPinNetExport::Run" "Schematic"] \
        [list "Synchronize All Title Blocks" "Alt+F7" \
            "\u540C\u6B65\u6240\u6709\u9875\u9762\u6807\u9898\u680F" \
            "::TitleBlockSync::Enabler" "::TitleBlockSync::Run" "Schematic"] \
        [list "Reannotate Current Page By Position" "Alt+F8" \
            "\u91CD\u6392\u5F53\u524D\u9875\u5668\u4EF6\u4F4D\u53F7" \
            "::PageAutoAnnotate::Enabler" "::PageAutoAnnotate::RunCurrent" "Schematic"] \
        [list "Reannotate All Pages By Position" "Alt+F9" \
            "\u6839\u636E\u73B0\u6709 Page Number \u91CD\u6392\u6240\u6709\u9875\u4F4D\u53F7" \
            "::PageAutoAnnotate::Enabler" "::PageAutoAnnotate::RunAll" "Schematic"] \
        [list "Reset All Page Numbers" "Alt+F10" \
            "\u53EA\u91CD\u7F6E Page Number \u548C Page Count" \
            "::PageAutoAnnotate::Enabler" "::PageAutoAnnotate::RunPageNumbers" "Schematic"] \
        [list "Fix Selected Part References To Current Page" "Alt+R" \
            "\u4FEE\u6B63\u6240\u9009\u65B0\u589E\u5668\u4EF6\u4F4D\u53F7\u5230\u5F53\u524D\u9875\u53F7\u6BB5" \
            "::PageReferenceFix::Enabler" "::PageReferenceFix::Run" "Schematic"] \
        [list "Navigate Selected Net Signals" "Alt+S" \
            "\u6253\u5F00\u6240\u9009\u7F51\u7EDC\u7684 Signals \u5BFC\u822A" \
            "::SignalsNavigation::Enabler" "::SignalsNavigation::Run" "Schematic"]]
}

# -----------------------------------------------------------------------------
# Native Signals navigation (Capture 16.6 ID_FOLLOW_SIGNAL / 14844).
# The companion opens the REAL RMB menu and invokes its accessible Signals item.
# Do not dispatch 14844 after the helper: that would run the action twice.
# A returned menu action is NOT a readback of the Signals result pane.
# No database writes, pointer moves, left clicks or global key injection.
# -----------------------------------------------------------------------------
namespace eval ::SignalsNavigation {
    if {![info exists Pending]} {variable Pending ""}
    if {![info exists Busy]} {variable Busy 0}
    if {![info exists ServerDirectory]} {
        variable ServerDirectory [::OrCADQuickTools::TempPath OrCADSignalsServer-[pid]-[clock clicks]]
    }
    if {![info exists ServerStarted]} {variable ServerStarted 0}
    if {![info exists RequestStarted]} {variable RequestStarted 0}
    variable LogFile [::OrCADQuickTools::TempPath OrCADSignalsNavigation.log]
}

proc ::SignalsNavigation::Log {message} {
    variable LogFile
    set f ""
    catch {
        set f [open $LogFile a]
        fconfigure $f -encoding utf-8
        puts $f "[clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S}] $message"
        close $f; set f ""
    }
    if {$f ne ""} {catch {close $f}}
    puts "Signals navigation: $message"
}

proc ::SignalsNavigation::Notice {message} {
    catch {tk_messageBox -type ok -icon warning -title "Signals - Alt+S" -message $message}
}

proc ::SignalsNavigation::SelectedWire {} {
    if {[IsSchematicViewActive] != 1} {error "No active schematic view"}
    set objects [GetSelectedObjects]
    if {[llength $objects] != 1} {error "Select exactly one network wire"}
    set object [lindex $objects 0]
    # WIRE_SCALAR=20 is verified for Capture 16.6. Prefer its native enum.
    set scalar 20
    if {[info exists ::DboBaseObject_WIRE_SCALAR]} {set scalar $::DboBaseObject_WIRE_SCALAR}
    if {[DboBaseObject_GetObjectType $object] != $scalar} {error "Selected object is not a scalar network wire"}
    return $object
}

proc ::SignalsNavigation::Enabler {args} {
    return [expr {![catch {::SignalsNavigation::SelectedWire}]}]
}

proc ::SignalsNavigation::Snapshot {} {
    set object [SelectedWire]
    set page [GetActivePage]
    if {$page eq "" || $page eq "NULL"} {error "No active schematic page"}
    set status [DboState]
    set code [catch {
        set id [$object GetId $status]
        if {![$status OK]} {error "Cannot read selected wire identity"}
        if {![string is integer -strict $id] || $id < 0} {error "Cannot identify selected wire"}
        set netName ""
        catch {
            set text [DboTclHelper_sMakeCString]
            $object GetNetName $text
            set netName [DboTclHelper_sGetConstCharPtr $text]
        }
        # Only identities/strings cross an idle callback, not a wire pointer.
        set snapshot [list $page $id $netName]
    } message]
    catch {$status -delete}
    if {$code} {error $message}
    return $snapshot
}

proc ::SignalsNavigation::StillSelected {snapshot} {
    if {[catch {set current [Snapshot]}]} {return 0}
    return [expr {$current eq $snapshot}]
}

proc ::SignalsNavigation::Run {args} {
    variable Pending
    variable Busy
    if {$Busy} {Log "Ignored duplicate request while native context is pending"; return}
    if {$Pending ne ""} {after cancel $Pending; set Pending ""}
    if {[catch {SelectedWire} message]} {
        Log "Rejected: $message"
        # Usage belongs in Alt+F1, not in a modal dialog on first use.
        Log "Usage: select one scalar wire, keep the pointer on it, then press Alt+S; see Alt+F1"
        return
    }
    if {[catch {set snapshot [Snapshot]} message]} {
        Log "Cannot read selected network: $message"
        Notice "\u8BFB\u53D6\u6240\u9009\u7F51\u7EDC\u5931\u8D25\uFF1A\n$message"
        return
    }
    Log "Requested page=[lindex $snapshot 0] wireId=[lindex $snapshot 1] net=[lindex $snapshot 2]"
    set Pending [after idle [list ::SignalsNavigation::Refresh $snapshot]]
}

proc ::SignalsNavigation::Refresh {snapshot} {
    variable Pending
    variable Busy
    variable ServerDirectory
    variable RequestStarted
    set Pending ""
    if {![StillSelected $snapshot]} {Log "Cancelled: selection/page changed before refresh"; return}
    set resultFile [file join $ServerDirectory request-[clock clicks].result]
    set RequestStarted [clock clicks -milliseconds]
    if {[catch {StartContext $resultFile} message]} {
        Log "Context helper failed: $message"
        Notice "\u65E0\u6CD5\u5237\u65B0 Signals \u4E0A\u4E0B\u6587\uFF1A\n$message"
        return
    }
    set Busy 1
    set Pending [after 20 [list ::SignalsNavigation::PollContext $snapshot $resultFile 0]]
}

proc ::SignalsNavigation::StartContext {resultFile} {
    variable ServerDirectory
    variable ServerStarted
    set helper [file join $::OrCADQuickTools::ScriptDirectory OrCADWheelZoom.exe]
    if {![file exists $helper]} {error "Missing OrCADWheelZoom.exe"}
    if {$ServerDirectory eq ""} {error "No writable temporary directory for Signals."}
    file mkdir $ServerDirectory
    if {!$ServerStarted} {
        set started [clock clicks -milliseconds]
        exec $helper --signals-server [pid] $ServerDirectory < NUL >& NUL &
        set ServerStarted 1
        Log "Reusable Signals helper launch returned after [expr {[clock clicks -milliseconds]-$started}] ms"
    } else {
        Log "Reusing Signals helper; no process launch"
    }
    # Publish atomically AFTER the launcher returns. The server never acts on
    # staging files, and cannot replay this request after it has been claimed.
    set f ""
    if {[catch {
        set f [open "$resultFile.request-writing" {WRONLY CREAT EXCL}]
        puts -nonewline $f "capture-ready-v21"
        close $f; set f ""
        file rename "$resultFile.request-writing" "$resultFile.request"
    } message]} {
        if {$f ne ""} {catch {close $f}}
        error "Signals launch handshake failed: $message"
    }
}

proc ::SignalsNavigation::PollContext {snapshot resultFile attempt} {
    variable Pending
    variable Busy
    variable RequestStarted
    set Pending ""
    set result ""
    if {[file exists $resultFile]} {
        set f ""
        catch {
            set f [open $resultFile r]; fconfigure $f -encoding utf-8
            set result [string trim [read $f]]; close $f; set f ""
        }
        if {$f ne ""} {catch {close $f}}
    }
    # Cancel pending work if selection changes, before the server acts. Never
    # launch a replacement process or retry an uncertain native action.
    if {$result eq "" && ![StillSelected $snapshot]} {
        catch {set f [open "$resultFile.cancel" w]; close $f}
    }
    if {$result eq "" && $attempt < 275 && [expr {[clock clicks -milliseconds]-$RequestStarted}] < 5500} {
        set Pending [after 20 [list ::SignalsNavigation::PollContext $snapshot $resultFile [expr {$attempt+1}]]]
        return
    }
    if {$result eq ""} {catch {set f [open "$resultFile.cancel" w]; close $f}}
    set Busy 0
    catch {file delete $resultFile}
    catch {file delete "$resultFile.ready"}
    if {$result ne "signals-invoked" && $result ne "signals-invoked-menu-open"} {
        if {$result eq ""} {set result "Context helper timed out; update BOTH runtime files"}
        Log "Native Signals action not confirmed: $result"
        Notice "Signals \u83DC\u5355\u64CD\u4F5C\u672A\u786E\u8BA4\u5B8C\u6210\u3002\n\u8BF7\u5355\u51FB\u9009\u4E2D\u5BFC\u7EBF\uFF0C\u9F20\u6807\u505C\u7559\u5728\u8BE5\u5BFC\u7EBF\u4E0A\uFF0C\u518D\u6309 Alt+S\u3002\n\u66F4\u65B0\u65F6\u8BF7\u540C\u65F6\u66FF\u6362 TCL \u548C EXE\uFF0C\u7136\u540E\u91CD\u542F Capture\u3002\n$result"
        return
    }
    if {![StillSelected $snapshot]} {
        Log "Signals menu action returned, but selection/page/net changed; pane result not verified"
    } else {
        Log "Native Signals menu action returned; requested net=[lindex $snapshot 2] wireId=[lindex $snapshot 1]; pane result not verified"
    }
    Log "Request acknowledgement after [expr {[clock clicks -milliseconds]-$RequestStarted}] ms"
    if {$result eq "signals-invoked-menu-open"} {
        Log "Signals invoked once, but its popup is still visible; no action retry"
        Notice "Signals \u5DF2\u8C03\u7528\uFF0C\u4F46\u53F3\u952E\u83DC\u5355\u672A\u81EA\u52A8\u6536\u8D77\u3002\n\u8BF7\u6309 Esc \u5173\u95ED\u83DC\u5355\uFF0C\u65E0\u9700\u91CD\u590D\u6267\u884C Alt+S\u3002\n\u8BF7\u63D0\u4F9B OrCADSignalsNavigation-native.log \u4EE5\u4FBF\u5206\u6790\u3002"
    }
}

proc ::OrCADQuickTools::ToggleOffPage {} {
    if {[catch {
        ::OffPageDirection::Run
    } message]} {
        tk_messageBox -type ok -icon error -title "Off-page Toggle - Alt+F5" -message $message
    }
}

proc ::OrCADQuickTools::ToggleWheelZoom {} {
    if {[catch {
        ::OrCADWheel::Toggle
    } message]} {
        tk_messageBox -type ok -icon error -title "Wheel Zoom" -message $message
    }
}

proc ::OrCADQuickTools::IsPlacedPart {pObject} {
    if {[catch {set lObjectType [DboBaseObject_GetObjectType $pObject]}]} {
        return 0
    }
    # Capture 16.6: 13 is DboBaseObject_PLACED_INSTANCE.
    return [expr {$lObjectType == 13}]
}

proc ::OrCADQuickTools::HasSelectedPart {} {
    if {[catch {set lSelectedObjects [GetSelectedObjects]}]} {
        return 0
    }
    foreach lObject $lSelectedObjects {
        if {[::OrCADQuickTools::IsPlacedPart $lObject]} {
            return 1
        }
    }
    return 0
}

# -----------------------------------------------------------------------------
# Add/remove NC value prefix
# -----------------------------------------------------------------------------

namespace eval ::NCValuePrefix {
    variable Prefix "NC,"
}

proc ::NCValuePrefix::Enabler {} {
    return [::OrCADQuickTools::HasSelectedPart]
}

proc ::NCValuePrefix::Run {} {::NCValuePrefix::Update 1}

proc ::NCValuePrefix::Remove {} {::NCValuePrefix::Update 0}

proc ::NCValuePrefix::Update {pAdd} {
    variable Prefix
    if {[catch {GetSelectedObjects} lSelectedObjects]} {
        puts "NC prefix: cannot read the current selection: $lSelectedObjects"
        return
    }

    set lUpdated 0
    set lUnchanged 0
    set lSkipped 0
    set lFailed 0
    set lPrefixLength [string length $Prefix]
    foreach lObject $lSelectedObjects {
        if {![::OrCADQuickTools::IsPlacedPart $lObject]} {
            incr lSkipped
            continue
        }
        if {[catch {::QuickToolsDbo::String $lObject GetPartValue} lOldValue]} {
            incr lFailed
            continue
        }
        set lPrefixed [string equal -nocase [string range $lOldValue 0 [expr {$lPrefixLength - 1}]] $Prefix]
        if {$lPrefixed == $pAdd} {
            incr lUnchanged
            continue
        }
        if {$pAdd} {
            set lNewValue "$Prefix$lOldValue"
        } else {
            set lNewValue [string range $lOldValue $lPrefixLength end]
        }
        if {[catch {
            ::QuickToolsDbo::WriteStrings $lObject SetPartValue 0 $lNewValue
            if {[::QuickToolsDbo::String $lObject GetPartValue] ne $lNewValue} {error "Value read-back differs."}
        } lError]} {
            incr lFailed
            puts "NC prefix: $lError"
        } else {
            incr lUpdated
        }
    }

    catch {Menu "View::Zoom::Redraw"}
    puts "NC prefix: updated=$lUpdated, already-correct=$lUnchanged, non-parts-skipped=$lSkipped, failed=$lFailed"
    if {$lFailed > 0} {
        catch {tk_messageBox -type ok -icon warning -title "NC Prefix" \
            -message "Updated: $lUpdated\nAlready correct: $lUnchanged\nSkipped: $lSkipped\nCould not update or verify: $lFailed"}
    }
}

# -----------------------------------------------------------------------------
# Correct selected references to the current page range
# -----------------------------------------------------------------------------

namespace eval ::PageReferenceFix {
    variable NumbersPerPage 100
}

proc ::PageReferenceFix::Enabler {} {
    return [::OrCADQuickTools::HasSelectedPart]
}

proc ::PageReferenceFix::SplitReference {pReference pPrefixName pNumberName} {
    upvar 1 $pPrefixName lPrefix
    upvar 1 $pNumberName lNumber

    set lPrefix ""
    set lNumber ""
    if {[regexp {^([^0-9]+)([0-9]+)$} $pReference lWhole lFoundPrefix lFoundNumber]} {
        set lPrefix $lFoundPrefix
        set lNumber [expr {int($lFoundNumber)}]
        return 1
    }
    return 0
}

proc ::PageReferenceFix::GetReference {pPart} {
    if {![catch {::QuickToolsDbo::String $pPart GetEffectivePropStringValue Reference} lValue] &&
        [string trim $lValue] ne ""} {
        return [string trim $lValue]
    }
    if {[catch {::QuickToolsDbo::String $pPart GetReference} lValue]} {return ""}
    return $lValue
}

proc ::PageReferenceFix::GetCurrentPageNumber {pPage pStatus} {
    foreach lTitleBlock [::QuickToolsDbo::Objects $pPage NewTitleBlocksIter NextTitleBlock delete_DboPageTitleBlocksIter] {
        if {![catch {::QuickToolsDbo::String $lTitleBlock GetEffectivePropStringValue "Page Number"} lCandidate] &&
            [string is integer -strict $lCandidate] && $lCandidate > 0} {
            return $lCandidate
        }
    }

    # The title-block property is the sheet number users see and edit.  The
    # DboPage number can instead be a separate database position.
    if {![catch {
        set lPageNumber [$pPage GetPageNumber $pStatus]
        ::QuickToolsDbo::Check $pStatus GetPageNumber
    }]} {
        if {[string is integer -strict $lPageNumber] && $lPageNumber > 0} {
            return $lPageNumber
        }
    }

    if {![catch {::QuickToolsDbo::String $pPage GetName} lPageName]} {
        if {[regexp {([0-9]+)$} $lPageName lWhole lCandidate]} {
            if {$lCandidate > 0} {
                return [expr {int($lCandidate)}]
            }
        }
    }
    return 0
}

proc ::PageReferenceFix::CollectPageReferences {pPage pUsedName pMaxName} {
    upvar 1 $pUsedName lUsed
    upvar 1 $pMaxName lMax

    foreach lPart [::QuickToolsDbo::Objects $pPage NewPartInstsIter NextPartInst delete_DboPagePartInstsIter] {
        if {[::OrCADQuickTools::IsPlacedPart $lPart]} {
            set lReference [::PageReferenceFix::GetReference $lPart]
            if {$lReference eq ""} {error "A component on the current page has no readable reference."}
            if {[::PageReferenceFix::SplitReference $lReference lPrefix lNumber]} {
                set lPrefixKey [string toupper $lPrefix]
                set lUsed($lPrefixKey,$lNumber) 1
                if {![info exists lMax($lPrefixKey)] || $lNumber > $lMax($lPrefixKey)} {
                    set lMax($lPrefixKey) $lNumber
                }
            }
        }
    }
}

proc ::PageReferenceFix::FindNextNumber {pPrefixKey pRangeStart pRangeEnd pUsedName pMaxName} {
    upvar 1 $pUsedName lUsed
    upvar 1 $pMaxName lMax

    set lCandidate $pRangeStart
    if {[info exists lMax($pPrefixKey)] && $lMax($pPrefixKey) >= $pRangeStart && $lMax($pPrefixKey) <= $pRangeEnd} {
        set lCandidate [expr {$lMax($pPrefixKey) + 1}]
    }

    if {$lCandidate <= $pRangeEnd && ![info exists lUsed($pPrefixKey,$lCandidate)]} {
        return $lCandidate
    }

    for {set lCandidate $pRangeStart} {$lCandidate <= $pRangeEnd} {incr lCandidate} {
        if {![info exists lUsed($pPrefixKey,$lCandidate)]} {
            return $lCandidate
        }
    }
    return 0
}

proc ::PageReferenceFix::Run {} {
    variable NumbersPerPage

    if {[catch {set lPage [GetActivePage]} lPageError] || $lPage == "NULL" || $lPage == ""} {
        puts "Page reference fix: no active schematic page."
        return
    }
    if {[catch {set lSelectedObjects [GetSelectedObjects]} lSelectionError]} {
        puts "Page reference fix: cannot read the current selection: $lSelectionError"
        return
    }

    set lStatus [DboState]
    set lReadFailed [catch {::PageReferenceFix::GetCurrentPageNumber $lPage $lStatus} lPageNumber]
    catch {$lStatus -delete}
    if {$lReadFailed || $lPageNumber <= 0} {
        puts "Page reference fix: cannot determine the current page number; no references were changed."
        return
    }

    set lRangeStart [expr {$lPageNumber * $NumbersPerPage + 1}]
    set lRangeEnd [expr {$lPageNumber * $NumbersPerPage + $NumbersPerPage - 1}]
    array set lUsed {}
    array set lMax {}
    if {[catch {::PageReferenceFix::CollectPageReferences $lPage lUsed lMax} lError]} {
        catch {tk_messageBox -type ok -icon error -title "Page Reference Fix" -message "$lError\nNo references were changed."}
        return
    }

    set lUpdated 0
    set lAlreadyCorrect 0
    set lSkipped 0
    set lFailed 0

    foreach lObject $lSelectedObjects {
        if {![::OrCADQuickTools::IsPlacedPart $lObject]} {
            incr lSkipped
            continue
        }

        set lOldReference [::PageReferenceFix::GetReference $lObject]
        if {![::PageReferenceFix::SplitReference $lOldReference lPrefix lOldNumber]} {
            incr lFailed
            continue
        }

        if {$lOldNumber >= $lRangeStart && $lOldNumber <= $lRangeEnd} {
            incr lAlreadyCorrect
            continue
        }

        set lPrefixKey [string toupper $lPrefix]
        set lNewNumber [::PageReferenceFix::FindNextNumber $lPrefixKey $lRangeStart $lRangeEnd lUsed lMax]
        if {$lNewNumber == 0} {
            incr lFailed
            continue
        }

        set lNewReference "${lPrefix}${lNewNumber}"
        set lUsed($lPrefixKey,$lNewNumber) 1
        if {[catch {::PageAutoAnnotate::SetReference $lObject $lNewReference} lOK] || !$lOK} {
            incr lFailed
            continue
        }

        set lMax($lPrefixKey) $lNewNumber
        incr lUpdated
        puts "Page reference fix: $lOldReference -> $lNewReference"
    }

    catch {Menu "View::Zoom::Redraw"}
    puts "Page reference fix: page=$lPageNumber, range=$lRangeStart-$lRangeEnd, updated=$lUpdated, already-correct=$lAlreadyCorrect, skipped=$lSkipped, failed=$lFailed"
    if {$lFailed > 0} {
        catch {tk_messageBox -type ok -icon warning -title "Page Reference Fix" \
            -message "Updated: $lUpdated\nAlready correct: $lAlreadyCorrect\nSkipped: $lSkipped\nCould not update or verify: $lFailed"}
    }
}

# -----------------------------------------------------------------------------
# Synchronize all title blocks in the active design.
# -----------------------------------------------------------------------------

namespace eval ::TitleBlockSync {
    variable ProjectName ""
    variable DialogResult ""
    if {![info exists Busy]} {variable Busy 0}
}

proc ::TitleBlockSync::Enabler {} {
    return 1
}

proc ::TitleBlockSync::GetActiveDesign {} {
    if {![info exists ::DboSession_s_pDboSession]} {
        return "NULL"
    }
    set lSession $::DboSession_s_pDboSession
    catch {DboSession -this $lSession}
    set lDesign "NULL"
    catch {set lDesign [$lSession GetActiveDesign]}
    return $lDesign
}

proc ::TitleBlockSync::GetObjectString {pObject pMethod} {
    if {[catch {::QuickToolsDbo::String $pObject $pMethod} lValue]} {return ""}
    return $lValue
}

proc ::TitleBlockSync::GetCurrentDoc {} {
    set lPage "NULL"
    catch {set lPage [GetActivePage]}
    if {$lPage == "NULL" || $lPage == ""} {
        return ""
    }

    if {![catch {::QuickToolsDbo::Objects $lPage NewTitleBlocksIter NextTitleBlock delete_DboPageTitleBlocksIter} lBlocks] &&
        [llength $lBlocks] && ![catch {::QuickToolsDbo::String [lindex $lBlocks 0] GetEffectivePropStringValue Doc} lDoc]} {
        return $lDoc
    }
    return ""
}

proc ::TitleBlockSync::PromptProjectName {} {
    variable DialogOpen
    if {[info exists DialogOpen] && $DialogOpen} {return ""}
    set DialogOpen 1
    set lCode [catch {PromptDialog} lResult]
    set DialogOpen 0
    if {$lCode} {
        catch {destroy .orcadTitleBlockSync}
        error $lResult
    }
    return $lResult
}

proc ::TitleBlockSync::PromptDialog {} {
    variable ProjectName
    variable DialogResult

    if {[catch {package require Tk} lTkError]} {
        puts "Title block sync: Tk is unavailable: $lTkError"
        return ""
    }

    set ProjectName [::TitleBlockSync::GetCurrentDoc]
    set DialogResult ""
    set lWindow .orcadTitleBlockSync
    catch {destroy $lWindow}
    toplevel $lWindow
    wm title $lWindow "Synchronize Title Blocks"
    wm resizable $lWindow 0 0
    wm protocol $lWindow WM_DELETE_WINDOW {
        set ::TitleBlockSync::DialogResult cancel
    }

    label $lWindow.message -text "Project name (writes to Doc on every page):" -anchor w
    entry $lWindow.project -width 48 -textvariable ::TitleBlockSync::ProjectName
    label $lWindow.note -text "Title will be synchronized to each page's Page Name." -anchor w
    frame $lWindow.buttons
    button $lWindow.buttons.ok -text "OK" -width 10 -default active -command {
        set ::TitleBlockSync::DialogResult ok
    }
    button $lWindow.buttons.cancel -text "Cancel" -width 10 -command {
        set ::TitleBlockSync::DialogResult cancel
    }

    pack $lWindow.message -side top -fill x -padx 14 -pady [list 14 5]
    pack $lWindow.project -side top -fill x -padx 14
    pack $lWindow.note -side top -fill x -padx 14 -pady [list 7 12]
    pack $lWindow.buttons.ok $lWindow.buttons.cancel -side left -padx 5
    pack $lWindow.buttons -side bottom -pady [list 0 12]

    bind $lWindow.project <Return> {
        set ::TitleBlockSync::DialogResult ok
    }
    bind $lWindow <Escape> {
        set ::TitleBlockSync::DialogResult cancel
    }
    bind $lWindow <Destroy> {
        if {%W eq ".orcadTitleBlockSync"} {set ::TitleBlockSync::DialogResult cancel}
    }
    focus $lWindow.project
    $lWindow.project selection range 0 end
    catch {grab set $lWindow}
    tkwait variable ::TitleBlockSync::DialogResult
    catch {grab release $lWindow}

    set lResult $DialogResult
    set lProjectName [string trim $ProjectName]
    catch {destroy $lWindow}
    if {$lResult != "ok"} {
        return ""
    }
    return $lProjectName
}

proc ::TitleBlockSync::WriteProperty {pObject pName pValue} {
    return [expr {![catch {::QuickToolsDbo::WriteStrings $pObject SetEffectivePropStringValue 1 $pName $pValue}]}]
}

proc ::TitleBlockSync::Run {} {
    variable Busy
    if {$Busy} {return}
    set Busy 1
    set lCode [catch {::TitleBlockSync::Execute} lMessage]
    set Busy 0
    if {$lCode} {
        catch {destroy .orcadTitleBlockSync}
        catch {tk_messageBox -type ok -icon error -title "Title Block Sync" -message $lMessage}
    }
}

proc ::TitleBlockSync::Execute {} {
    set lDesign [::TitleBlockSync::GetActiveDesign]
    if {$lDesign == "NULL" || $lDesign == ""} {
        catch {tk_messageBox -type ok -icon warning -title "Title Block Sync" \
            -message "No active design was found."}
        puts "Title block sync: no active design."
        return
    }

    set lProjectName [::TitleBlockSync::PromptProjectName]
    if {$lProjectName == ""} {
        puts "Title block sync: cancelled or empty project name."
        return
    }

    set lConfirmation [tk_messageBox -type okcancel -default cancel -icon question \
        -title "Title Block Sync" \
        -message "Update every title block in the active design?\n\nDoc = $lProjectName\nTitle = each page's Page Name"]
    if {$lConfirmation != "ok"} {
        puts "Title block sync: cancelled."
        return
    }

    set lPageCount 0
    set lPageWithoutTitleBlockCount 0
    set lPlan {}
    foreach lPageRecord [::QuickToolsDbo::SchematicPages $lDesign] {
        set lPage [lindex $lPageRecord 1]
        set lPageName [::QuickToolsDbo::String $lPage GetName]
        if {$lPageName eq ""} {error "A schematic page has no readable name."}
        incr lPageCount
        set lBlocks [::QuickToolsDbo::Objects $lPage NewTitleBlocksIter NextTitleBlock delete_DboPageTitleBlocksIter]
        if {![llength $lBlocks]} {incr lPageWithoutTitleBlockCount}
        foreach lBlock $lBlocks {lappend lPlan [list $lBlock $lPageName]}
    }
    set lTitleBlockCount [llength $lPlan]
    set lUpdatedCount 0
    set lFailedPropertyCount 0
    foreach lItem $lPlan {
        foreach {lBlock lPageName} $lItem break
        set lDocOK [::TitleBlockSync::WriteProperty $lBlock Doc $lProjectName]
        set lTitleOK [::TitleBlockSync::WriteProperty $lBlock Title $lPageName]
        if {$lDocOK && $lTitleOK} {incr lUpdatedCount}
        incr lFailedPropertyCount [expr {!$lDocOK + !$lTitleOK}]
    }
    catch {Menu "View::Zoom::Redraw"}

    if {$lTitleBlockCount == 0} {
        set lIcon warning
        set lMessage "No title blocks were found. No properties were changed."
    } elseif {$lFailedPropertyCount > 0} {
        set lIcon warning
        set lMessage "Synchronization finished with some failures.\n\nPages: $lPageCount\nTitle blocks updated: $lUpdatedCount / $lTitleBlockCount\nFailed property writes: $lFailedPropertyCount\nPages without a title block: $lPageWithoutTitleBlockCount\n\nPlease save the design after checking the result."
    } else {
        set lIcon info
        set lMessage "Synchronization complete.\n\nPages: $lPageCount\nTitle blocks updated: $lUpdatedCount\nPages without a title block: $lPageWithoutTitleBlockCount\n\nPlease save the design after checking the result."
    }
    catch {tk_messageBox -type ok -icon $lIcon -title "Title Block Sync" -message $lMessage}
    puts "Title block sync: pages=$lPageCount, title-blocks=$lTitleBlockCount, updated=$lUpdatedCount, pages-without-title-block=$lPageWithoutTitleBlockCount, failed-properties=$lFailedPropertyCount, Doc=$lProjectName"
}

# -----------------------------------------------------------------------------
# Page-based reference reannotation.
# Each reference prefix has its own 01-99 sequence on each page. Components are
# ordered in horizontal rows, from left to right and then from top to bottom.
# -----------------------------------------------------------------------------

namespace eval ::PageAutoAnnotate {
    variable RowTolerance 25
}

proc ::PageAutoAnnotate::Enabler {} {
    return 1
}

proc ::PageAutoAnnotate::GetPrefix {pReference} {
    if {[regexp {^([^0-9?]+)} [string trim $pReference] lWhole lPrefix]} {
        return [string toupper [string trim $lPrefix]]
    }
    return ""
}

proc ::PageAutoAnnotate::ReferenceForm {reference} {
    if {[regexp {^([^0-9?]+[0-9]+)([A-Za-z]*)$} $reference -> base suffix]} {
        return [list $base $suffix 1]
    }
    if {[regexp {^[^0-9?]+\??$} $reference]} {return [list $reference "" 0]}
    error "Unsupported reference format: $reference"
}

# Capture's physical-view exporter uses the cached package size and section
# designator. Cache/package identity alone cannot distinguish two copies.
proc ::PageAutoAnnotate::PartPackage {part} {
    set placed [DboPartInstToDboPlacedInst $part]
    if {[::QuickToolsDbo::Null $placed]} {error "Placed component is unavailable."}
    set package [::QuickToolsDbo::Read $placed GetPackage]
    if {[::QuickToolsDbo::Null $package]} {error "Cached package is unavailable."}
    set size [::QuickToolsDbo::Read $package GetSize]
    if {![string is integer -strict $size] || $size < 1} {error "Cached package size is unavailable."}
    return [list $placed $package $size]
}

proc ::PageAutoAnnotate::PackageMember {part occurrence {packageInfo {}}} {
    if {$packageInfo eq ""} {set packageInfo [PartPackage $part]}
    foreach {placed package size} $packageInfo break
    if {$size <= 1} {error "The package has no separate units."}
    set unit [string trim [::QuickToolsDbo::String $placed GetDeviceDesignator]]
    if {$unit eq ""} {error "The package unit is unavailable."}
    if {![::QuickToolsDbo::Null $occurrence]} {
        set occurrenceUnit [string trim [::QuickToolsDbo::String $occurrence GetDesignator]]
        if {![string equal -nocase $unit $occurrenceUnit]} {
            error "Instance and occurrence unit designators disagree."
        }
    }
    return [list $package $size [string toupper $unit]]
}

proc ::PageAutoAnnotate::ConfirmGroup {records skipName} {
    upvar 1 $skipName skip
    set skip ""
    set members {}
    set package ""
    array set usedUnits {}
    set groupSize [llength $records]
    foreach record $records {
        set suffixes {}
        foreach original [lrange $record 7 8] {
            if {$original ne ""} {
                lappend suffixes [lindex [ReferenceForm $original] 1]
            }
        }
        set identity {}
        set effective [lindex $record 8]
        if {$effective eq ""} {set effective [lindex $record 7]}
        set part [lindex $record 0]
        if {![lindex [ReferenceForm $effective] 2]} {
            if {[catch {PartPackage $part} packageInfo]} {
                set skip "Package size could not be verified for the unnumbered part: $packageInfo"
                return $records
            }
            if {[lindex $packageInfo 2] > 1} {
                error "A multi-unit component needs a package reference before reannotation."
            }
        }
        if {$groupSize > 1 || [join $suffixes {}] ne ""} {
            set packageInfo [PartPackage $part]
            if {$groupSize == 1 && [lindex $packageInfo 2] == 1} {
                set skip "Single-unit reference with a letter suffix; preserved as entered."
                return $records
            }
            set identity [PackageMember $part [lindex $record 6] $packageInfo]
            foreach {cache size unit} $identity break
            if {$package ne "" && $cache ne $package} {error "The reference is used by different cached packages."}
            if {[info exists usedUnits($unit)]} {error "Unit $unit occurs more than once."}
            foreach suffix $suffixes {
                if {$suffix ne "" && ![string equal -nocase $unit $suffix]} {
                    error "Reference suffix $suffix does not match package unit $unit."
                }
            }
            set package $cache
            set usedUnits($unit) 1
            if {[array size usedUnits] > $size} {error "More units share the reference than the package defines."}
        }
        lappend members [linsert $record end $identity]
    }
    return $members
}

proc ::PageAutoAnnotate::CheckGroupMember {record} {
    set expected [lindex $record 9]
    if {$expected ne "" && [PackageMember [lindex $record 0] [lindex $record 6]] ne $expected} {
        error "Package unit changed on [lindex $record 2] ([lindex $record 7])."
    }
}

proc ::PageAutoAnnotate::ReferenceTarget {base original} {
    return "$base[lindex [ReferenceForm $original] 1]"
}

proc ::PageAutoAnnotate::GetCoordinates {pPart pStatus} {
    set lLocation "NULL"
    if {![catch {set lLocation [$pPart GetLocation $pStatus]}] &&
        $lLocation != "NULL" && $lLocation != ""} {
        if {![catch {
            set lX [DboTclHelper_sGetCPointX $lLocation]
            set lY [DboTclHelper_sGetCPointY $lLocation]
        }]} {
            return [list $lX $lY]
        }
    }

    set lBoundingBox "NULL"
    if {![catch {set lBoundingBox [$pPart GetBoundingBox]}] &&
        $lBoundingBox != "NULL" && $lBoundingBox != ""} {
        if {![catch {
            set lTopLeft [DboTclHelper_sGetCRectTopLeft $lBoundingBox]
            set lX [DboTclHelper_sGetCPointX $lTopLeft]
            set lY [DboTclHelper_sGetCPointY $lTopLeft]
        }]} {
            return [list $lX $lY]
        }
    }
    return [list 0 0]
}

proc ::PageAutoAnnotate::CompareYX {pLeft pRight} {
    set lLeftY [lindex $pLeft 2]
    set lRightY [lindex $pRight 2]
    if {$lLeftY < $lRightY} {
        return -1
    }
    if {$lLeftY > $lRightY} {
        return 1
    }
    set lLeftX [lindex $pLeft 1]
    set lRightX [lindex $pRight 1]
    if {$lLeftX < $lRightX} {
        return -1
    }
    if {$lLeftX > $lRightX} {
        return 1
    }
    return [string compare [lindex $pLeft 0] [lindex $pRight 0]]
}

proc ::PageAutoAnnotate::CompareX {pLeft pRight} {
    set lLeftX [lindex $pLeft 1]
    set lRightX [lindex $pRight 1]
    if {$lLeftX < $lRightX} {
        return -1
    }
    if {$lLeftX > $lRightX} {
        return 1
    }
    set lLeftY [lindex $pLeft 2]
    set lRightY [lindex $pRight 2]
    if {$lLeftY < $lRightY} {
        return -1
    }
    if {$lLeftY > $lRightY} {
        return 1
    }
    return [string compare [lindex $pLeft 0] [lindex $pRight 0]]
}

proc ::PageAutoAnnotate::SortSpatial {pRecords} {
    variable RowTolerance
    set lByY [lsort -command ::PageAutoAnnotate::CompareYX $pRecords]
    set lResult {}
    set lRow {}
    set lRowAnchorY 0

    foreach lRecord $lByY {
        set lY [lindex $lRecord 2]
        if {[llength $lRow] == 0} {
            set lRow [list $lRecord]
            set lRowAnchorY $lY
        } elseif {[expr {abs($lY - $lRowAnchorY)}] <= $RowTolerance} {
            lappend lRow $lRecord
        } else {
            set lResult [concat $lResult [lsort -command ::PageAutoAnnotate::CompareX $lRow]]
            set lRow [list $lRecord]
            set lRowAnchorY $lY
        }
    }
    if {[llength $lRow] > 0} {
        set lResult [concat $lResult [lsort -command ::PageAutoAnnotate::CompareX $lRow]]
    }
    return $lResult
}

proc ::PageAutoAnnotate::CompareBucketKeys {pLeft pRight} {
    set lLeftPage [lindex $pLeft 0]
    set lRightPage [lindex $pRight 0]
    if {$lLeftPage < $lRightPage} {
        return -1
    }
    if {$lLeftPage > $lRightPage} {
        return 1
    }
    return [string compare [lindex $pLeft 1] [lindex $pRight 1]]
}

proc ::PageAutoAnnotate::ReadReferenceProperty {pObject} {
    if {[catch {::QuickToolsDbo::String $pObject GetEffectivePropStringValue Reference} lText]} {
        return [list 0 ""]
    }
    return [list 1 [string trim $lText]]
}

proc ::PageAutoAnnotate::CollectPartOccurrences {pDesign pStatus pOccurrencesName} {
    upvar 1 $pOccurrencesName lOccurrences
    array set lOccurrences {}
    if {[catch {set lReused [$pDesign DesignHasReusedSchematics]}] || $lReused} {
        return "A reused schematic was found; occurrence references cannot be changed safely."
    }
    # Capture may still display occurrence-level Reference values even when
    # DesignHasOccurrenceProperties reports false.  Build the root occurrence
    # and enumerate it unconditionally so mixed instance/occurrence designs do
    # not update only a subset of the visible references.
    if {[catch {set lRootExists [$pDesign IsRootOccurrenceExisting]}]} {
        return "The root design occurrence could not be checked."
    }
    if {!$lRootExists} {
        set lRoot "NULL"
        if {[catch {set lRoot [$pDesign GetRootOccurrence $pStatus]}] ||
            $lRoot == "NULL" || $lRoot == ""} {
            return "The root design occurrence could not be created."
        }
    }
    if {[catch {DboDesignOccurrencesIter quickToolsOccurrencesIter $pDesign}]} {
        return "The design occurrences could not be read."
    }
    set lError ""
    if {[catch {
        array set lSeen {}
        while {1} {
            set lOccurrence [::QuickToolsDbo::Next quickToolsOccurrencesIter NextOccurrence]
            if {[::QuickToolsDbo::Null $lOccurrence]} {break}
            if {[info exists lSeen($lOccurrence)]} {error "The occurrence iterator repeated an object."}
            set lSeen($lOccurrence) 1
            set lPart [$lOccurrence GetPartInst $pStatus]
            if {![::QuickToolsDbo::Null $lPart]} {
                ::QuickToolsDbo::Check $pStatus GetPartInst
                if {[::OrCADQuickTools::IsPlacedPart $lPart]} {
                    if {[info exists lOccurrences($lPart)]} {
                        error "A component has multiple occurrences."
                    }
                    set lOccurrences($lPart) $lOccurrence
                }
            }
        }
    } lReadError]} {
        set lError "The design occurrences could not be read: $lReadError"
    }
    catch {rename quickToolsOccurrencesIter {}}
    return $lError
}

proc ::PageAutoAnnotate::SetReference {pPart pReference {pExpected ""}} {
    if {$pExpected eq ""} {set pExpected $pReference}
    if {[catch {::QuickToolsDbo::WriteStrings $pPart SetReference 1 $pReference}]} {return 0}
    set lVisible [::PageAutoAnnotate::ReadReferenceProperty $pPart]
    if {![lindex $lVisible 0] || ![string equal -nocase [lindex $lVisible 1] $pExpected]} {
        if {![::TitleBlockSync::WriteProperty $pPart "Reference" $pExpected]} {
            puts "Reference property write failed: $pExpected"
            return 0
        }
        set lVisible [::PageAutoAnnotate::ReadReferenceProperty $pPart]
    }
    if {![lindex $lVisible 0] || ![string equal -nocase [lindex $lVisible 1] $pExpected]} {
        puts "Reference property read-back failed: target=$pExpected, actual=[lindex $lVisible 1]"
        return 0
    }
    return 1
}

proc ::PageAutoAnnotate::ApplyReferenceToGroup {pRecords pReference} {
    foreach lRecord $pRecords {
        set lPart [lindex $lRecord 0]
        if {![SetReference $lPart $pReference [ReferenceTarget $pReference [lindex $lRecord 7]]]} {
            return 0
        }
        set lOccurrence [lindex $lRecord 6]
        if {$lOccurrence != "" && $lOccurrence != "NULL" &&
            ![SetReference $lOccurrence $pReference [ReferenceTarget $pReference [lindex $lRecord 8]]]} {
            return 0
        }
        CheckGroupMember $lRecord
    }
    return 1
}

proc ::PageAutoAnnotate::ReadTitleProperty {pTitleBlock pName} {
    if {[catch {::QuickToolsDbo::String $pTitleBlock GetEffectivePropStringValue $pName} lText]} {
        return [list 0 ""]
    }
    return [list 1 [string trim $lText]]
}

proc ::PageAutoAnnotate::ReadPageTitleBlocks {pPage} {
    set lRecords {}
    foreach lTitleBlock [::QuickToolsDbo::Objects $pPage NewTitleBlocksIter NextTitleBlock delete_DboPageTitleBlocksIter] {
        set lOldVisibleNumber [::PageAutoAnnotate::ReadTitleProperty $lTitleBlock "Page Number"]
        set lOldVisibleCount [::PageAutoAnnotate::ReadTitleProperty $lTitleBlock "Page Count"]
        lappend lRecords [list $lTitleBlock $lOldVisibleNumber $lOldVisibleCount]
    }
    return $lRecords
}

proc ::PageAutoAnnotate::ApplyPageNumbers {pPagePlan pPageCount pJournalName} {
    upvar 1 $pJournalName lJournal
    foreach lPageRecord $pPagePlan {
        set lNumber [lindex $lPageRecord 3]
        set lPageName [lindex $lPageRecord 2]
        foreach lTitleRecord [lindex $lPageRecord 5] {
            set lTitleBlock [lindex $lTitleRecord 0]
            foreach {lProperty lValue lOldIndex} [list "Page Number" $lNumber 1 "Page Count" $pPageCount 2] {
                lappend lJournal [list $lTitleBlock $lProperty [lindex [lindex $lTitleRecord $lOldIndex] 1]]
                if {![::TitleBlockSync::WriteProperty $lTitleBlock $lProperty $lValue]} {
                    error "Could not update $lProperty on $lPageName."
                }
            }
            set lVisibleNumber [::PageAutoAnnotate::ReadTitleProperty $lTitleBlock "Page Number"]
            set lVisibleCount [::PageAutoAnnotate::ReadTitleProperty $lTitleBlock "Page Count"]
            if {![lindex $lVisibleNumber 0] || [lindex $lVisibleNumber 1] != $lNumber ||
                ![lindex $lVisibleCount 0] || [lindex $lVisibleCount 1] != $pPageCount} {
                error "Title-block Page Number / Page Count did not change on $lPageName (read back: [lindex $lVisibleNumber 1] / [lindex $lVisibleCount 1])."
            }
            catch {puts "Page numbering verified: $lPageName -> $lNumber / $pPageCount"}
        }
    }
}

proc ::PageAutoAnnotate::RestorePageNumbers {pJournal} {
    set lFailures 0
    for {set i [expr {[llength $pJournal] - 1}]} {$i >= 0} {incr i -1} {
        foreach {lTitleBlock lProperty lOriginal} [lindex $pJournal $i] break
        if {[catch {
            if {![::TitleBlockSync::WriteProperty $lTitleBlock $lProperty $lOriginal]} {error "Write failed."}
            set lRestored [::PageAutoAnnotate::ReadTitleProperty $lTitleBlock $lProperty]
            if {![lindex $lRestored 0] || ![string equal [lindex $lRestored 1] $lOriginal]} {
                error "Read-back failed."
            }
        }]} {incr lFailures}
    }
    return $lFailures
}

# NewPagesIter is a database iterator, not the Project Manager's visible order.
# Compare names naturally: P2 < P10, 2 < 10, and Alpha < Beta.
# Refuse empty or naturally equivalent names rather than guessing their order.
proc ::PageAutoAnnotate::CompareNaturalPageNames {pLeft pRight} {
    set lLeft [string trim $pLeft]
    set lRight [string trim $pRight]
    while {$lLeft != "" && $lRight != ""} {
        set lLeftNumber [regexp {^([0-9]+)} $lLeft lMatch lLeftChunk]
        if {!$lLeftNumber} {
            regexp {^([^0-9]+)} $lLeft lMatch lLeftChunk
        }
        set lRightNumber [regexp {^([0-9]+)} $lRight lMatch lRightChunk]
        if {!$lRightNumber} {
            regexp {^([^0-9]+)} $lRight lMatch lRightChunk
        }

        if {$lLeftNumber != $lRightNumber} {
            if {$lLeftNumber} {return -1}
            return 1
        }
        if {$lLeftNumber} {
            regsub {^0+} $lLeftChunk "" lLeftDigits
            regsub {^0+} $lRightChunk "" lRightDigits
            if {$lLeftDigits == ""} {set lLeftDigits "0"}
            if {$lRightDigits == ""} {set lRightDigits "0"}
            set lComparison [expr {[string length $lLeftDigits] - [string length $lRightDigits]}]
            if {$lComparison == 0} {
                set lComparison [string compare $lLeftDigits $lRightDigits]
            }
        } else {
            set lComparison [string compare [string toupper $lLeftChunk] [string toupper $lRightChunk]]
        }
        if {$lComparison < 0} {return -1}
        if {$lComparison > 0} {return 1}
        set lLeft [string range $lLeft [string length $lLeftChunk] end]
        set lRight [string range $lRight [string length $lRightChunk] end]
    }
    if {$lLeft == "" && $lRight == ""} {return 0}
    if {$lLeft == ""} {return -1}
    return 1
}

proc ::PageAutoAnnotate::ComparePageRecords {pLeft pRight} {
    return [::PageAutoAnnotate::CompareNaturalPageNames [lindex $pLeft 2] [lindex $pRight 2]]
}

proc ::PageAutoAnnotate::ResolveNamedPageOrder {pPagePlan pInvalidPagesName} {
    upvar 1 $pInvalidPagesName lInvalidPages

    foreach lPageRecord $pPagePlan {
        set lPageName [string trim [lindex $lPageRecord 2]]
        if {$lPageName == ""} {
            lappend lInvalidPages "(empty page name)"
        }
    }
    if {[llength $lInvalidPages] > 0} {
        return {}
    }
    set lSortable [lsort -command ::PageAutoAnnotate::ComparePageRecords $pPagePlan]
    set lPreviousName ""
    foreach lPageRecord $lSortable {
        set lPageName [lindex $lPageRecord 2]
        if {$lPreviousName != "" &&
            [::PageAutoAnnotate::CompareNaturalPageNames $lPreviousName $lPageName] == 0} {
            lappend lInvalidPages "$lPageName (same sort position as $lPreviousName)"
        }
        set lPreviousName $lPageName
    }
    if {[llength $lInvalidPages] > 0} {return {}}

    set lOrderedPlan {}
    set lNewNumber 0
    foreach lPageRecord $lSortable {
        incr lNewNumber
        lappend lOrderedPlan [lreplace $lPageRecord 3 3 $lNewNumber]
    }
    return $lOrderedPlan
}

proc ::PageAutoAnnotate::CollectDesign {pDesign pStatus pMode pRecordsName pPrefixName pOldReferenceName pOrderName pExistingName pPagesName pInvalidPagesName pSkippedGroupsName pStatsName} {
    upvar 1 $pRecordsName lGroupRecords
    upvar 1 $pPrefixName lGroupPrefix
    upvar 1 $pOldReferenceName lGroupOldReference
    upvar 1 $pOrderName lGroupOrder
    upvar 1 $pExistingName lExistingOwners
    upvar 1 $pPagesName lPageOccurrences
    upvar 1 $pInvalidPagesName lInvalidPages
    upvar 1 $pSkippedGroupsName lSkippedGroups
    upvar 1 $pStatsName lStats

    array set lGroupRecords {}
    array set lGroupPrefix {}
    array set lGroupOldReference {}
    array set lExistingOwners {}
    array set lPageOccurrences {}
    array set lSkippedGroups {}
    set lGroupOrder {}
    set lInvalidPages {}
    set lPageCount 0
    set lPartCount 0
    set lSkippedCount 0

    array set lPartOccurrences {}
    set lOccurrenceError [::PageAutoAnnotate::CollectPartOccurrences $pDesign $pStatus lPartOccurrences]
    if {$lOccurrenceError != ""} {
        lappend lInvalidPages $lOccurrenceError
        set lStats [list 0 0 0]
        return 0
    }
    set lOccurrenceMode [expr {[array size lPartOccurrences] > 0}]

    foreach lPageRecord [::QuickToolsDbo::SchematicPages $pDesign] {
        set lPage [lindex $lPageRecord 1]
        incr lPageCount
        set lPageName [::TitleBlockSync::GetObjectString $lPage GetName]
        if {$lPageName eq ""} {error "A schematic page has no readable name."}
        set lPageNumber [::PageReferenceFix::GetCurrentPageNumber $lPage $pStatus]
        if {$lPageNumber <= 0} {
            lappend lInvalidPages "$lPageName (Page Number unavailable)"
        } else {
            lappend lPageOccurrences($lPageNumber) $lPageName
        }
        if {[catch {::QuickToolsDbo::Objects $lPage NewPartInstsIter NextPartInst delete_DboPagePartInstsIter} lParts]} {
            error "$lPageName: $lParts"
        }
        foreach lPart $lParts {
            if {![::OrCADQuickTools::IsPlacedPart $lPart]} {
                incr lSkippedCount
                continue
            }
            set lPartReference [::PageReferenceFix::GetReference $lPart]
            if {$lPartReference eq ""} {error "$lPageName (component reference unavailable)"}
            set lOccurrence ""
            set lOccurrenceReference ""
            if {[info exists lPartOccurrences($lPart)]} {
                set lOccurrence $lPartOccurrences($lPart)
                set lOccurrenceValue [::PageAutoAnnotate::ReadReferenceProperty $lOccurrence]
                if {![lindex $lOccurrenceValue 0] || [lindex $lOccurrenceValue 1] eq ""} {
                    error "$lPageName (occurrence reference unavailable for $lPartReference)"
                }
                set lOccurrenceReference [lindex $lOccurrenceValue 1]
            } elseif {$lOccurrenceMode} {
                error "$lPageName (component occurrence missing for $lPartReference)"
            }
            set lOldReference $lPartReference
            if {$lOccurrenceReference ne ""} {set lOldReference $lOccurrenceReference}
            if {[catch {
                foreach {lBase lSuffix lAssigned} [ReferenceForm $lOldReference] break
                set lInstanceBase [lindex [ReferenceForm $lPartReference] 0]
            } lError]} {error "$lPageName: $lError"}
            set lPrefix [GetPrefix $lBase]
            set lReferenceKey [list $lPrefix [string toupper $lBase]]
            set lGroupKey $lReferenceKey
            if {!$lAssigned} {lappend lGroupKey $lPart}
            if {![info exists lGroupRecords($lGroupKey)]} {
                set lGroupPrefix($lGroupKey) $lPrefix
                set lGroupOldReference($lGroupKey) $lBase
                lappend lGroupOrder $lGroupKey
            }
            foreach {lX lY} [GetCoordinates $lPart $pStatus] break
            lappend lGroupRecords($lGroupKey) [list $lPart $lPageNumber $lPageName $lX $lY $lPage $lOccurrence $lPartReference $lOccurrenceReference]
            lappend lExistingOwners($lReferenceKey) $lGroupKey
            set lInstanceKey [list [GetPrefix $lInstanceBase] [string toupper $lInstanceBase]]
            if {$lInstanceKey ne $lReferenceKey} {lappend lExistingOwners($lInstanceKey) $lGroupKey}
            incr lPartCount
        }
    }
    foreach key $lGroupOrder {
        if {[catch {ConfirmGroup $lGroupRecords($key) skipReason} members]} {
            set pageNames {}
            foreach record $lGroupRecords($key) {lappend pageNames [lindex $record 2]}
            set pages [join [lsort -unique $pageNames] { / }]
            lappend lInvalidPages "$lGroupOldReference($key) on $pages: $members"
        } elseif {$skipReason ne ""} {
            set lSkippedGroups($key) $skipReason
        } else {
            set lGroupRecords($key) $members
        }
    }
    set lStats [list $lPageCount $lPartCount $lSkippedCount]
    if {$pMode == "all" && $lPageCount == 0} {
        return 0
    }
    foreach lPageNumber [array names lPageOccurrences] {
        if {[llength $lPageOccurrences($lPageNumber)] > 1} {
            lappend lInvalidPages "Page Number $lPageNumber is used by [join $lPageOccurrences($lPageNumber) { / }]"
        }
    }
    return 1
}

proc ::PageAutoAnnotate::RestoreOriginalReferences {pPlan pRecordsName} {
    upvar 1 $pRecordsName lGroupRecords
    set lFailures 0
    foreach lItem $pPlan {
        set lGroupKey [lindex $lItem 0]
        foreach lRecord $lGroupRecords($lGroupKey) {
            set lOld [lindex $lRecord 7]
            if {[catch {SetReference [lindex $lRecord 0] [lindex [ReferenceForm $lOld] 0] $lOld} lOK] || !$lOK} {
                incr lFailures
            }
            set lOccurrence [lindex $lRecord 6]
            set lOld [lindex $lRecord 8]
            if {$lOccurrence != "" && $lOccurrence != "NULL" &&
                ([catch {SetReference $lOccurrence [lindex [ReferenceForm $lOld] 0] $lOld} lOK] || !$lOK)} {
                incr lFailures
            }
            if {[catch {CheckGroupMember $lRecord}]} {incr lFailures}
        }
    }
    return $lFailures
}

proc ::PageAutoAnnotate::Run {pMode} {
    variable Busy
    if {[info exists Busy] && $Busy} {return}
    set Busy 1
    set title "Reference Reannotation"
    set code [catch {
        if {$pMode eq "pages"} {
            set title "Page Number Reset"
            ResetPageNumbers
        } else {
            Reannotate $pMode
        }
    } message]
    set Busy 0
    if {$code} {catch {tk_messageBox -type ok -icon error -title $title -message $message}}
}

proc ::PageAutoAnnotate::Reannotate {pMode} {
    set lDesign [::TitleBlockSync::GetActiveDesign]
    if {$lDesign == "NULL" || $lDesign == ""} {
        catch {tk_messageBox -type ok -icon warning -title "Reference Reannotation" \
            -message "No active design was found."}
        puts "Reference reannotation: no active design."
        return
    }

    set lCurrentPage "NULL"
    catch {set lCurrentPage [GetActivePage]}
    if {$pMode == "current" && ($lCurrentPage == "NULL" || $lCurrentPage == "")} {
        catch {tk_messageBox -type ok -icon warning -title "Reference Reannotation" \
            -message "No active schematic page was found."}
        return
    }

    set lStatus [DboState]
    set lCurrentPageName ""
    set lCurrentPageNumber 0
    if {$pMode == "current"} {
        set lCurrentPageName [::TitleBlockSync::GetObjectString $lCurrentPage "GetName"]
        if {[catch {::PageReferenceFix::GetCurrentPageNumber $lCurrentPage $lStatus} lCurrentPageNumber] ||
            $lCurrentPageNumber <= 0} {
            catch {$lStatus -delete}
            catch {tk_messageBox -type ok -icon error -title "Reference Reannotation" \
                -message "The current page number could not be determined."}
            return
        }
    }

    array set lGroupRecords {}
    array set lGroupPrefix {}
    array set lGroupOldReference {}
    array set lExistingOwners {}
    array set lPageOccurrences {}
    array set lSkippedGroups {}
    set lGroupOrder {}
    set lInvalidPages {}
    set lStats {}
    set lReadCode [catch {::PageAutoAnnotate::CollectDesign $lDesign $lStatus $pMode \
        lGroupRecords lGroupPrefix lGroupOldReference lGroupOrder \
        lExistingOwners lPageOccurrences lInvalidPages lSkippedGroups lStats} lReadResult]
    if {$lReadCode || !$lReadResult} {
        catch {$lStatus -delete}
        set lDetail [join $lInvalidPages {, }]
        if {$lReadCode} {set lDetail $lReadResult}
        if {$lDetail == ""} {set lDetail "The schematic pages could not be read."}
        catch {tk_messageBox -type ok -icon error -title "Reference Reannotation" \
            -message "$lDetail\n\nNo changes were made."}
        return
    }

    if {[llength $lInvalidPages] > 0} {
        catch {$lStatus -delete}
        catch {tk_messageBox -type ok -icon error -title "Reference Reannotation" \
            -message "Reannotation cannot continue safely. Page names, title-block properties, and component references must be readable and unambiguous. No changes were made.\n\nDetails: [join $lInvalidPages {, }]"}
        return
    }

    array set lBuckets {}
    array set lSelectedGroups {}
    array set lAnchorPageName {}
    set lSkippedInScope {}
    foreach lGroupKey $lGroupOrder {
        set lAnchor ""
        foreach lRecord $lGroupRecords($lGroupKey) {
            set lPageNumber [lindex $lRecord 1]
            set lPageName [lindex $lRecord 2]
            set lX [lindex $lRecord 3]
            set lY [lindex $lRecord 4]
            if {$pMode == "current" &&
                !($lPageNumber == $lCurrentPageNumber && [string equal $lPageName $lCurrentPageName])} {
                continue
            }
            if {$lPageNumber <= 0} {
                continue
            }
            if {$lAnchor == "" ||
                $lPageNumber < [lindex $lAnchor 0] ||
                ($lPageNumber == [lindex $lAnchor 0] && $lY < [lindex $lAnchor 3]) ||
                ($lPageNumber == [lindex $lAnchor 0] && $lY == [lindex $lAnchor 3] && $lX < [lindex $lAnchor 2])} {
                set lAnchor [list $lPageNumber $lPageName $lX $lY]
            }
        }
        if {$lAnchor != ""} {
            if {[info exists lSkippedGroups($lGroupKey)]} {
                set lRecord [lindex $lGroupRecords($lGroupKey) 0]
                set lRef [lindex $lRecord 8]
                if {$lRef eq ""} {set lRef [lindex $lRecord 7]}
                lappend lSkippedInScope "[lindex $lAnchor 1] / $lRef: $lSkippedGroups($lGroupKey)"
                continue
            }
            set lSelectedGroups($lGroupKey) 1
            set lPageNumber [lindex $lAnchor 0]
            set lPageName [lindex $lAnchor 1]
            set lPrefix $lGroupPrefix($lGroupKey)
            set lBucketKey [list $lPageNumber $lPrefix]
            lappend lBuckets($lBucketKey) [list $lGroupKey [lindex $lAnchor 2] [lindex $lAnchor 3]]
            set lAnchorPageName($lGroupKey) $lPageName
        }
    }

    set lSkipSummary ""
    if {[llength $lSkippedInScope]} {
        foreach lSkipped $lSkippedInScope {puts "Reference reannotation skipped: $lSkipped"}
        set lSkipSummary "\nSkipped references: [llength $lSkippedInScope]\n[join [lrange $lSkippedInScope 0 4] \n]"
        if {[llength $lSkippedInScope] > 5} {append lSkipSummary "\nSee Command Window for the full list."}
    }
    if {[array size lSelectedGroups] == 0} {
        catch {$lStatus -delete}
        catch {tk_messageBox -type ok -icon warning -title "Reference Reannotation" \
            -message "No references were changed in the selected scope.$lSkipSummary"}
        return
    }

    # Reserve the base numbers of preserved references, including their
    # instance/occurrence aliases, until all planned writes have finished.
    array set lReservedTargets {}
    if {[array size lSkippedGroups]} {
        foreach lExisting [array names lExistingOwners] {
            foreach lOwner $lExistingOwners($lExisting) {
                if {[info exists lSkippedGroups($lOwner)]} {
                    set lReservedTargets($lExisting) 1
                    break
                }
            }
        }
    }
    set lPlan {}
    set lPlanError ""
    foreach lBucketKey [lsort -command ::PageAutoAnnotate::CompareBucketKeys [array names lBuckets]] {
        set lPageNumber [lindex $lBucketKey 0]
        set lPrefix [lindex $lBucketKey 1]
        set lSorted [::PageAutoAnnotate::SortSpatial $lBuckets($lBucketKey)]
        set lMaxPerPrefix [expr {$::PageReferenceFix::NumbersPerPage - 1}]
        if {[llength $lSorted] > $lMaxPerPrefix} {
            set lPlanError "Page $lPageNumber has more than $lMaxPerPrefix $lPrefix references."
            break
        }
        set lSequence 1
        foreach lSpatialRecord $lSorted {
            set lGroupKey [lindex $lSpatialRecord 0]
            while {$lSequence <= $lMaxPerPrefix} {
                set lNewReference "${lPrefix}[expr {$lPageNumber * $::PageReferenceFix::NumbersPerPage + $lSequence}]"
                if {![info exists lReservedTargets([list $lPrefix $lNewReference])]} {break}
                incr lSequence
            }
            if {$lSequence > $lMaxPerPrefix} {
                set lPlanError "Page $lPageNumber has insufficient free $lPrefix references after accounting for preserved references."
                break
            }
            lappend lPlan [list $lGroupKey $lGroupOldReference($lGroupKey) $lNewReference $lPrefix $lPageNumber $lAnchorPageName($lGroupKey)]
            incr lSequence
        }
        if {$lPlanError ne ""} {break}
    }
    if {$lPlanError != ""} {
        catch {$lStatus -delete}
        catch {tk_messageBox -type ok -icon error -title "Reference Reannotation" \
            -message "$lPlanError\nNo references were changed."}
        return
    }

    array set lPlannedTargets {}
    foreach lItem $lPlan {
        set lTargetKey [list [lindex $lItem 3] [string toupper [lindex $lItem 2]]]
        if {[info exists lPlannedTargets($lTargetKey)]} {
            set lPlanError "The target reference [lindex $lItem 2] was generated more than once."
            break
        }
        set lPlannedTargets($lTargetKey) [lindex $lItem 0]
        if {[info exists lExistingOwners($lTargetKey)]} {
            foreach lOwner $lExistingOwners($lTargetKey) {
                if {![info exists lSelectedGroups($lOwner)]} {
                    set lPlanError "Target reference [lindex $lItem 2] is already used outside the selected scope."
                    break
                }
            }
        }
        if {$lPlanError != ""} {
            break
        }
    }
    if {$lPlanError != ""} {
        catch {$lStatus -delete}
        catch {tk_messageBox -type ok -icon error -title "Reference Reannotation" \
            -message "$lPlanError\nNo references were changed."}
        return
    }

    set lObjectCount 0
    foreach lItem $lPlan {
        incr lObjectCount [llength $lGroupRecords([lindex $lItem 0])]
    }
    if {$pMode == "all"} {
        set lScopeText "ALL schematic pages"
        set lWarningText "This will reset all component references in the active design using each title block's existing Page Number. Page Number and Page Count will not be changed."
    } else {
        set lScopeText "current page $lCurrentPageNumber ($lCurrentPageName)"
        set lWarningText "This will reset all component references on the current page. Linked multi-part units retain one shared reference."
    }
    if {$pMode == "all"} {
        set lScopePageCount [lindex $lStats 0]
    } else {
        set lScopePageCount 1
    }
    set lSkippedCount [lindex $lStats 2]
    set lConfirmation "cancel"
    catch {set lConfirmation [tk_messageBox -type okcancel -default cancel -icon warning \
        -title "Reference Reannotation" \
        -message "$lWarningText\n\nScope: $lScopeText\nPages: $lScopePageCount\nReferences to update: [llength $lPlan]\nPlaced units: $lObjectCount\nNon-annotatable objects in design: $lSkippedCount$lSkipSummary\nComponent order: left to right, then top to bottom\n\nPlease make sure the design is backed up before continuing."]}
    if {$lConfirmation != "ok"} {
        catch {$lStatus -delete}
        puts "Reference reannotation: cancelled."
        return
    }

    array set lTemporaryReferences {}
    set lTemporaryNumber 900000000
    foreach lItem $lPlan {
        set lGroupKey [lindex $lItem 0]
        set lPrefix [lindex $lItem 3]
        while {1} {
            set lTemporaryReference "${lPrefix}${lTemporaryNumber}"
            set lTemporaryKey [list $lPrefix [string toupper $lTemporaryReference]]
            incr lTemporaryNumber
            if {![info exists lExistingOwners($lTemporaryKey)] &&
                ![info exists lPlannedTargets($lTemporaryKey)]} {
                break
            }
        }
        set lTemporaryReferences($lGroupKey) $lTemporaryReference
    }

    catch {$lStatus -delete}
    set lAttempted {}
    set lFinalPhase 0
    if {[catch {
        foreach lItem $lPlan {
            set lGroupKey [lindex $lItem 0]
            lappend lAttempted $lItem
            if {![::PageAutoAnnotate::ApplyReferenceToGroup $lGroupRecords($lGroupKey) $lTemporaryReferences($lGroupKey)]} {
                error "Failed while assigning temporary references."
            }
        }
        set lFinalPhase 1
        foreach lItem $lPlan {
            set lGroupKey [lindex $lItem 0]
            set lNewReference [lindex $lItem 2]
            if {![::PageAutoAnnotate::ApplyReferenceToGroup $lGroupRecords($lGroupKey) $lNewReference]} {
                error "Failed while assigning $lNewReference."
            }
        }
        foreach lItem $lPlan {
            set lTarget [lindex $lItem 2]
            foreach lRecord $lGroupRecords([lindex $lItem 0]) {
                set lPartValue [::PageAutoAnnotate::ReadReferenceProperty [lindex $lRecord 0]]
                set lExpected [ReferenceTarget $lTarget [lindex $lRecord 7]]
                if {![lindex $lPartValue 0] || ![string equal -nocase [lindex $lPartValue 1] $lExpected]} {
                    error "Reference read-back failed on [lindex $lRecord 2]: expected $lExpected, instance shows [lindex $lPartValue 1]."
                }
                set lOccurrence [lindex $lRecord 6]
                if {$lOccurrence != "" && $lOccurrence != "NULL"} {
                    set lVisibleValue [::PageAutoAnnotate::ReadReferenceProperty $lOccurrence]
                    set lExpected [ReferenceTarget $lTarget [lindex $lRecord 8]]
                    if {![lindex $lVisibleValue 0] || ![string equal -nocase [lindex $lVisibleValue 1] $lExpected]} {
                        error "Reference read-back failed on [lindex $lRecord 2]: expected $lExpected, occurrence shows [lindex $lVisibleValue 1]."
                    }
                }
                CheckGroupMember $lRecord
            }
        }
    } lOperationError]} {
        # Free original refdes before restoration if final writes had begun.
        # Continue the restore even when one temporary write fails.
        if {$lFinalPhase} {
            foreach lItem $lAttempted {
                set lGroupKey [lindex $lItem 0]
                catch {::PageAutoAnnotate::ApplyReferenceToGroup $lGroupRecords($lGroupKey) $lTemporaryReferences($lGroupKey)}
            }
        }
        set lRestoreFailures [::PageAutoAnnotate::RestoreOriginalReferences $lAttempted lGroupRecords]
        catch {Menu "View::Zoom::Redraw"}
        catch {tk_messageBox -type ok -icon error -title "Reference Reannotation" \
            -message "$lOperationError\n\nThe script attempted to restore the original references.\nRestore failures: $lRestoreFailures"}
        puts "Reference reannotation failed: $lOperationError; restore-failures=$lRestoreFailures"
        return
    }

    catch {Menu "View::Zoom::Redraw"}
    catch {tk_messageBox -type ok -icon info -title "Reference Reannotation" \
        -message "Reannotation complete.\n\nScope: $lScopeText\nReferences updated: [llength $lPlan]\nPlaced units: $lObjectCount\nNon-annotatable objects in design: $lSkippedCount$lSkipSummary\n\nPlease inspect and save the design."}
    puts "Reference reannotation complete: mode=$pMode, pages=$lScopePageCount, references=[llength $lPlan], placed-units=$lObjectCount"
}

proc ::PageAutoAnnotate::RunCurrent {} {
    ::PageAutoAnnotate::Run current
}

proc ::PageAutoAnnotate::RunAll {} {
    ::PageAutoAnnotate::Run all
}

proc ::PageAutoAnnotate::RunPageNumbers {} {
    ::PageAutoAnnotate::Run pages
}

proc ::PageAutoAnnotate::ResetPageNumbers {} {
    set lDesign [::TitleBlockSync::GetActiveDesign]
    if {$lDesign == "NULL" || $lDesign == ""} {
        catch {tk_messageBox -type ok -icon warning -title "Page Number Reset" \
            -message "No active design was found."}
        return
    }

    set lPagePlan {}
    set lInvalidPages {}
    if {[catch {
        foreach lPageRecord [::QuickToolsDbo::SchematicPages $lDesign] {
            foreach {lSchematic lPage} $lPageRecord break
            set lPageName [::TitleBlockSync::GetObjectString $lPage GetName]
            if {[catch {::PageAutoAnnotate::ReadPageTitleBlocks $lPage} lTitleRecords]} {
                error "$lPageName: $lTitleRecords"
            }
            if {![llength $lTitleRecords]} {
                lappend lInvalidPages "$lPageName (no title block)"
            }
            foreach lTitleRecord $lTitleRecords {
                if {![lindex [lindex $lTitleRecord 1] 0] || ![lindex [lindex $lTitleRecord 2] 0]} {
                    lappend lInvalidPages "$lPageName (visible title-block properties unavailable)"
                    break
                }
            }
            lappend lPagePlan [list $lSchematic $lPage $lPageName 0 0 $lTitleRecords]
        }
    } lReadError]} {lappend lInvalidPages $lReadError}

    if {[llength $lInvalidPages] == 0} {
        set lPagePlan [::PageAutoAnnotate::ResolveNamedPageOrder \
            $lPagePlan lInvalidPages]
    }
    if {[llength $lPagePlan] == 0 || [llength $lInvalidPages] > 0} {
        set lDetail [join $lInvalidPages {, }]
        if {$lDetail == ""} {set lDetail "No schematic pages were found."}
        catch {tk_messageBox -type ok -icon error -title "Page Number Reset" \
            -message "Page numbers cannot be reset safely. No changes were made.\n\nDetails: $lDetail"}
        return
    }

    set lPreview ""
    set lIndex 0
    foreach lPageRecord $lPagePlan {
        incr lIndex
        puts "Page number reset order: $lIndex -> [lindex $lPageRecord 2]"
        if {$lIndex <= 8} {append lPreview "\n$lIndex. [lindex $lPageRecord 2]"}
    }
    if {$lIndex > 8} {
        append lPreview "\n... [expr {$lIndex - 8}] more pages (see Command Window)"
    }
    set lConfirmation "cancel"
    catch {set lConfirmation [tk_messageBox -type okcancel -default cancel -icon warning \
        -title "Page Number Reset" \
        -message "This will reset Page Number and Page Count only. Component references will not be changed.\n\nPages: [llength $lPagePlan]\nNew page order:$lPreview\n\nPlease make sure the design is backed up before continuing."]}
    if {$lConfirmation != "ok"} {
        puts "Page number reset: cancelled."
        return
    }

    set lJournal {}
    if {[catch {::PageAutoAnnotate::ApplyPageNumbers $lPagePlan [llength $lPagePlan] lJournal} lError]} {
        set lRestoreFailures [::PageAutoAnnotate::RestorePageNumbers $lJournal]
        catch {Menu "View::Zoom::Redraw"}
        catch {tk_messageBox -type ok -icon error -title "Page Number Reset" \
            -message "$lError\n\nThe script attempted to restore the original page properties.\nRestore failures: $lRestoreFailures"}
        puts "Page number reset failed: $lError; restore-failures=$lRestoreFailures"
        return
    }

    catch {Menu "View::Zoom::Redraw"}
    catch {tk_messageBox -type ok -icon info -title "Page Number Reset" \
        -message "Page number reset complete.\n\nPages updated: [llength $lPagePlan]\nComponent references were not changed.\n\nPlease inspect and save the design."}
    puts "Page number reset complete: pages=[llength $lPagePlan]"
}

# -----------------------------------------------------------------------------
# Export the selected parts' pins and connected nets to an Excel workbook.
# The schematic is read only.  A pure Tcl 8.4 writer creates the standard
# Open XML .xlsx package without Excel, WPS automation, PowerShell, or any
# external process.
# -----------------------------------------------------------------------------

namespace eval ::SelectedPinNetExport {
    if {![info exists Busy]} {variable Busy 0}
}

proc ::SelectedPinNetExport::Enabler {} {
    return [::OrCADQuickTools::HasSelectedPart]
}


proc ::SelectedPinNetExport::GetDefaultLocation {} {
    set lDirectory [pwd]
    set lBaseName "Selected_Pin_Net"

    set lDesign "NULL"
    catch {set lDesign [GetActivePMDesign]}
    if {$lDesign != "NULL" && $lDesign != ""} {
        set lDesignName [::TitleBlockSync::GetObjectString $lDesign "GetName"]
        if {$lDesignName != ""} {
            set lCandidateDirectory [file dirname $lDesignName]
            if {[file isdirectory $lCandidateDirectory]} {
                set lDirectory $lCandidateDirectory
            }
            set lCandidateBase [file rootname [file tail $lDesignName]]
            if {$lCandidateBase != ""} {
                set lBaseName "${lCandidateBase}_Selected_Pin_Net"
            }
        }
    }

    set lTimestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
    return [list $lDirectory "${lBaseName}_${lTimestamp}.xlsx"]
}

proc ::SelectedPinNetExport::ChooseOutputFile {} {
    foreach {lInitialDirectory lInitialFile} [::SelectedPinNetExport::GetDefaultLocation] break

    if {[catch {package require Tk}]} {
        return [file join $lInitialDirectory $lInitialFile]
    }
    set lOutputFile [tk_getSaveFile \
        -title "Export Selected Part Pin-Net Table" \
        -initialdir $lInitialDirectory \
        -initialfile $lInitialFile \
        -defaultextension ".xlsx" \
        -filetypes [list [list "Excel Workbook" ".xlsx"] [list "All Files" "*"]]]
    return $lOutputFile
}

proc ::SelectedPinNetExport::Run {} {
    variable Busy
    if {$Busy} {return}
    set Busy 1
    set code [catch {Execute} message]
    set Busy 0
    if {$code} {
        set logFile [::OrCADQuickTools::TempPath OrCADPinNetExport.log]
        set channel ""
        set details ""
        if {$logFile ne "" && ![catch {
            set channel [open $logFile w]
            fconfigure $channel -encoding utf-8
            puts $channel $message
            close $channel
            set channel ""
        }]} {set details "\n\nDiagnostic log:\n$logFile"}
        if {$channel ne ""} {catch {close $channel}}
        catch {tk_messageBox -type ok -icon error -title "Excel Export" -message "$message$details"}
        puts "Pin-net export failed: $message"
    }
}

proc ::SelectedPinNetExport::Execute {} {
    set page [GetActivePage]
    if {[::QuickToolsDbo::Null $page]} {error "Open a schematic page first."}
    set selection [GetSelectedObjects]
    set parts {}; set skipped 0
    array set seen {}
    foreach object $selection {
        if {[info exists seen($object)]} {continue}
        set seen($object) 1
        if {[::OrCADQuickTools::IsPlacedPart $object]} {
            lappend parts $object
        } else {
            incr skipped
        }
    }
    if {![llength $parts]} {error "Select at least one schematic component."}

    set output [ChooseOutputFile]
    if {$output eq ""} {return}
    if {[GetActivePage] ne $page || [GetSelectedObjects] ne $selection} {
        error "The page or selection changed while choosing the output file. Run the export again."
    }
    if {![string equal -nocase [file extension $output] .xlsx]} {append output .xlsx}

    set pageName [::QuickToolsDbo::String $page GetName]
    set rows {}; set noPins 0
    foreach part $parts {
        set reference [::PageReferenceFix::GetReference $part]
        if {$reference eq ""} {error "$pageName: A selected part has no readable reference."}
        set unitRows [::DesignPinNetExport::PartRows $page $pageName $part $reference]
        if {![llength $unitRows]} {incr noPins}
        foreach row $unitRows {lappend rows $row}
    }
    if {![llength $rows]} {error "No pins were found on the selected schematic parts."}
    ::OrCADPinNetXlsx::WriteWorkbook $output $rows
    catch {tk_messageBox -type ok -icon info -title "Excel Export" \
        -message "Export complete.\n\nPlaced units: [llength $parts]\nPins: [llength $rows]\nUnits with no pins: $noPins\nOther selected objects skipped: $skipped\nFile: $output"}
    puts "Pin-net export: placed-units=[llength $parts], pins=[llength $rows], zero-pin-units=$noPins, skipped=$skipped, file=$output"
}

# -----------------------------------------------------------------------------
# Shortcut help and clickable Accessories > Quick Tools menu.
# Capture owns the bare Alt key, so the menu and Alt+F1 provide discoverable
# access without intercepting the application's normal menu behavior.
# -----------------------------------------------------------------------------

namespace eval ::QuickToolsHelp {
    variable MenuName "\u5FEB\u6377\u5DE5\u5177"
    variable AuthorName "\u5C0F\u822A"
    variable AuthorWeChat "XiaoHang_Sky"
}

proc ::QuickToolsHelp::Enabler {} {
    return 1
}

proc ::QuickToolsHelp::ShortcutItems {} {
    set items {}
    foreach definition [::OrCADQuickTools::ActionDefinitions] {
        lappend items [list [lindex $definition 1] [lindex $definition 2] [lindex $definition 4]]
    }
    return $items
}

proc ::QuickToolsHelp::ShortcutText {} {
    variable AuthorName
    variable AuthorWeChat
    set lText ""
    set lItems [::QuickToolsHelp::ShortcutItems]
    foreach lItem $lItems {
        append lText "[lindex $lItem 0]    [lindex $lItem 1]\n"
    }
    set lNumberStep 0
    foreach lCommand {::PageAutoAnnotate::RunPageNumbers ::PageAutoAnnotate::RunAll} {
        foreach lItem $lItems {
            if {[lindex $lItem 2] eq $lCommand} {
                lappend lSteps "[incr lNumberStep]. [lindex $lItem 0]"
                break
            }
        }
    }
    if {$lNumberStep == 2} {
        append lText "\n\u5982\u9700\u540C\u65F6\u91CD\u7F6E\u9875\u7801\u548C\u6240\u6709\u4F4D\u53F7\uFF0C\u8BF7\u6309\u987A\u5E8F\u6267\u884C\uFF1A\n[join $lSteps \n]"
    }
    append lText "\n\n\u9F20\u6807\u6EDA\u8F6E\uFF1A\u7ED8\u56FE\u533A\u76F4\u63A5\u7F29\u653E\uFF08\u65E0\u9700 Ctrl\uFF09\n\u6309\u4F4F\u53F3\u952E\u62D6\u52A8\uFF1A\u753B\u5E03\u8DDF\u968F\u9F20\u6807\u79FB\u52A8\uFF0C\u677E\u5F00\u505C\u6B62\nAccessories > \u5FEB\u6377\u5DE5\u5177 > \u9F20\u6807\u5BFC\u822A\u5F00\u5173"
    append lText "\n\n\u5355\u51FB\u5668\u4EF6\uFF1A\u65E5\u5FD7\u663E\u793A\u53C2\u6570\u3002\nAccessories > \u5FEB\u6377\u5DE5\u5177 > \u5355\u51FB\u5668\u4EF6\u53C2\u6570\u9884\u89C8\u5F00\u5173"
    append lText "\n\n\u4F5C\u8005\uFF1A$AuthorName\n\u8054\u7CFB\u65B9\u5F0F\uFF08VX\uFF09\uFF1A$AuthorWeChat"
    return $lText
}

proc ::QuickToolsHelp::Show {args} {
    catch {tk_messageBox -type ok -icon info -title "OrCAD \u5FEB\u6377\u5DE5\u5177" \
        -message [::QuickToolsHelp::ShortcutText]}
}

proc ::QuickToolsHelp::Invoke {pCommand args} {
    if {[llength [info commands $pCommand]] > 0} {
        uplevel #0 [list $pCommand]
    }
}

proc ::QuickToolsHelp::AddOneMenuItem {pLabel pCommand} {
    variable MenuName
    set lCallback "::QuickToolsHelp::Invoke $pCommand"
    if {[catch {AddAccessoryMenu $MenuName $pLabel $lCallback}]} {
        catch {ui::AddAccessoryMenu $MenuName $pLabel $lCallback}
    }
}

proc ::QuickToolsHelp::AddAccessoryMenus {args} {
    foreach lItem [::QuickToolsHelp::ShortcutItems] {
        ::QuickToolsHelp::AddOneMenuItem "[lindex $lItem 1]    [lindex $lItem 0]" [lindex $lItem 2]
    }
    ::QuickToolsHelp::AddOneMenuItem "\u9F20\u6807\u5BFC\u822A\u5F00\u5173\uFF08\u6EDA\u8F6E\u7F29\u653E/\u53F3\u952E\u5E73\u79FB\uFF09" "::OrCADQuickTools::ToggleWheelZoom"
    ::QuickToolsHelp::AddOneMenuItem "\u5355\u51FB\u5668\u4EF6\u53C2\u6570\u9884\u89C8\u5F00\u5173" "::PartPreview::Toggle"
}

# =============================================================================
# BOOTSTRAP: validate all actions before changing any existing registration.
# Re-sourcing keeps the wheel controller's timers and single-instance state.
# =============================================================================
proc ::OrCADQuickTools::ValidateActions {definitions} {
    array set names {}
    array set keys {}
    foreach definition $definitions {
        if {[llength $definition] != 6} {error "An action must have six fields: $definition"}
        foreach {name key label enabler command context} $definition break
        if {$name eq "" || $key eq "" || $label eq ""} {error "An action requires a name, hotkey and label."}
        set normalizedKey [string toupper $key]
        if {[info exists names($name)]} {error "Duplicate action name: $name"}
        if {[info exists keys($normalizedKey)]} {error "Duplicate hotkey: $key"}
        foreach callback [list $enabler $command] {
            if {![llength [info commands $callback]]} {error "Action callback not defined: $callback"}
        }
        set names($name) 1
        set keys($normalizedKey) 1
    }
}

proc ::OrCADQuickTools::RegisterActions {} {
    variable RegisteredActions
    variable MenuEventsRegistered
    set definitions [::OrCADQuickTools::ActionDefinitions]
    ::OrCADQuickTools::ValidateActions $definitions
    foreach definition $definitions {
        foreach {name key label enabler command context} $definition break
        # Capture 16.6 can leave stale accelerators after unregister/register.
        # Reload procedure bodies in place; retain the native action identity.
        set binding [list $enabler $key $command $context]
        if {[info exists RegisteredActions($name)]} {
            if {$RegisteredActions($name) ne $binding} {
                puts "Quick tools: changed binding for $name requires a Capture restart."
            }
            continue
        }
        RegisterAction $name $enabler $key $command $context
        set RegisteredActions($name) $binding
    }
    # Capture menu-building events are shared; do not unregister these events.
    if {!$MenuEventsRegistered} {
        RegisterAction "_cdnCapTclAddPageCustomMenu" \
            "::QuickToolsHelp::Enabler" "" "::QuickToolsHelp::AddAccessoryMenus" ""
        RegisterAction "_cdnCapTclAddDesignCustomMenu" \
            "::QuickToolsHelp::Enabler" "" "::QuickToolsHelp::AddAccessoryMenus" ""
        set MenuEventsRegistered 1
    }
}

proc ::OrCADQuickTools::Initialize {} {
    if {[llength [info commands RegisterAction]]} {
        ::OrCADQuickTools::RegisterActions
        set shortcuts {}
        foreach item [::QuickToolsHelp::ShortcutItems] {lappend shortcuts [lindex $item 0]}
        puts "OrCAD quick tools loaded: [join $shortcuts {, }]"
    }
    ::OrCADWheel::Initialize
    if {[llength [info commands ::PartPreview::Initialize]]} {
        if {[catch {::PartPreview::Initialize} message]} {puts "Part preview unavailable: $message"}
    }
}
