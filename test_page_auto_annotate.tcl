# A pure Tcl mock of the Capture objects used by the bulk annotation action.
proc RegisterAction args {}
proc UnregisterAction args {}
proc Menu args {}
proc AddAccessoryMenu {group label callback} {lappend ::accessoryMenus [list $group $label $callback]}
proc DboSession args {}
proc DboState {} {return status}
proc status {method args} {return 1}
proc DboTclHelper_sMakeCString {args} {
    if {[llength $args]} {return [lindex $args 0]}
    set ::stringBuffer ""
    return outputBuffer
}
proc DboTclHelper_sGetConstCharPtr {value} {
    if {$value eq "outputBuffer"} {return $::stringBuffer}
    return $value
}
proc DboTclHelper_sGetCPointX {point} {return [lindex $point 0]}
proc DboTclHelper_sGetCPointY {point} {return [lindex $point 1]}
proc DboBaseObject_GetObjectType {object} {return 13}
proc DboViewToDboSchematic {view} {return schematic}
proc DboPartInstToDboPlacedInst {part} {return $part}
proc DboDesignOccurrencesIter {name design} {
    set ::iterPosition(occurrences) 0
    proc quickToolsOccurrencesIter {method args} {
        if {!$::occurrenceMode} {return NULL}
        incr ::iterPosition(occurrences)
        if {$::iterPosition(occurrences)==1} {return occ1}
        if {$::iterPosition(occurrences)==2} {return occ2}
        return NULL
    }
}
proc delete_DboLibViewsIter args {}
proc delete_DboSchematicPagesIter args {}
proc delete_DboPageTitleBlocksIter args {}
proc delete_DboPagePartInstsIter args {}
proc GetActivePage {} {return page1}
proc tk_messageBox {args} {
    set ::lastDialog [lindex $args [expr {[lsearch $args -message] + 1}]]
    set index [lsearch $args -type]
    if {$index >= 0 && [lindex $args [expr {$index+1}]] eq "okcancel"} {return ok}
    return ok
}
set ::DboSession_s_pDboSession session
set ::IterDefs_SCHEMATICS 1
array set ::pageNumbers {page1 28 page2 28}
array set ::pageCounts {page1 33 page2 33}
array set ::titleNumbers {page1 28 page2 28}
array set ::visibleNumbers {page1 28 page2 28}
array set ::visibleCounts {page1 33 page2 33}
array set ::references {part1 R20 part2 R50}
array set ::coordinates {part1 {50 20} part2 {40 20}}
array set ::pageNames {page1 {P01. Title} page2 {P02. Power}}
array set ::iterPosition {}
set ::failVisibleWrite 0
set ::silentlyIgnoreVisibleWrite 0
set ::checkPageFirst 1
set ::accessoryMenus {}
set ::occurrenceMode 0
set ::ignorePartSetReference 0
set ::referenceWrites 0
array set ::packageFor {part1 singlePackage part2 singlePackage}
array set ::unit {part1 {} part2 {}}
array set ::partsByPage {page1 part1 page2 part2}
proc singlePackage {method args} {if {$method eq "GetSize"} {return 1}; error $method}
proc dualPackage {method args} {if {$method eq "GetSize"} {return 2}; error $method}
proc otherDualPackage {method args} {if {$method eq "GetSize"} {return 2}; error $method}
array set ::occurrenceReferences {occ1 R20 occ2 R50}

