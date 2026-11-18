# Tcl 8.4: read every schematic page of the current DSN. No selection changes,
# annotation, netlist regeneration, Excel automation or external processes.
namespace eval ::DesignPinNetExport {
    if {![info exists Busy]} {variable Busy 0}
}

proc ::DesignPinNetExport::Null {object} {expr {$object eq "" || $object eq "NULL"}}
proc ::DesignPinNetExport::Design {} {
    # Prefer the visible page's owner over a stale Project Manager selection.
    if {![catch {IsSchematicViewActive} active] && $active} {
        set page [GetActivePage]
        if {![Null $page]} {
            set lib [$page GetContainingLib]
            if {[llength [info commands DboLibToDboDesign]]} {return [DboLibToDboDesign $lib]}
            return $lib
        }
    }
    set design [GetActivePMDesign]
    if {[Null $design]} {error "Select a design (.dsn) or open a schematic page first."}
    return $design
}
proc ::DesignPinNetExport::Enabler {args} {
    variable Busy
    return [expr {!$Busy && ![catch {Design} design] && ![Null $design]}]
}
proc ::DesignPinNetExport::NetName {pin} {
    set failures {}
    foreach method {GetNet GetWire} {
        set state [DboState]
        set code [catch {
            set object [$pin $method $state]
            if {[Null $object]} {
                # Capture's orSMIDB_DLL.xml: 1021 = Object Not Found;
                # 1043 = not connected to any Net. Either can accompany a
                # NULL lookup for an unconnected pin. Still check GetWire:
                # absence in GetNet alone does NOT prove disconnection.
                # Accept these codes only for NULL network/wire lookups,
                # never for a returned object, iterator or property read.
                if {![$state Succeeded] && [$state Code]!=1021 && [$state Code]!=1043} {::QuickToolsDbo::Check $state $method}
                set name ""
            } else {
                ::QuickToolsDbo::Check $state $method
                set name [::QuickToolsDbo::String $object GetNetName]
                if {$name eq ""} {error "$method returned an unnamed connection"}
            }
        } message]
        catch {$state -delete}
        if {$code} {lappend failures $message} elseif {$name ne ""} {return $name}
    }
    if {[llength $failures]} {error "Cannot determine pin network: [join $failures {; }]"}
    return ""
}
proc ::DesignPinNetExport::PartRows {page pageName part reference} {
    set rows {}
    if {[catch {
        set value [::QuickToolsDbo::String $part GetPartValue]
        set pins [::QuickToolsDbo::Objects $part NewPinsIter NextPin delete_DboPartInstPinsIter]
        foreach pin $pins {
            set number [::QuickToolsDbo::String $pin GetPinNumber]
            if {$number eq ""} {error "A pin has no readable number."}
            set name [::QuickToolsDbo::String $pin GetPinName]
            if {[catch {NetName $pin} net]} {error "pin $number: $net"}
            set connection Connected
            if {$net eq ""} {set connection Unconnected}
            lappend rows [list $pageName $reference $value $number $name $net $connection [list $page $part]]
        }
    } message]} {error "$pageName / $reference: $message"}
    return $rows
}

