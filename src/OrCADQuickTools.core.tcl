# OrCAD Capture 16.6 quick tools.
# Alt+F1: show all quick-tool shortcuts.
# Alt+F2: add "NC," to selected part values.
# Alt+F3: remove one leading "NC," from selected part values.
# Alt+F5: replace selected off-page input/output graphics, preserving names.
# Alt+F6: export selected part pin-to-net data to an Excel workbook.
# Alt+F7: update every title block Doc and synchronize Title with Page Name.
# Alt+F8: reannotate the current page from left to right, top to bottom.
# Alt+F9: reannotate all pages by position using existing page numbers.
# Alt+F10: reset Page Number and Page Count only.
# Alt+R: move selected misplaced references into the current page range.
# Alt+S: open native Signals navigation for one selected scalar wire.

package require Tcl 8.4
catch {package require DboTclWriteBasic 16.3.0}

namespace eval ::OrCADQuickTools {
    variable ScriptDirectory [file dirname [info script]]
    if {![info exists RegisteredActions]} {variable RegisteredActions; array set RegisteredActions {}}
    if {![info exists MenuEventsRegistered]} {variable MenuEventsRegistered 0}
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
            "::QuickToolsHelp::Enabler" "::OrCADQuickTools::ToggleOffPage" "Schematic"] \
        [list "Export Selected Part Pin Net Table To Excel" "Alt+F6" \
            "\u5BFC\u51FA\u6240\u9009\u5668\u4EF6\u7684\u5F15\u811A-\u7F51\u7EDC\u8868 (XLSX)" \
            "::SelectedPinNetExport::Enabler" "::SelectedPinNetExport::Run" "Schematic"] \
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
    variable LogFile [file join $::env(TEMP) OrCADSignalsNavigation.log]
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
    set Pending ""
    if {![StillSelected $snapshot]} {Log "Cancelled: selection/page changed before refresh"; return}
    set resultFile [file join $::env(TEMP) OrCADSignalsContext-[pid]-[clock clicks].result]
    if {[catch {StartContext $resultFile} message]} {
        Log "Context helper failed: $message"
        Notice "\u65E0\u6CD5\u5237\u65B0 Signals \u4E0A\u4E0B\u6587\uFF1A\n$message"
        return
    }
    set Busy 1
    set Pending [after 50 [list ::SignalsNavigation::PollContext $snapshot $resultFile 0]]
}

proc ::SignalsNavigation::StartContext {resultFile} {
    set helper [file join $::OrCADQuickTools::ScriptDirectory OrCADWheelZoom.exe]
    if {![file exists $helper]} {error "Missing OrCADWheelZoom.exe"}
    set started [clock clicks -milliseconds]
    exec $helper --signals-context [pid] $resultFile < NUL >& NUL &
    Log "Context helper launch returned after [expr {[clock clicks -milliseconds]-$started}] ms"
    # The GUI helper must enter its own input-idle loop before Tcl's Windows
    # launcher returns. Only now allow it to inject input into Capture.
    set ready ""
    set readyPath "$resultFile.ready"
    if {[catch {
        set ready [open $readyPath {WRONLY CREAT EXCL}]
        puts -nonewline $ready "capture-ready-v17"
        close $ready
        set ready ""
    } message]} {
        if {$ready ne ""} {catch {close $ready}}
        error "Signals launch handshake failed: $message"
    }
}