proc session {method args} {if {$method eq "GetActiveDesign"} {return design}; error $method}
proc design {method args} {
    if {$method eq "NewViewsIter"} {set ::iterPosition(views) 0; return views}
    if {$method eq "DesignHasReusedSchematics"} {return 0}
    if {$method eq "DesignHasOccurrenceProperties"} {return $::occurrenceMode}
    if {$method eq "IsRootOccurrenceExisting"} {return 1}
    if {$method eq "GetRootOccurrence"} {return rootOccurrence}
    error $method
}
proc views {method args} {
    if {$method eq "NextView"} {
        incr ::iterPosition(views)
        if {$::iterPosition(views)==1} {return view}
        return NULL
    }
    error $method
}
proc schematic {method args} {
    if {$method eq "NewPagesIter"} {set ::iterPosition(pages) 0; return pages}
    if {$method eq "SetPageNumber"} {
        if {$::silentlyIgnoreInternalWrite && [lindex $args 0] eq "page2" &&
            [lindex $args 1] != $::pageNumbers(page2)} {
            set ::silentlyIgnoreInternalWrite 0
            return status
        }
        set ::pageNumbers([lindex $args 0]) [lindex $args 1]
        return status
    }
    error $method
}
proc pages {method args} {
    if {$method eq "NextPage"} {
        incr ::iterPosition(pages)
        if {$::iterPosition(pages)==1} {return page2}
        if {$::iterPosition(pages)==2} {return page1}
        return NULL
    }
    error $method
}
proc page1 {method args} {return [mockPage page1 $method $args]}
proc page2 {method args} {return [mockPage page2 $method $args]}
proc mockPage {page method args} {
    if {$method eq "GetName"} {return $::pageNames($page)}
    if {$method eq "GetPageNumber"} {return $::pageNumbers($page)}
    if {$method eq "NewTitleBlocksIter"} {set ::iterPosition(title$page) 0; return title$page}
    if {$method eq "NewPartInstsIter"} {set ::iterPosition(parts$page) 0; return parts$page}
    error $method
}
proc titlepage1 {method args} {return [mockTitleIter page1 $method]}
proc titlepage2 {method args} {return [mockTitleIter page2 $method]}
proc mockTitleIter {page method} {
    if {$method eq "NextTitleBlock"} {
        incr ::iterPosition(title$page)
        if {$::iterPosition(title$page)==1} {return block$page}
        return NULL
    }
    error $method
}
proc blockpage1 {method args} {return [mockTitle page1 $method $args]}
proc blockpage2 {method args} {return [mockTitle page2 $method $args]}
proc mockTitle {page method args} {
    if {$method eq "GetPageNumber"} {return $::titleNumbers($page)}
    if {$method eq "GetPageCount"} {return $::pageCounts($page)}
    if {$method eq "SetPageNumber"} {set ::titleNumbers($page) [lindex $args 0]; return status}
    if {$method eq "SetPageCount"} {
        set ::pageCounts($page) [lindex $args 0]
        return status
    }
    error $method
}
proc partspage1 {method args} {return [mockPartIter page1 $method]}
proc partspage2 {method args} {return [mockPartIter page2 $method]}
proc mockPartIter {page method} {
    if {$method eq "NextPartInst"} {
        set index [expr {[incr ::iterPosition(parts$page)] - 1}]
        if {$index >= [llength $::partsByPage($page)]} {return NULL}
        return [lindex $::partsByPage($page) $index]
    }
    error $method
}
proc part1 {method args} {return [mockPart part1 $method $args]}
proc part2 {method args} {return [mockPart part2 $method $args]}
proc mockPart {part method args} {
    if {$method eq "GetReference"} {return $::references($part)}
    if {$method eq "GetLocation"} {return $::coordinates($part)}
    if {$method eq "GetPackage"} {return $::packageFor($part)}
    if {$method eq "GetDeviceDesignator"} {set ::stringBuffer $::unit($part); return status}
    if {$method eq "SetReference"} {
        incr ::referenceWrites
        if {!$::ignorePartSetReference} {set ::references($part) [lindex $args 0]}
        if {[info exists ::failRefdes] && [lindex $args 0] eq $::failRefdes} {
            unset ::failRefdes
            error "Injected exception after writing a reference"
        }
        return status
    }
    error $method
}

