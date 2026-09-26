# A pure Tcl mock of the Capture objects used by the bulk annotation action.
proc RegisterAction args {}
proc UnregisterAction args {}
proc Menu args {}
proc AddAccessoryMenu {group label callback} {lappend ::accessoryMenus [list $group $label $callback]}
proc DboSession args {}
proc DboState {} {return status}
proc status {method args} {return 1}
proc DboTclHelper_sMakeCString {{value ""}} {return $value}
proc DboTclHelper_sGetConstCharPtr {value} {return $value}
proc DboTclHelper_sGetCPointX {point} {return [lindex $point 0]}
proc DboTclHelper_sGetCPointY {point} {return [lindex $point 1]}
proc DboBaseObject_GetObjectType {object} {return 13}
proc DboViewToDboSchematic {view} {return schematic}
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
        incr ::iterPosition(parts$page)
        if {$::iterPosition(parts$page)==1} {
            if {$page eq "page1"} {return part1}
            return part2
        }
        return NULL
    }
    error $method
}
proc part1 {method args} {return [mockPart part1 $method $args]}
proc part2 {method args} {return [mockPart part2 $method $args]}
proc mockPart {part method args} {
    if {$method eq "GetReference"} {return $::references($part)}
    if {$method eq "GetLocation"} {return $::coordinates($part)}
    if {$method eq "SetReference"} {
        if {!$::ignorePartSetReference} {set ::references($part) [lindex $args 0]}
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

::QuickToolsHelp::AddAccessoryMenus
if {[llength $::accessoryMenus] != 9} {
    error "Expected 9 Quick Tools menu items, got [llength $::accessoryMenus]"
}
foreach lMenuItem $::accessoryMenus {
    if {[lindex $lMenuItem 0] ne $::QuickToolsHelp::MenuName ||
        [string first "Alt+" [lindex $lMenuItem 1]] < 0} {
        error "Invalid Quick Tools menu item: $lMenuItem"
    }
}
if {[string first "\u7ED9\u6240\u9009\u5668\u4EF6" [::QuickToolsHelp::ShortcutText]] < 0} {
    error "Shortcut help was not translated to Chinese"
}
puts "PASS: shortcut help menu entries"