proc ::SignalsNavigation::PollContext {snapshot resultFile attempt} {
    variable Pending
    variable Busy
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
    # Release-keys/menu lookup plus bounded popup cleanup can take about 5 s.
    if {$result eq "" && $attempt < 110} {
        set Pending [after 50 [list ::SignalsNavigation::PollContext $snapshot $resultFile [expr {$attempt+1}]]]
        return
    }
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

proc ::NCValuePrefix::Run {} {
    variable Prefix

    if {[catch {set lSelectedObjects [GetSelectedObjects]} lSelectionError]} {
        puts "NC prefix: cannot read the current selection: $lSelectionError"
        return
    }

    set lUpdated 0
    set lAlreadyPrefixed 0
    set lSkipped 0
    set lFailed 0

    foreach lObject $lSelectedObjects {
        if {![::OrCADQuickTools::IsPlacedPart $lObject]} {
            incr lSkipped
            continue
        }

        set lOldValueCString [DboTclHelper_sMakeCString]
        if {[catch {$lObject GetPartValue $lOldValueCString} lReadError]} {
            incr lFailed
            continue
        }
        set lOldValue [DboTclHelper_sGetConstCharPtr $lOldValueCString]

        set lPrefixLength [string length $Prefix]
        set lExistingPrefix [string range $lOldValue 0 [expr {$lPrefixLength - 1}]]
        if {[string equal -nocase $lExistingPrefix $Prefix]} {
            incr lAlreadyPrefixed
            continue
        }

        set lNewValueCString [DboTclHelper_sMakeCString "${Prefix}${lOldValue}"]
        if {[catch {$lObject SetPartValue $lNewValueCString} lWriteError]} {
            incr lFailed
            continue
        }
        incr lUpdated
    }

    catch {Menu "View::Zoom::Redraw"}
    puts "NC prefix: updated=$lUpdated, already-prefixed=$lAlreadyPrefixed, non-parts-skipped=$lSkipped, failed=$lFailed"
}

proc ::NCValuePrefix::Remove {} {
    variable Prefix

    if {[catch {set lSelectedObjects [GetSelectedObjects]} lSelectionError]} {
        puts "NC prefix removal: cannot read the current selection: $lSelectionError"
        return
    }

    set lUpdated 0
    set lWithoutPrefix 0
    set lSkipped 0
    set lFailed 0
    set lPrefixLength [string length $Prefix]

    foreach lObject $lSelectedObjects {
        if {![::OrCADQuickTools::IsPlacedPart $lObject]} {
            incr lSkipped
            continue
        }

        set lOldValueCString [DboTclHelper_sMakeCString]
        if {[catch {$lObject GetPartValue $lOldValueCString} lReadError]} {
            incr lFailed
            continue
        }
        set lOldValue [DboTclHelper_sGetConstCharPtr $lOldValueCString]

        set lExistingPrefix [string range $lOldValue 0 [expr {$lPrefixLength - 1}]]
        if {![string equal -nocase $lExistingPrefix $Prefix]} {
            incr lWithoutPrefix
            continue
        }

        set lNewValue [string range $lOldValue $lPrefixLength end]
        set lNewValueCString [DboTclHelper_sMakeCString $lNewValue]
        if {[catch {$lObject SetPartValue $lNewValueCString} lWriteError]} {
            incr lFailed
            continue
        }
        incr lUpdated
    }

    catch {Menu "View::Zoom::Redraw"}
    puts "NC prefix removal: updated=$lUpdated, without-prefix=$lWithoutPrefix, non-parts-skipped=$lSkipped, failed=$lFailed"
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
    set lPropertyName [DboTclHelper_sMakeCString "Reference"]
    set lPropertyValue [DboTclHelper_sMakeCString]
    if {![catch {$pPart GetEffectivePropStringValue $lPropertyName $lPropertyValue}]} {
        set lVisible [string trim [DboTclHelper_sGetConstCharPtr $lPropertyValue]]
        if {$lVisible != ""} {return $lVisible}
    }
    set lReferenceCString [DboTclHelper_sMakeCString]
    if {[catch {$pPart GetReference $lReferenceCString}]} {
        return ""
    }
    return [DboTclHelper_sGetConstCharPtr $lReferenceCString]
}

proc ::PageReferenceFix::GetCurrentPageNumber {pPage pStatus} {
    set lPageNumberName [DboTclHelper_sMakeCString "Page Number"]
    set lPageNumberValue [DboTclHelper_sMakeCString]
    if {![catch {set lTitleBlocksIter [$pPage NewTitleBlocksIter $pStatus]}]} {
        set lTitleBlock [$lTitleBlocksIter NextTitleBlock $pStatus]
        while {$lTitleBlock != "NULL"} {
            if {![catch {$lTitleBlock GetEffectivePropStringValue $lPageNumberName $lPageNumberValue}]} {
                set lCandidate [DboTclHelper_sGetConstCharPtr $lPageNumberValue]
                if {[string is integer -strict $lCandidate] && $lCandidate > 0} {
                    catch {delete_DboPageTitleBlocksIter $lTitleBlocksIter}
                    return $lCandidate
                }
            }
            set lTitleBlock [$lTitleBlocksIter NextTitleBlock $pStatus]
        }
        catch {delete_DboPageTitleBlocksIter $lTitleBlocksIter}
    }

    # The title-block property is the sheet number users see and edit.  The
    # DboPage number can instead be a separate database position.
    if {![catch {set lPageNumber [$pPage GetPageNumber $pStatus]}]} {
        if {[string is integer -strict $lPageNumber] && $lPageNumber > 0} {
            return $lPageNumber
        }
    }

    set lPageNameCString [DboTclHelper_sMakeCString]
    if {![catch {$pPage GetName $lPageNameCString}]} {
        set lPageName [DboTclHelper_sGetConstCharPtr $lPageNameCString]
        if {[regexp {([0-9]+)$} $lPageName lWhole lCandidate]} {
            if {$lCandidate > 0} {
                return [expr {int($lCandidate)}]
            }
        }
    }
    return 0
}

proc ::PageReferenceFix::CollectPageReferences {pPage pStatus pUsedName pMaxName} {
    upvar 1 $pUsedName lUsed
    upvar 1 $pMaxName lMax

    set lPartsIter [$pPage NewPartInstsIter $pStatus]
    set lPart [$lPartsIter NextPartInst $pStatus]
    while {$lPart != "NULL"} {
        if {[::OrCADQuickTools::IsPlacedPart $lPart]} {
            set lReference [::PageReferenceFix::GetReference $lPart]
            if {[::PageReferenceFix::SplitReference $lReference lPrefix lNumber]} {
                set lPrefixKey [string toupper $lPrefix]
                set lUsed($lPrefixKey,$lNumber) 1
                if {![info exists lMax($lPrefixKey)] || $lNumber > $lMax($lPrefixKey)} {
                    set lMax($lPrefixKey) $lNumber
                }
            }
        }
        set lPart [$lPartsIter NextPartInst $pStatus]
    }
    catch {delete_DboPagePartInstsIter $lPartsIter}
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
    set lPageNumber [::PageReferenceFix::GetCurrentPageNumber $lPage $lStatus]
    if {$lPageNumber <= 0} {
        catch {$lStatus -delete}
        puts "Page reference fix: cannot determine the current page number; no references were changed."
        return
    }

    set lRangeStart [expr {$lPageNumber * $NumbersPerPage + 1}]
    set lRangeEnd [expr {$lPageNumber * $NumbersPerPage + $NumbersPerPage - 1}]
    array set lUsed {}
    array set lMax {}
    ::PageReferenceFix::CollectPageReferences $lPage $lStatus lUsed lMax

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
        set lNewReferenceCString [DboTclHelper_sMakeCString $lNewReference]
        if {[catch {$lObject SetReference $lNewReferenceCString} lWriteError]} {
            incr lFailed
            continue
        }

        set lUsed($lPrefixKey,$lNewNumber) 1
        set lMax($lPrefixKey) $lNewNumber
        incr lUpdated
        puts "Page reference fix: $lOldReference -> $lNewReference"
    }

    catch {$lStatus -delete}
    catch {Menu "View::Zoom::Redraw"}
    puts "Page reference fix: page=$lPageNumber, range=$lRangeStart-$lRangeEnd, updated=$lUpdated, already-correct=$lAlreadyCorrect, skipped=$lSkipped, failed=$lFailed"
}

# -----------------------------------------------------------------------------
# Synchronize all title blocks in the active design.
# -----------------------------------------------------------------------------

namespace eval ::TitleBlockSync {
    variable ProjectName ""
    variable DialogResult ""
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
    set lValueCString [DboTclHelper_sMakeCString]
    if {[catch {$pObject $pMethod $lValueCString}]} {
        return ""
    }
    return [DboTclHelper_sGetConstCharPtr $lValueCString]
}