source [file join [file dirname [info script]] OrCADQuickTools.tcl]
proc ::TitleBlockSync::GetObjectString {object method} {return $::pageNames($object)}
proc ::PageReferenceFix::GetReference {part} {return $::references($part)}
proc ::PageAutoAnnotate::ReadReferenceProperty {part} {
    if {[info exists ::occurrenceReferences($part)]} {
        return [list 1 $::occurrenceReferences($part)]
    }
    return [list 1 $::references($part)]
}
proc ::PageReferenceFix::GetCurrentPageNumber {page status} {return $::visibleNumbers($page)}
proc ::PageAutoAnnotate::ReadTitleProperty {block name} {
    set page [string range $block 5 end]
    if {$name eq "Page Number"} {return [list 1 $::visibleNumbers($page)]}
    if {$name eq "Page Count"} {return [list 1 $::visibleCounts($page)]}
    error "Unexpected title-block property $name"
}
proc ::TitleBlockSync::WriteProperty {block name value} {
    if {$name eq "Reference"} {
        if {[info exists ::occurrenceReferences($block)]} {
            set ::occurrenceReferences($block) $value
        } else {
            set ::references($block) $value
        }
        return 1
    }
    set page [string range $block 5 end]
    if {$::checkPageFirst && $name eq "Page Number" &&
        ($::references(part1) ne "R20" || $::references(part2) ne "R50")} {
        error "References were changed before page properties"
    }
    if {$::failVisibleWrite && $page eq "page2" && $name eq "Page Count"} {
        set ::failVisibleWrite 0
        return 0
    }
    if {$::silentlyIgnoreVisibleWrite && $page eq "page2" &&
        $name eq "Page Number" && $value ne $::visibleNumbers($page)} {
        set ::silentlyIgnoreVisibleWrite 0
        return 1
    }
    if {$name eq "Page Number"} {set ::visibleNumbers($page) $value; return 1}
    if {$name eq "Page Count"} {set ::visibleCounts($page) $value; return 1}
    error "Unexpected title-block property $name"
}
foreach pair {{P2 P10} {2 10} {Alpha Beta} {Sheet9 Sheet10}} {
    if {[::PageAutoAnnotate::CompareNaturalPageNames [lindex $pair 0] [lindex $pair 1]] >= 0} {
        error "Natural page-name order failed for $pair"
    }
}
if {[::PageAutoAnnotate::CompareNaturalPageNames P01 P1] != 0} {
    error "Equivalent page numbers should compare equal"
}
puts "PASS: natural name comparison"
if {[catch {::PageAutoAnnotate::RunPageNumbers} failure]} {error "RunPageNumbers crashed: $failure"}
if {$::references(part1) ne "R20" || $::references(part2) ne "R50"} {
    error "Page-number reset changed component references"
}
if {[catch {::PageAutoAnnotate::RunAll} failure]} {error "RunAll crashed: $failure"}
set ::checkPageFirst 0
if {$::pageNumbers(page1)!=28 || $::pageNumbers(page2)!=28 ||
    $::pageCounts(page1)!=33 || $::pageCounts(page2)!=33 ||
    $::titleNumbers(page1)!=28 || $::titleNumbers(page2)!=28 ||
    $::visibleNumbers(page1)!=1 || $::visibleNumbers(page2)!=2 ||
    $::visibleCounts(page1)!=2 || $::visibleCounts(page2)!=2 ||
    $::references(part1) ne "R101" || $::references(part2) ne "R201"} {
    error "Incorrect result: pages=[array get ::pageNumbers], counts=[array get ::pageCounts], refs=[array get ::references]"
}
puts "PASS: page numbers and all references are separate actions"

array set ::references {part1 R20 part2 R50}
::PageAutoAnnotate::RunCurrent
if {$::references(part1) ne "R101" || $::references(part2) ne "R50" ||
    $::visibleNumbers(page1)!=1 || $::visibleNumbers(page2)!=2} {
    error "Current-page action changed another page or its reference"
}
puts "PASS: current page leaves other pages untouched"

array set ::pageNumbers {page1 28 page2 28}
array set ::pageCounts {page1 33 page2 33}
array set ::titleNumbers {page1 28 page2 28}
array set ::visibleNumbers {page1 28 page2 28}
array set ::visibleCounts {page1 33 page2 33}
array set ::references {part1 R20 part2 R50}
array set ::pageNames {page1 {2. Power} page2 {10. Future}}
::PageAutoAnnotate::RunPageNumbers
::PageAutoAnnotate::RunAll
if {$::visibleNumbers(page1)!=1 || $::visibleNumbers(page2)!=2 ||
    $::references(part1) ne "R101" || $::references(part2) ne "R201"} {
    error "Bare-number page names were not ordered numerically"
}
puts "PASS: bare-number page names"

array set ::pageNumbers {page1 28 page2 28}
array set ::pageCounts {page1 33 page2 33}
array set ::titleNumbers {page1 28 page2 28}
array set ::visibleNumbers {page1 28 page2 28}
array set ::visibleCounts {page1 33 page2 33}
array set ::references {part1 R20 part2 R50}
array set ::pageNames {page1 {Beta} page2 {Alpha}}
::PageAutoAnnotate::RunPageNumbers
::PageAutoAnnotate::RunAll
if {$::visibleNumbers(page1)!=2 || $::visibleNumbers(page2)!=1 ||
    $::references(part1) ne "R201" || $::references(part2) ne "R101"} {
    error "Alphabetic page names were not ordered alphabetically"
}
puts "PASS: alphabetic page names"