proc ::DesignPinNetExport::Collect {design statsName} {
    upvar 1 $statsName stats
    array set stats {pages 0 parts 0 pins 0 noPins 0 skipped 0}
    if {[catch {$design DesignHasReusedSchematics} reused]} {
        error "Cannot verify whether this design reuses hierarchical pages; export stopped to avoid missing occurrences."
    }
    if {$reused} {
        error "This design reuses hierarchical schematics. A page-instance export would omit occurrence-specific references/nets; flattened occurrence export is not supported yet. No workbook was written."
    }
    set pages {}
    array set schematicNames {}
    foreach record [::QuickToolsDbo::SchematicPages $design] {
        foreach {schematic page} $record break
        if {![info exists schematicNames($schematic)]} {
            set schematicNames($schematic) [::QuickToolsDbo::String $schematic GetName]
        }
        set pageName [::QuickToolsDbo::String $page GetName]
        lappend pages [list "$schematicNames($schematic) / $pageName" $page]
    }
    set rows {}; array set seenPages {}
    foreach pageRecord [lsort -dictionary -index 0 $pages] {
        foreach {pageName page} $pageRecord break
        if {[info exists seenPages($page)]} {continue}
        set seenPages($page) 1; incr stats(pages)
        set parts {}
        foreach part [::QuickToolsDbo::Objects $page NewPartInstsIter NextPartInst delete_DboPagePartInstsIter] {
            set placed 13
            if {[info exists ::DboBaseObject_PLACED_INSTANCE]} {set placed $::DboBaseObject_PLACED_INSTANCE}
            if {[DboBaseObject_GetObjectType $part]!=$placed} {incr stats(skipped); continue}
            # Effective Reference first, matching current quick-tool behavior.
            set reference [::PageReferenceFix::GetReference $part]
            if {$reference eq ""} {error "A part on $pageName has no readable reference; export stopped."}
            lappend parts [list $reference $part]
        }
        foreach partRecord [lsort -dictionary -index 0 $parts] {
            foreach {reference part} $partRecord break
            incr stats(parts)
            set unitRows [PartRows $page $pageName $part $reference]
            if {![llength $unitRows]} {incr stats(noPins)}
            incr stats(pins) [llength $unitRows]
            foreach row $unitRows {lappend rows $row}
        }
        puts "All-design pin-net export: pages=$stats(pages), placed-units=$stats(parts), pins=$stats(pins)"
    }
    return $rows
}
proc ::DesignPinNetExport::ChooseFile {design} {
    set directory [pwd]; set base Design
    if {![catch {::QuickToolsDbo::String $design GetName} name] && $name ne ""} {
        if {[file isdirectory [file dirname $name]]} {set directory [file dirname $name]}
        set base [file rootname [file tail $name]]
    }
    set initial "${base}_All_Part_Pin_Net_[clock format [clock seconds] -format %Y%m%d_%H%M%S].xlsx"
    package require Tk
    return [tk_getSaveFile -title "Export All Design Parts Pin-Net Table" -initialdir $directory -initialfile $initial \
        -defaultextension .xlsx -filetypes [list [list {Excel Workbook} .xlsx] [list {All Files} *]]]
}
proc ::DesignPinNetExport::Run {args} {
    variable Busy
    if {$Busy} {return}
    set Busy 1; set output ""
    set code [catch {
        set design [Design]
        if {[Null $design]} {error "Select a design (.dsn) or open a schematic page first."}
        set output [ChooseFile $design]
        if {$output ne ""} {
            if {![string equal -nocase [file extension $output] .xlsx]} {append output .xlsx}
            puts "All-design pin-net export: reading every schematic page of the current DSN; no design changes."
            set rows [Collect $design stats]
            if {![llength $rows]} {error "No component pins found in this design. No workbook was written."}
            ::OrCADPinNetXlsx::WriteWorkbook $output $rows "All Design Parts Pin-Net Table"
        }
    } message]
    set Busy 0
    if {$code} {
        puts "All-design pin-net export FAILED: $message"
        catch {tk_messageBox -type ok -icon error -title "All Design Pin-Net Export" -message $message}
    } elseif {$output eq ""} {
        puts "All-design pin-net export: cancelled."
    } else {
        puts "All-design pin-net export complete: pages=$stats(pages), placed-units=$stats(parts), pins=$stats(pins), zero-pin-units=$stats(noPins), skipped=$stats(skipped), file=$output"
        catch {tk_messageBox -type ok -icon info -title "All Design Pin-Net Export" \
            -message "Export complete.\n\nPages: $stats(pages)\nPlaced units: $stats(parts)\nPins: $stats(pins)\nUnits with no pins (no pin rows): $stats(noPins)\nOther objects skipped: $stats(skipped)\nFile: $output"}
    }
}