proc ::TitleBlockSync::GetCurrentDoc {} {
    set lPage "NULL"
    catch {set lPage [GetActivePage]}
    if {$lPage == "NULL" || $lPage == ""} {
        return ""
    }

    set lStatus [DboState]
    set lTitleBlocksIter "NULL"
    if {[catch {set lTitleBlocksIter [$lPage NewTitleBlocksIter $lStatus]}] ||
        $lTitleBlocksIter == "NULL" || $lTitleBlocksIter == ""} {
        catch {$lStatus -delete}
        return ""
    }

    set lResult ""
    set lTitleBlock [$lTitleBlocksIter NextTitleBlock $lStatus]
    if {$lTitleBlock != "NULL" && $lTitleBlock != ""} {
        set lPropName [DboTclHelper_sMakeCString "Doc"]
        set lPropValue [DboTclHelper_sMakeCString]
        if {![catch {$lTitleBlock GetEffectivePropStringValue $lPropName $lPropValue}]} {
            set lResult [DboTclHelper_sGetConstCharPtr $lPropValue]
        }
    }

    catch {delete_DboPageTitleBlocksIter $lTitleBlocksIter}
    catch {$lStatus -delete}
    return $lResult
}

proc ::TitleBlockSync::PromptProjectName {} {
    variable ProjectName
    variable DialogResult

    if {[catch {package require Tk} lTkError]} {
        puts "Title block sync: Tk is unavailable: $lTkError"
        return ""
    }
    catch {wm withdraw .}

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
    set lNameCString [DboTclHelper_sMakeCString $pName]
    set lValueCString [DboTclHelper_sMakeCString $pValue]
    if {[catch {set lWriteStatus [$pObject SetEffectivePropStringValue $lNameCString $lValueCString]}]} {
        return 0
    }
    if {$lWriteStatus == "NULL" || $lWriteStatus == ""} {
        return 0
    }
    if {[catch {set lOK [$lWriteStatus OK]}] || !$lOK} {
        return 0
    }
    return 1
}