array set ::pageNumbers {page1 28 page2 28}
array set ::pageCounts {page1 33 page2 33}
array set ::titleNumbers {page1 28 page2 28}
array set ::visibleNumbers {page1 28 page2 28}
array set ::visibleCounts {page1 33 page2 33}
array set ::references {part1 R20 part2 R50}
array set ::pageNames {page1 {P01. Title} page2 {P02. Power}}
set ::failVisibleWrite 1
::PageAutoAnnotate::RunPageNumbers
if {$::pageNumbers(page1)!=28 || $::pageNumbers(page2)!=28 ||
    $::visibleNumbers(page1)!=28 || $::visibleNumbers(page2)!=28 ||
    $::references(part1) ne "R20" || $::references(part2) ne "R50"} {
    error "Rollback failed: pages=[array get ::pageNumbers], refs=[array get ::references]"
}
puts "PASS: rollback after title-block failure"

array set ::pageNumbers {page1 28 page2 28}
array set ::pageCounts {page1 33 page2 33}
array set ::titleNumbers {page1 28 page2 28}
array set ::visibleNumbers {page1 28 page2 28}
array set ::visibleCounts {page1 33 page2 33}
array set ::references {part1 R20 part2 R50}
set ::silentlyIgnoreVisibleWrite 1
::PageAutoAnnotate::RunPageNumbers
if {$::visibleNumbers(page1)!=28 || $::visibleNumbers(page2)!=28 ||
    $::references(part1) ne "R20" || $::references(part2) ne "R50"} {
    error "Silent title-block write failure did not roll back"
}
puts "PASS: silent title-block write failure detected and rolled back"

array set ::pageNumbers {page1 28 page2 28}
array set ::pageCounts {page1 33 page2 33}
array set ::titleNumbers {page1 28 page2 28}
array set ::visibleNumbers {page1 28 page2 28}
array set ::visibleCounts {page1 33 page2 33}
array set ::references {part1 R20 part2 R50}
set ::pageNames(page2) {P1. Title}
::PageAutoAnnotate::RunPageNumbers
if {$::pageNumbers(page1)!=28 || $::pageNumbers(page2)!=28 ||
    $::references(part1) ne "R20" || $::references(part2) ne "R50"} {
    error "Ambiguous names should not alter the design"
}
puts "PASS: duplicate page-name number safely rejected"

proc occ1 {method args} {return [mockOccurrence occ1 part1 $method $args]}
proc occ2 {method args} {return [mockOccurrence occ2 part2 $method $args]}
proc mockOccurrence {occ part method args} {
    if {$method eq "GetPartInst"} {return $part}
    if {$method eq "GetDesignator"} {set ::stringBuffer $::unit($part); return status}
    if {$method eq "SetReference"} {
        set ::occurrenceReferences($occ) [lindex $args 0]
        return status
    }
    error $method
}
array set ::visibleNumbers {page1 28 page2 28}
array set ::visibleCounts {page1 33 page2 33}
array set ::references {part1 R20 part2 Q2203}
array set ::occurrenceReferences {occ1 R20 occ2 Q2203}
array set ::pageNames {page1 {P01. Title} page2 {P02. Power}}
set ::occurrenceMode 1
set ::ignorePartSetReference 1
::PageAutoAnnotate::RunPageNumbers
::PageAutoAnnotate::RunAll
if {$::references(part2) ne "Q201" || $::occurrenceReferences(occ2) ne "Q201" ||
    $::visibleNumbers(page2)!=2} {
    error "Occurrence reference was not updated: instances=[array get ::references], occurrences=[array get ::occurrenceReferences]"
}
puts "PASS: occurrence-visible reference and silent instance write"

set ::ignorePartSetReference 0
foreach failAt {R900000001 R201} {
    set ::occurrenceMode 0
    array set ::references {part1 R201 part2 R101}
    set ::failRefdes $failAt
    ::PageAutoAnnotate::RunAll
    if {[info exists ::failRefdes] || $::references(part1) ne "R201" || $::references(part2) ne "R101"} {
        error "Reference rollback failed after exception at $failAt: [array get ::references]"
    }
}
puts "PASS: partial temporary and final writes restore original references"