proc ::TitleBlockSync::Run {} {
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

    set lStatus [DboState]
    set lPageCount 0
    set lTitleBlockCount 0
    set lUpdatedCount 0
    set lPageWithoutTitleBlockCount 0
    set lFailedPropertyCount 0

    set lViewsIter "NULL"
    if {[catch {set lViewsIter [$lDesign NewViewsIter $lStatus $::IterDefs_SCHEMATICS]} lViewError] ||
        $lViewsIter == "NULL" || $lViewsIter == ""} {
        catch {$lStatus -delete}
        catch {tk_messageBox -type ok -icon error -title "Title Block Sync" \
            -message "The schematic pages could not be read.\n\n$lViewError"}
        puts "Title block sync: cannot create schematic iterator: $lViewError"
        return
    }

    set lView [$lViewsIter NextView $lStatus]
    while {$lView != "NULL" && $lView != ""} {
        set lSchematic "NULL"
        catch {set lSchematic [DboViewToDboSchematic $lView]}
        if {$lSchematic != "NULL" && $lSchematic != ""} {
            set lPagesIter "NULL"
            if {![catch {set lPagesIter [$lSchematic NewPagesIter $lStatus]}] &&
                $lPagesIter != "NULL" && $lPagesIter != ""} {
                set lPage [$lPagesIter NextPage $lStatus]
                while {$lPage != "NULL" && $lPage != ""} {
                    incr lPageCount
                    set lPageName [::TitleBlockSync::GetObjectString $lPage "GetName"]
                    set lPageTitleBlockCount 0
                    set lTitleBlocksIter "NULL"
                    if {![catch {set lTitleBlocksIter [$lPage NewTitleBlocksIter $lStatus]}] &&
                        $lTitleBlocksIter != "NULL" && $lTitleBlocksIter != ""} {
                        set lTitleBlock [$lTitleBlocksIter NextTitleBlock $lStatus]
                        while {$lTitleBlock != "NULL" && $lTitleBlock != ""} {
                            incr lPageTitleBlockCount
                            incr lTitleBlockCount
                            set lDocOK [::TitleBlockSync::WriteProperty $lTitleBlock "Doc" $lProjectName]
                            set lTitleOK [::TitleBlockSync::WriteProperty $lTitleBlock "Title" $lPageName]
                            if {$lDocOK && $lTitleOK} {
                                incr lUpdatedCount
                            } else {
                                if {!$lDocOK} {
                                    incr lFailedPropertyCount
                                }
                                if {!$lTitleOK} {
                                    incr lFailedPropertyCount
                                }
                            }
                            set lTitleBlock [$lTitleBlocksIter NextTitleBlock $lStatus]
                        }
                        catch {delete_DboPageTitleBlocksIter $lTitleBlocksIter}
                    }
                    if {$lPageTitleBlockCount == 0} {
                        incr lPageWithoutTitleBlockCount
                    }
                    set lPage [$lPagesIter NextPage $lStatus]
                }
                catch {delete_DboSchematicPagesIter $lPagesIter}
            }
        }
        set lView [$lViewsIter NextView $lStatus]
    }

    catch {delete_DboLibViewsIter $lViewsIter}
    catch {$lStatus -delete}
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
    set lName [DboTclHelper_sMakeCString "Reference"]
    set lValue [DboTclHelper_sMakeCString]
    if {[catch {$pObject GetEffectivePropStringValue $lName $lValue}]} {
        return [list 0 ""]
    }
    if {[catch {set lText [DboTclHelper_sGetConstCharPtr $lValue]}]} {
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
    if {[catch {set lOccurrence [quickToolsOccurrencesIter NextOccurrence $pStatus]}]} {
        set lError "The first design occurrence could not be read."
    }
    while {$lError == "" && $lOccurrence != "NULL" && $lOccurrence != ""} {
        set lPart "NULL"
        catch {set lPart [$lOccurrence GetPartInst $pStatus]}
        if {$lPart != "NULL" && $lPart != "" && [::OrCADQuickTools::IsPlacedPart $lPart]} {
            if {[info exists lOccurrences($lPart)]} {
                set lError "A component has multiple occurrences; no changes were made."
                break
            }
            set lOccurrences($lPart) $lOccurrence
        }
        if {[catch {set lOccurrence [quickToolsOccurrencesIter NextOccurrence $pStatus]}]} {
            set lError "A design occurrence could not be read."
        }
    }
    catch {rename quickToolsOccurrencesIter {}}
    return $lError
}

proc ::PageAutoAnnotate::SetReference {pPart pReference} {
    set lReferenceCString [DboTclHelper_sMakeCString $pReference]
    if {[catch {set lWriteStatus [$pPart SetReference $lReferenceCString]}]} {
        return 0
    }
    if {$lWriteStatus == "NULL" || $lWriteStatus == ""} {
        return 0
    }
    if {[catch {set lOK [$lWriteStatus OK]}] || !$lOK} {
        return 0
    }
    set lVisible [::PageAutoAnnotate::ReadReferenceProperty $pPart]
    if {![lindex $lVisible 0] || ![string equal -nocase [lindex $lVisible 1] $pReference]} {
        if {![::TitleBlockSync::WriteProperty $pPart "Reference" $pReference]} {
            puts "Reference property write failed: $pReference"
            return 0
        }
        set lVisible [::PageAutoAnnotate::ReadReferenceProperty $pPart]
    }
    if {![lindex $lVisible 0] || ![string equal -nocase [lindex $lVisible 1] $pReference]} {
        puts "Reference property read-back failed: target=$pReference, actual=[lindex $lVisible 1]"
        return 0
    }
    return 1
}

proc ::PageAutoAnnotate::ApplyReferenceToGroup {pRecords pReference} {
    foreach lRecord $pRecords {
        set lPart [lindex $lRecord 0]
        if {![::PageAutoAnnotate::SetReference $lPart $pReference]} {
            return 0
        }
        set lOccurrence [lindex $lRecord 6]
        if {$lOccurrence != "" && $lOccurrence != "NULL" &&
            ![::PageAutoAnnotate::SetReference $lOccurrence $pReference]} {
            return 0
        }
    }
    return 1
}

proc ::PageAutoAnnotate::ReadTitleProperty {pTitleBlock pName} {
    set lName [DboTclHelper_sMakeCString $pName]
    set lValue [DboTclHelper_sMakeCString]
    if {[catch {$pTitleBlock GetEffectivePropStringValue $lName $lValue}]} {
        return [list 0 ""]
    }
    if {[catch {set lText [DboTclHelper_sGetConstCharPtr $lValue]}]} {
        return [list 0 ""]
    }
    return [list 1 [string trim $lText]]
}

proc ::PageAutoAnnotate::ReadPageTitleBlocks {pPage pStatus} {
    set lTitleBlocksIter "NULL"
    if {[catch {set lTitleBlocksIter [$pPage NewTitleBlocksIter $pStatus]}] ||
        $lTitleBlocksIter == "NULL" || $lTitleBlocksIter == ""} {
        return {}
    }

    set lRecords {}
    set lTitleBlock [$lTitleBlocksIter NextTitleBlock $pStatus]
    while {$lTitleBlock != "NULL" && $lTitleBlock != ""} {
        set lOldVisibleNumber [::PageAutoAnnotate::ReadTitleProperty $lTitleBlock "Page Number"]
        set lOldVisibleCount [::PageAutoAnnotate::ReadTitleProperty $lTitleBlock "Page Count"]
        lappend lRecords [list $lTitleBlock $lOldVisibleNumber $lOldVisibleCount]
        set lTitleBlock [$lTitleBlocksIter NextTitleBlock $pStatus]
    }
    catch {delete_DboPageTitleBlocksIter $lTitleBlocksIter}
    return $lRecords
}

proc ::PageAutoAnnotate::ApplyPageNumbers {pPagePlan pPageCount} {
    foreach lPageRecord $pPagePlan {
        set lNumber [lindex $lPageRecord 3]
        foreach lTitleRecord [lindex $lPageRecord 5] {
            set lTitleBlock [lindex $lTitleRecord 0]
            if {![::TitleBlockSync::WriteProperty $lTitleBlock "Page Number" $lNumber] ||
                ![::TitleBlockSync::WriteProperty $lTitleBlock "Page Count" $pPageCount]} {
                return "Could not update visible title-block page properties on [lindex $lPageRecord 2]."
            }
            set lVisibleNumber [::PageAutoAnnotate::ReadTitleProperty $lTitleBlock "Page Number"]
            set lVisibleCount [::PageAutoAnnotate::ReadTitleProperty $lTitleBlock "Page Count"]
            if {![lindex $lVisibleNumber 0] || [lindex $lVisibleNumber 1] != $lNumber ||
                ![lindex $lVisibleCount 0] || [lindex $lVisibleCount 1] != $pPageCount} {
                return "Title-block Page Number / Page Count did not change on [lindex $lPageRecord 2] (read back: [lindex $lVisibleNumber 1] / [lindex $lVisibleCount 1])."
            }
            puts "Page numbering verified: [lindex $lPageRecord 2] -> $lNumber / $pPageCount"
        }
    }
    return ""
}

proc ::PageAutoAnnotate::RestorePageNumbers {pPagePlan} {
    set lFailures 0
    foreach lPageRecord $pPagePlan {
        foreach lTitleRecord [lindex $lPageRecord 5] {
            set lTitleBlock [lindex $lTitleRecord 0]
            foreach {lProperty lOldVisible} [list "Page Number" [lindex $lTitleRecord 1] "Page Count" [lindex $lTitleRecord 2]] {
                if {[lindex $lOldVisible 0]} {
                    if {![::TitleBlockSync::WriteProperty $lTitleBlock $lProperty [lindex $lOldVisible 1]]} {
                        incr lFailures
                    } else {
                        set lRestored [::PageAutoAnnotate::ReadTitleProperty $lTitleBlock $lProperty]
                        if {![lindex $lRestored 0] ||
                            ![string equal [lindex $lRestored 1] [lindex $lOldVisible 1]]} {
                            incr lFailures
                        }
                    }
                }
            }
        }
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

proc ::PageAutoAnnotate::ResolveNamedPageOrder {pPagePlan pRecordsName pInvalidPagesName} {
    upvar 1 $pRecordsName lGroupRecords
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
    array set lPageNumbers {}
    set lNewNumber 0
    foreach lPageRecord $lSortable {
        incr lNewNumber
        set lPage [lindex $lPageRecord 1]
        set lPageNumbers($lPage) $lNewNumber
        lappend lOrderedPlan [lreplace $lPageRecord 3 3 $lNewNumber]
    }
    foreach lGroupKey [array names lGroupRecords] {
        set lUpdatedRecords {}
        foreach lRecord $lGroupRecords($lGroupKey) {
            set lPage [lindex $lRecord 5]
            lappend lUpdatedRecords [lreplace $lRecord 1 1 $lPageNumbers($lPage)]
        }
        set lGroupRecords($lGroupKey) $lUpdatedRecords
    }
    return $lOrderedPlan
}

proc ::PageAutoAnnotate::CollectDesign {pDesign pStatus pMode pRecordsName pPrefixName pOldReferenceName pOrderName pExistingName pPagesName pInvalidPagesName pPagePlanName pStatsName} {
    upvar 1 $pRecordsName lGroupRecords
    upvar 1 $pPrefixName lGroupPrefix
    upvar 1 $pOldReferenceName lGroupOldReference
    upvar 1 $pOrderName lGroupOrder
    upvar 1 $pExistingName lExistingOwners
    upvar 1 $pPagesName lPageOccurrences
    upvar 1 $pInvalidPagesName lInvalidPages
    upvar 1 $pPagePlanName lPagePlan
    upvar 1 $pStatsName lStats

    array set lGroupRecords {}
    array set lGroupPrefix {}
    array set lGroupOldReference {}
    array set lExistingOwners {}
    array set lPageOccurrences {}
    set lGroupOrder {}
    set lInvalidPages {}
    set lPagePlan {}
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

    set lViewsIter "NULL"
    if {[catch {set lViewsIter [$pDesign NewViewsIter $pStatus $::IterDefs_SCHEMATICS]}] ||
        $lViewsIter == "NULL" || $lViewsIter == ""} {
        set lStats [list 0 0 0]
        return 0
    }

    set lView [$lViewsIter NextView $pStatus]
    while {$lView != "NULL" && $lView != ""} {
        set lSchematic "NULL"
        catch {set lSchematic [DboViewToDboSchematic $lView]}
        if {$lSchematic != "NULL" && $lSchematic != ""} {
            set lPagesIter "NULL"
            if {![catch {set lPagesIter [$lSchematic NewPagesIter $pStatus]}] &&
                $lPagesIter != "NULL" && $lPagesIter != ""} {
                set lPage [$lPagesIter NextPage $pStatus]
                while {$lPage != "NULL" && $lPage != ""} {
                    incr lPageCount
                    set lPageName [::TitleBlockSync::GetObjectString $lPage "GetName"]
                    set lPageNumber [::PageReferenceFix::GetCurrentPageNumber $lPage $pStatus]
                    if {$lPageNumber <= 0} {
                        lappend lInvalidPages $lPageName
                    } else {
                        lappend lPageOccurrences($lPageNumber) $lPageName
                    }

                    set lPartsIter "NULL"
                    if {![catch {set lPartsIter [$lPage NewPartInstsIter $pStatus]}] &&
                        $lPartsIter != "NULL" && $lPartsIter != ""} {
                        set lPart [$lPartsIter NextPartInst $pStatus]
                        while {$lPart != "NULL" && $lPart != ""} {
                            if {[::OrCADQuickTools::IsPlacedPart $lPart]} {
                                set lPartReference [::PageReferenceFix::GetReference $lPart]
                                set lOccurrence ""
                                set lOccurrenceReference ""
                                if {[info exists lPartOccurrences($lPart)]} {
                                    set lOccurrence $lPartOccurrences($lPart)
                                    set lOccurrenceValue [::PageAutoAnnotate::ReadReferenceProperty $lOccurrence]
                                    if {![lindex $lOccurrenceValue 0] || [lindex $lOccurrenceValue 1] == ""} {
                                        lappend lInvalidPages "$lPageName (occurrence reference unavailable)"
                                    } else {
                                        set lOccurrenceReference [lindex $lOccurrenceValue 1]
                                    }
                                } elseif {$lOccurrenceMode} {
                                    lappend lInvalidPages "$lPageName (component occurrence missing)"
                                }
                                if {$lOccurrenceReference != ""} {
                                    set lOldReference $lOccurrenceReference
                                } else {
                                    set lOldReference $lPartReference
                                }
                                set lPrefix [::PageAutoAnnotate::GetPrefix $lOldReference]
                                if {$lPrefix != ""} {
                                    foreach {lX lY} [::PageAutoAnnotate::GetCoordinates $lPart $pStatus] break
                                    set lReferenceKey [list $lPrefix [string toupper $lOldReference]]
                                    if {[regexp {^[^0-9?]+[0-9]+$} $lOldReference]} {
                                        set lGroupKey $lReferenceKey
                                    } else {
                                        set lGroupKey [list $lPrefix [string toupper $lOldReference] $lPart]
                                    }
                                    if {![info exists lGroupRecords($lGroupKey)]} {
                                        set lGroupRecords($lGroupKey) {}
                                        set lGroupPrefix($lGroupKey) $lPrefix
                                        set lGroupOldReference($lGroupKey) $lOldReference
                                        lappend lGroupOrder $lGroupKey
                                    }
                                    lappend lGroupRecords($lGroupKey) [list $lPart $lPageNumber $lPageName $lX $lY $lPage $lOccurrence $lPartReference $lOccurrenceReference]
                                    lappend lExistingOwners($lReferenceKey) $lGroupKey
                                    incr lPartCount
                                } else {
                                    incr lSkippedCount
                                }
                            } else {
                                incr lSkippedCount
                            }
                            set lPart [$lPartsIter NextPartInst $pStatus]
                        }
                        catch {delete_DboPagePartInstsIter $lPartsIter}
                    }
                    set lPage [$lPagesIter NextPage $pStatus]
                }
                catch {delete_DboSchematicPagesIter $lPagesIter}
            } elseif {$pMode == "all"} {
                catch {delete_DboLibViewsIter $lViewsIter}
                set lStats [list $lPageCount $lPartCount $lSkippedCount]
                return 0
            }
        }
        set lView [$lViewsIter NextView $pStatus]
    }
    catch {delete_DboLibViewsIter $lViewsIter}
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
            if {![::PageAutoAnnotate::SetReference [lindex $lRecord 0] [lindex $lRecord 7]]} {
                incr lFailures
            }
            set lOccurrence [lindex $lRecord 6]
            if {$lOccurrence != "" && $lOccurrence != "NULL" &&
                ![::PageAutoAnnotate::SetReference $lOccurrence [lindex $lRecord 8]]} {
                incr lFailures
            }
        }
    }
    return $lFailures
}

proc ::PageAutoAnnotate::Run {pMode} {
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
        set lCurrentPageNumber [::PageReferenceFix::GetCurrentPageNumber $lCurrentPage $lStatus]
        if {$lCurrentPageNumber <= 0} {
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
    set lGroupOrder {}
    set lInvalidPages {}
    set lPagePlan {}
    set lStats {}
    if {![::PageAutoAnnotate::CollectDesign $lDesign $lStatus $pMode \
        lGroupRecords lGroupPrefix lGroupOldReference lGroupOrder \
        lExistingOwners lPageOccurrences lInvalidPages lPagePlan lStats]} {
        catch {$lStatus -delete}
        set lDetail [join $lInvalidPages {, }]
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
            set lSelectedGroups($lGroupKey) 1
            set lPageNumber [lindex $lAnchor 0]
            set lPageName [lindex $lAnchor 1]
            set lPrefix $lGroupPrefix($lGroupKey)
            set lBucketKey [list $lPageNumber $lPrefix]
            lappend lBuckets($lBucketKey) [list $lGroupKey [lindex $lAnchor 2] [lindex $lAnchor 3]]
            set lAnchorPageName($lGroupKey) $lPageName
        }
    }

    if {[array size lSelectedGroups] == 0 && $pMode != "all"} {
        catch {$lStatus -delete}
        catch {tk_messageBox -type ok -icon warning -title "Reference Reannotation" \
            -message "No annotatable components were found in the selected scope."}
        return
    }

    set lPlan {}
    set lPlanError ""
    foreach lBucketKey [lsort -command ::PageAutoAnnotate::CompareBucketKeys [array names lBuckets]] {
        set lPageNumber [lindex $lBucketKey 0]
        set lPrefix [lindex $lBucketKey 1]
        set lSorted [::PageAutoAnnotate::SortSpatial $lBuckets($lBucketKey)]
        if {[llength $lSorted] > 99} {
            set lPlanError "Page $lPageNumber has more than 99 $lPrefix references."
            break
        }
        set lSequence 1
        foreach lSpatialRecord $lSorted {
            set lGroupKey [lindex $lSpatialRecord 0]
            set lNewReference "${lPrefix}[expr {$lPageNumber * 100 + $lSequence}]"
            lappend lPlan [list $lGroupKey $lGroupOldReference($lGroupKey) $lNewReference $lPrefix $lPageNumber $lAnchorPageName($lGroupKey)]
            incr lSequence
        }
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
        set lPagePreview ""
    } else {
        set lScopeText "current page $lCurrentPageNumber ($lCurrentPageName)"
        set lWarningText "This will reset all component references on the current page. Linked multi-part units retain one shared reference."
        set lPagePreview ""
    }
    if {$pMode == "all"} {
        set lScopePageCount [lindex $lStats 0]
    } else {
        set lScopePageCount 1
    }
    set lConfirmation "cancel"
    catch {set lConfirmation [tk_messageBox -type okcancel -default cancel -icon warning \
        -title "Reference Reannotation" \
        -message "$lWarningText\n\nScope: $lScopeText\nPages: $lScopePageCount\nReferences: [llength $lPlan]\nPlaced units: $lObjectCount\nComponent order: left to right, then top to bottom$lPagePreview\n\nPlease make sure the design is backed up before continuing."]}
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

    set lOperationError ""
    set lReferencesStarted 0
    if {$lOperationError == ""} {
        foreach lItem $lPlan {
            set lReferencesStarted 1
            set lGroupKey [lindex $lItem 0]
            if {![::PageAutoAnnotate::ApplyReferenceToGroup $lGroupRecords($lGroupKey) $lTemporaryReferences($lGroupKey)]} {
                set lOperationError "Failed while assigning temporary references."
                break
            }
        }
    }
    if {$lOperationError == ""} {
        foreach lItem $lPlan {
            set lGroupKey [lindex $lItem 0]
            set lNewReference [lindex $lItem 2]
            if {![::PageAutoAnnotate::ApplyReferenceToGroup $lGroupRecords($lGroupKey) $lNewReference]} {
                set lOperationError "Failed while assigning $lNewReference."
                break
            }
        }
    }
    if {$lOperationError == ""} {
        foreach lItem $lPlan {
            set lTarget [lindex $lItem 2]
            foreach lRecord $lGroupRecords([lindex $lItem 0]) {
                set lPartValue [::PageAutoAnnotate::ReadReferenceProperty [lindex $lRecord 0]]
                if {![lindex $lPartValue 0] || ![string equal -nocase [lindex $lPartValue 1] $lTarget]} {
                    set lOperationError "Reference read-back failed on [lindex $lRecord 2]: expected $lTarget, instance shows [lindex $lPartValue 1]."
                    break
                }
                set lOccurrence [lindex $lRecord 6]
                if {$lOccurrence != "" && $lOccurrence != "NULL"} {
                    set lVisibleValue [::PageAutoAnnotate::ReadReferenceProperty $lOccurrence]
                    if {![lindex $lVisibleValue 0] || ![string equal -nocase [lindex $lVisibleValue 1] $lTarget]} {
                        set lOperationError "Reference read-back failed on [lindex $lRecord 2]: expected $lTarget, occurrence shows [lindex $lVisibleValue 1]."
                        break
                    }
                }
            }
            if {$lOperationError != ""} {break}
        }
    }

    if {$lOperationError != ""} {
        set lRestoreFailures 0
        if {$lReferencesStarted} {
            incr lRestoreFailures [::PageAutoAnnotate::RestoreOriginalReferences $lPlan lGroupRecords]
        }
        catch {$lStatus -delete}
        catch {Menu "View::Zoom::Redraw"}
        catch {tk_messageBox -type ok -icon error -title "Reference Reannotation" \
            -message "$lOperationError\n\nThe script attempted to restore the original references.\nRestore failures: $lRestoreFailures"}
        puts "Reference reannotation failed: $lOperationError; restore-failures=$lRestoreFailures"
        return
    }

    catch {$lStatus -delete}
    catch {Menu "View::Zoom::Redraw"}
    set lPageResult ""
    catch {tk_messageBox -type ok -icon info -title "Reference Reannotation" \
        -message "Reannotation complete.\n\nScope: $lScopeText\n${lPageResult}References updated: [llength $lPlan]\nPlaced units: $lObjectCount\n\nPlease inspect and save the design."}
    puts "Reference reannotation complete: mode=$pMode, pages=$lScopePageCount, references=[llength $lPlan], placed-units=$lObjectCount"
}

proc ::PageAutoAnnotate::RunCurrent {} {
    ::PageAutoAnnotate::Run current
}

proc ::PageAutoAnnotate::RunAll {} {
    ::PageAutoAnnotate::Run all
}

proc ::PageAutoAnnotate::RunPageNumbers {} {
    set lDesign [::TitleBlockSync::GetActiveDesign]
    if {$lDesign == "NULL" || $lDesign == ""} {
        catch {tk_messageBox -type ok -icon warning -title "Page Number Reset" \
            -message "No active design was found."}
        return
    }

    set lStatus [DboState]
    set lPagePlan {}
    set lInvalidPages {}
    set lViewsIter "NULL"
    if {[catch {set lViewsIter [$lDesign NewViewsIter $lStatus $::IterDefs_SCHEMATICS]}] ||
        $lViewsIter == "NULL" || $lViewsIter == ""} {
        catch {$lStatus -delete}
        catch {tk_messageBox -type ok -icon error -title "Page Number Reset" \
            -message "The schematic pages could not be read. No changes were made."}
        return
    }

    set lView [$lViewsIter NextView $lStatus]
    while {$lView != "NULL" && $lView != ""} {
        set lSchematic "NULL"
        catch {set lSchematic [DboViewToDboSchematic $lView]}
        if {$lSchematic != "NULL" && $lSchematic != ""} {
            set lPagesIter "NULL"
            if {![catch {set lPagesIter [$lSchematic NewPagesIter $lStatus]}] &&
                $lPagesIter != "NULL" && $lPagesIter != ""} {
                set lPage [$lPagesIter NextPage $lStatus]
                while {$lPage != "NULL" && $lPage != ""} {
                    set lPageName [::TitleBlockSync::GetObjectString $lPage "GetName"]
                    set lTitleRecords [::PageAutoAnnotate::ReadPageTitleBlocks $lPage $lStatus]
                    if {[llength $lTitleRecords] == 0} {
                        lappend lInvalidPages "$lPageName (no title block)"
                    }
                    foreach lTitleRecord $lTitleRecords {
                        if {![lindex [lindex $lTitleRecord 1] 0] ||
                            ![lindex [lindex $lTitleRecord 2] 0]} {
                            lappend lInvalidPages "$lPageName (visible title-block properties unavailable)"
                            break
                        }
                    }
                    lappend lPagePlan [list $lSchematic $lPage $lPageName 0 0 $lTitleRecords]
                    set lPage [$lPagesIter NextPage $lStatus]
                }
                catch {delete_DboSchematicPagesIter $lPagesIter}
            }
        }
        set lView [$lViewsIter NextView $lStatus]
    }
    catch {delete_DboLibViewsIter $lViewsIter}

    array set lNoComponentRecords {}
    if {[llength $lInvalidPages] == 0} {
        set lPagePlan [::PageAutoAnnotate::ResolveNamedPageOrder \
            $lPagePlan lNoComponentRecords lInvalidPages]
    }
    if {[llength $lPagePlan] == 0 || [llength $lInvalidPages] > 0} {
        catch {$lStatus -delete}
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
        catch {$lStatus -delete}
        puts "Page number reset: cancelled."
        return
    }

    set lError [::PageAutoAnnotate::ApplyPageNumbers $lPagePlan [llength $lPagePlan]]
    if {$lError != ""} {
        set lRestoreFailures [::PageAutoAnnotate::RestorePageNumbers $lPagePlan]
        catch {$lStatus -delete}
        catch {Menu "View::Zoom::Redraw"}
        catch {tk_messageBox -type ok -icon error -title "Page Number Reset" \
            -message "$lError\n\nThe script attempted to restore the original page properties.\nRestore failures: $lRestoreFailures"}
        puts "Page number reset failed: $lError; restore-failures=$lRestoreFailures"
        return
    }

    catch {$lStatus -delete}
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

namespace eval ::SelectedPinNetExport {}

proc ::SelectedPinNetExport::Enabler {} {
    return [::OrCADQuickTools::HasSelectedPart]
}

proc ::SelectedPinNetExport::EscapeCSV {pValue} {
    set lEscaped [string map [list "\"" "\"\""] $pValue]
    return "\"$lEscaped\""
}

proc ::SelectedPinNetExport::GetObjectString {pObject pMethod} {
    set lValueCString [DboTclHelper_sMakeCString]
    if {[catch {$pObject $pMethod $lValueCString}]} {
        return ""
    }
    return [DboTclHelper_sGetConstCharPtr $lValueCString]
}

proc ::SelectedPinNetExport::GetPageName {pPage} {
    if {$pPage == "NULL" || $pPage == ""} {
        return ""
    }
    return [::SelectedPinNetExport::GetObjectString $pPage "GetName"]
}

proc ::SelectedPinNetExport::GetNetName {pPin pStatus} {
    set lNet "NULL"
    catch {set lNet [$pPin GetNet $pStatus]}
    if {$lNet != "NULL" && $lNet != ""} {
        set lNetName [::SelectedPinNetExport::GetObjectString $lNet "GetNetName"]
        if {$lNetName != ""} {
            return $lNetName
        }
    }

    # A wire can carry the resolved name in older Capture 16.6 designs even
    # when DboPortInst::GetNet does not return a net object.
    set lWire "NULL"
    catch {set lWire [$pPin GetWire $pStatus]}
    if {$lWire != "NULL" && $lWire != ""} {
        set lNetName [::SelectedPinNetExport::GetObjectString $lWire "GetNetName"]
        if {$lNetName != ""} {
            return $lNetName
        }
    }
    return ""
}

proc ::SelectedPinNetExport::GetDefaultLocation {} {
    set lDirectory [pwd]
    set lBaseName "Selected_Pin_Net"

    set lDesign "NULL"
    catch {set lDesign [GetActivePMDesign]}
    if {$lDesign != "NULL" && $lDesign != ""} {
        set lDesignName [::SelectedPinNetExport::GetObjectString $lDesign "GetName"]
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
    catch {wm withdraw .}
    set lOutputFile [tk_getSaveFile \
        -title "Export Selected Part Pin-Net Table" \
        -initialdir $lInitialDirectory \
        -initialfile $lInitialFile \
        -defaultextension ".xlsx" \
        -filetypes [list [list "Excel Workbook" ".xlsx"] [list "All Files" "*"]]]
    return $lOutputFile
}

proc ::SelectedPinNetExport::Run {} {

    if {![llength [info commands ::OrCADPinNetXlsx::WriteWorkbook]]} {
        error "The embedded XLSX module is missing; reload the complete OrCADQuickTools.tcl."
    }
    if {[catch {set lSelectedObjects [GetSelectedObjects]} lSelectionError]} {
        puts "Pin-net export: cannot read the current selection: $lSelectionError"
        return
    }

    set lPage "NULL"
    catch {set lPage [GetActivePage]}
    set lPageName [::SelectedPinNetExport::GetPageName $lPage]
    set lStatus [DboState]
    set lRows {}
    set lPartCount 0
    set lPinCount 0
    set lSkipped 0
    set lFailed 0
    array set lSeen {}

    foreach lObject $lSelectedObjects {
        if {![::OrCADQuickTools::IsPlacedPart $lObject]} {
            incr lSkipped
            continue
        }
        if {[info exists lSeen($lObject)]} {
            continue
        }
        set lSeen($lObject) 1

        set lReference [::SelectedPinNetExport::GetObjectString $lObject "GetReference"]
        set lValue [::SelectedPinNetExport::GetObjectString $lObject "GetPartValue"]
        if {$lReference == ""} {
            incr lFailed
            continue
        }

        set lPinsIter "NULL"
        if {[catch {set lPinsIter [$lObject NewPinsIter $lStatus]}] ||
            $lPinsIter == "NULL" || $lPinsIter == ""} {
            incr lFailed
            continue
        }

        incr lPartCount
        set lPin [$lPinsIter NextPin $lStatus]
        while {$lPin != "NULL"} {
            set lPinNumber [::SelectedPinNetExport::GetObjectString $lPin "GetPinNumber"]
            set lPinName [::SelectedPinNetExport::GetObjectString $lPin "GetPinName"]
            set lNetName [::SelectedPinNetExport::GetNetName $lPin $lStatus]
            if {$lNetName == ""} {
                set lConnection "Unconnected"
            } else {
                set lConnection "Connected"
            }
            lappend lRows [list $lPageName $lReference $lValue $lPinNumber $lPinName $lNetName $lConnection]
            incr lPinCount
            set lPin [$lPinsIter NextPin $lStatus]
        }
        catch {delete_DboPartInstPinsIter $lPinsIter}
    }

    catch {$lStatus -delete}
    if {$lPinCount == 0} {
        catch {tk_messageBox -type ok -icon warning -title "Excel Export" \
            -message "No pins were found on the selected schematic parts."}
        puts "Pin-net export: no pins found; selected-parts=$lPartCount, skipped=$lSkipped, failed=$lFailed"
        return
    }

    set lOutputFile [::SelectedPinNetExport::ChooseOutputFile]
    if {$lOutputFile == ""} {
        puts "Pin-net export: cancelled."
        return
    }
    if {![string equal -nocase [file extension $lOutputFile] ".xlsx"]} {
        append lOutputFile ".xlsx"
    }

    set lLogFile [file join $::env(TEMP) "OrCADPinNetExport.log"]
    set lExportResult [catch {
        ::OrCADPinNetXlsx::WriteWorkbook $lOutputFile $lRows
    } lExportMessage]

    if {$lExportResult != 0 || ![file exists $lOutputFile]} {
        catch {
            set lLogChannel [open $lLogFile "w"]
            fconfigure $lLogChannel -encoding utf-8 -translation lf
            puts $lLogChannel "OrCAD pure-Tcl XLSX export failed"
            puts $lLogChannel "Output: $lOutputFile"
            puts $lLogChannel "Parts: $lPartCount"
            puts $lLogChannel "Pins: $lPinCount"
            puts $lLogChannel "Error: $lExportMessage"
            close $lLogChannel
        }
        catch {tk_messageBox -type ok -icon error -title "Excel Export" \
            -message "Excel workbook export failed.\n\n$lExportMessage\n\nDiagnostic log:\n$lLogFile"}
        puts "Pin-net export: pure-Tcl writer failed: $lExportMessage; log=$lLogFile"
        return
    }
    catch {file delete -force $lLogFile}

    catch {tk_messageBox -type ok -icon info -title "Excel Export" \
        -message "Export complete.\n\nParts: $lPartCount\nPins: $lPinCount\nFile: $lOutputFile"}
    puts "Pin-net export: parts=$lPartCount, pins=$lPinCount, skipped=$lSkipped, failed=$lFailed, file=$lOutputFile"
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
    foreach lItem [::QuickToolsHelp::ShortcutItems] {
        append lText "[lindex $lItem 0]    [lindex $lItem 1]\n"
    }
    append lText "\n\u5982\u9700\u540C\u65F6\u91CD\u7F6E\u9875\u7801\u548C\u6240\u6709\u4F4D\u53F7\uFF0C\u8BF7\u6309\u987A\u5E8F\u6267\u884C\uFF1A\n1. Alt+F10\n2. Alt+F9"
    append lText "\n\n\u9F20\u6807\u6EDA\u8F6E\uFF1A\u7ED8\u56FE\u533A\u76F4\u63A5\u7F29\u653E\uFF08\u65E0\u9700 Ctrl\uFF09\n\u6309\u4F4F\u53F3\u952E\u62D6\u52A8\uFF1A\u753B\u5E03\u8DDF\u968F\u9F20\u6807\u79FB\u52A8\uFF0C\u677E\u5F00\u505C\u6B62\nAccessories > \u5FEB\u6377\u5DE5\u5177 > \u9F20\u6807\u5BFC\u822A\u5F00\u5173"
    append lText "\n\nAlt+S\uFF1A\u5355\u9009\u4E00\u6839\u5BFC\u7EBF\uFF0C\u9F20\u6807\u505C\u5728\u7EBF\u4E0A\uFF0C\u6309\u4E0B\u5E76\u677E\u5F00\u5FEB\u6377\u952E\u3002\nAlt+F5\uFF1A\u9009\u4E2D\u8DE8\u9875\u7B26\u53F7\u672C\u4F53\uFF0C\u53EA\u5207\u6362\u56FE\u5F62\uFF0C\u4FDD\u7559\u7F51\u7EDC\u540D\u548C\u8FDE\u63A5\u70B9\u3002\n\u4FEE\u6539\u8BBE\u8BA1\u524D\u8BF7\u5907\u4EFD\uFF0C\u9996\u6B21\u8BF7\u5728\u526F\u672C\u6D4B\u8BD5\u3002\n\u8DE8\u9875\u66FF\u6362\u6062\u590D\u5931\u8D25\u65F6\u52FF\u4FDD\u5B58\uFF0C\u8BF7\u91CD\u5F00\u5907\u4EFD\u3002"
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
}