rename schematic nativeSchematic
proc schematic {method args} {
    if {$method eq "NewPagesIter"} {return NULL}
    return [eval [linsert $args 0 nativeSchematic $method]]
}
array set ::visibleNumbers {page1 31 page2 32}
::PageAutoAnnotate::RunAll
::PageAutoAnnotate::RunPageNumbers
if {$::visibleNumbers(page1) != 31 || $::visibleNumbers(page2) != 32 ||
    $::references(part1) ne "R201" || $::references(part2) ne "R101"} {
    error "Enumeration failure did not stop before writes"
}
rename schematic {}
rename nativeSchematic schematic
rename page2 nativePage2
proc page2 {method args} {
    if {$method eq "NewPartInstsIter"} {return ""}
    return [eval [linsert $args 0 nativePage2 $method]]
}
::PageAutoAnnotate::RunCurrent
::PageAutoAnnotate::RunAll
if {$::references(part1) ne "R201" || $::references(part2) ne "R101"} {
    error "A missing part iterator did not stop reannotation"
}
rename page2 {}
rename nativePage2 page2
puts "PASS: both page and placed-part enumeration failures block writes"

array set ::visibleNumbers {page1 1 page2 2}
set ::occurrenceMode 0
array set ::references {part1 R5 part2 R5}
set before $::referenceWrites
::PageAutoAnnotate::RunAll
if {$::referenceWrites != $before || [string first R5 $::lastDialog] < 0} {
    error "Distinct single-section parts sharing R5 were not rejected before any writes"
}

array set ::packageFor {part1 dualPackage part2 dualPackage}
array set ::unit {part1 A part2 B}
foreach original {{U1 U1} {U1A U1B}} expected {{U101 U101} {U101A U101B}} {
    array set ::references [list part1 [lindex $original 0] part2 [lindex $original 1]]
    ::PageAutoAnnotate::RunCurrent
    if {[list $::references(part1) $::references(part2)] ne $expected} {
        error "Current-page reannotation of $original produced [list $::references(part1) $::references(part2)]: $::lastDialog"
    }
    ::PageAutoAnnotate::RunAll
    if {[list $::references(part1) $::references(part2)] ne $expected} {
        error "Repeating design reannotation changed a verified package reference"
    }
}

set ::occurrenceMode 1
array set ::references {part1 U2 part2 U2}
array set ::occurrenceReferences {occ1 U1A occ2 U1B}
::PageAutoAnnotate::RunAll
if {[list $::references(part1) $::references(part2) $::occurrenceReferences(occ1) $::occurrenceReferences(occ2)]
    ne {U101 U101 U101A U101B}} {
    error "Occurrence suffixes were not preserved independently"
}
set ::occurrenceMode 0

foreach spec {
    {U1A U1A A A dualPackage}
    {U1A U1B A B otherDualPackage}
    {U1Z U1B A B dualPackage}
    {U? U? A B dualPackage}
} {
    foreach {refA refB unitA unitB pkgB} $spec break
    array set ::references [list part1 $refA part2 $refB]
    array set ::unit [list part1 $unitA part2 $unitB]
    set ::packageFor(part2) $pkgB
    set before $::referenceWrites
    ::PageAutoAnnotate::RunCurrent
    if {$::referenceWrites != $before || [string first "No changes were made" $::lastDialog] < 0} {
        error "Ambiguous multi-unit reference reached the write phase: $spec"
    }
}
puts "PASS: package and section verification keeps cross-page units together, preserves suffixes, and stops conflicting references"

array set ::partsByPage {page1 {part1 part2} page2 {}}
array set ::packageFor {part1 singlePackage part2 singlePackage}
array set ::references {part1 R? part2 R?}
::PageAutoAnnotate::RunCurrent
if {[lsort [list $::references(part1) $::references(part2)]] ne {R101 R102}} {
    error "Two confirmed single-unit R? parts on one page were not both numbered"
}
array set ::references {part1 TP101A part2 TP?}
::PageAutoAnnotate::RunCurrent
if {$::references(part1) ne "TP101A" || $::references(part2) ne "TP102" ||
    [string first "Skipped references: 1" $::lastDialog] < 0 ||
    [string first TP101A $::lastDialog] < 0} {
    error "A preserved suffix should reserve its number and be reported without stopping other parts"
}
array set ::references {part1 R? part2 R?}
set ::packageFor(part1) NULL
::PageAutoAnnotate::RunAll
if {$::references(part1) ne "R?" || $::references(part2) ne "R101" ||
    [string first "Package size could not be verified" $::lastDialog] < 0} {
    error "An unreadable package should preserve only the unnumbered part"
}
set ::partsByPage(page1) part1
set before $::referenceWrites
::PageAutoAnnotate::RunAll
if {$::referenceWrites != $before || [string first "No references were changed" $::lastDialog] < 0 ||
    [string first "Skipped references: 1" $::lastDialog] < 0} {
    error "All-skipped design should report that no references were changed"
}
array set ::partsByPage {page1 part1 page2 part2}
puts "PASS: unnumbered single units get distinct references; preserved references are reported and their numbers reserved"

rename ::TitleBlockSync::PromptDialog ::TitleBlockSync::NativePromptDialog
proc ::TitleBlockSync::PromptDialog {} {
    if {[::TitleBlockSync::PromptProjectName] ne ""} {error "Re-entry started a second project dialog"}
    return "project"
}
if {[::TitleBlockSync::PromptProjectName] ne "project" || $::TitleBlockSync::DialogOpen} {
    error "Prompt did not prevent re-entry or release its guard"
}
rename ::TitleBlockSync::PromptDialog {}
rename ::TitleBlockSync::NativePromptDialog ::TitleBlockSync::PromptDialog

unset ::IterDefs_SCHEMATICS
if {![catch {::QuickToolsDbo::SchematicMode} why] || [string first "schematic database iterator is unavailable" $why] < 0} {
    error "Missing Capture dependency lacked a diagnostic"
}
set ::IterDefs_SCHEMATICS 1
puts "PASS: project dialog re-entry and missing database API diagnostics"

::QuickToolsHelp::AddAccessoryMenus
if {[llength $::accessoryMenus] != 14} {
    error "Expected 12 shortcuts plus mouse navigation and part preview toggles, got [llength $::accessoryMenus]"
}
if {[lindex [lindex $::accessoryMenus end-1] 2] ne "::QuickToolsHelp::Invoke ::OrCADQuickTools::ToggleWheelZoom"} {
    error "Missing mouse navigation toggle menu callback"
}
if {[string first "\u9F20\u6807\u5BFC\u822A" [lindex [lindex $::accessoryMenus end-1] 1]] < 0} {
    error "Mouse navigation menu label missing"
}
if {[lindex [lindex $::accessoryMenus end] 2] ne "::QuickToolsHelp::Invoke ::PartPreview::Toggle"} {
    error "Missing read-only part preview menu callback"
}
if {[string first "\u6309\u4F4F\u53F3\u952E\u62D6\u52A8" [::QuickToolsHelp::ShortcutText]] < 0} {
    error "Right-drag pan help missing"
}
foreach lMenuItem [lrange $::accessoryMenus 0 11] {
    if {[lindex $lMenuItem 0] ne $::QuickToolsHelp::MenuName ||
        [string first "Alt+" [lindex $lMenuItem 1]] < 0} {
        error "Invalid Quick Tools menu item: $lMenuItem"
    }
}
set lExpectedHotkeys {Alt+F1 Alt+F2 Alt+F3 Alt+F5 Alt+F6 Alt+Shift+F6 Alt+F7 Alt+F8 Alt+F9 Alt+F10 Alt+R Alt+S}
set lMenuHotkeys {}
foreach lMenuItem [lrange $::accessoryMenus 0 11] {
    if {![regexp {((?:Ctrl\+)?Alt\+(?:Shift\+)?[A-Z][0-9]*)$} [lindex $lMenuItem 1] lHotkey]} {
        error "Missing shortcut at end of menu label: $lMenuItem"
    }
    lappend lMenuHotkeys $lHotkey
}
if {$lMenuHotkeys ne $lExpectedHotkeys} {
    error "Quick Tools menu order: expected $lExpectedHotkeys, got $lMenuHotkeys"
}
set lHelpHotkeys {}
foreach lLine [lrange [split [::QuickToolsHelp::ShortcutText] "\n"] 0 11] {
    if {![regexp {^((?:Ctrl\+)?Alt\+(?:Shift\+)?[A-Z][0-9]*)[ ]+} $lLine lMatch lHotkey]} {
        error "Missing shortcut at start of help line: $lLine"
    }
    lappend lHelpHotkeys $lHotkey
}
if {$lHelpHotkeys ne $lExpectedHotkeys} {
    error "Shortcut help order: expected $lExpectedHotkeys, got $lHelpHotkeys"
}
if {[string first "\u7ED9\u6240\u9009\u5668\u4EF6" [::QuickToolsHelp::ShortcutText]] < 0} {
    error "Shortcut help was not translated to Chinese"
}
puts "PASS: shortcut help menu entries"
