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
proc ::DesignPinNetExport::Check {state stage} {
    if {![$state Succeeded]} {error "$stage failed (Capture status [$state Code]); export stopped, not silently truncated."}
}
proc ::DesignPinNetExport::Objects {owner create next destroy args} {
    set iterator ""; set state ""; set objects {}
    set code [catch {
        set state [DboState]
        set iterator [eval [linsert $args 0 $owner $create $state]]
        Check $state $create
        $state -delete; set state ""
        if {[Null $iterator]} {error "$create returned no iterator."}
        array set seen {}
        while {1} {
            set state [DboState]
            set object [$iterator $next $state]
            set end [expr {[Null $object] && ([$state Succeeded] || [$state Code]==1022)}]
            if {!$end} {Check $state $next}
            $state -delete; set state ""
            if {$end} {break}
            if {[info exists seen($object)]} {error "$next repeated an object; export stopped."}
            set seen($object) 1
            lappend objects $object
        }
    } message]
    if {$state ne ""} {catch {$state -delete}}
    if {![Null $iterator]} {catch {$destroy $iterator}}
    if {$code} {error $message}
    return $objects
}
proc ::DesignPinNetExport::String {object method} {
    set value ""; set status ""
    set code [catch {
        set value [DboTclHelper_sMakeCString]
        set status [$object $method $value]
        if {![Null $status] && [namespace which -command $status] ne ""} {Check $status $method}
        set result [DboTclHelper_sGetConstCharPtr $value]
    } message]
    if {$value ne "" && [llength [info commands DboTclHelper_sDeleteCString]]} {catch {DboTclHelper_sDeleteCString $value}}
    if {![Null $status]} {catch {$status -delete}}
    if {$code} {error "$method: $message"}
    return $result
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
                if {![$state Succeeded] && [$state Code]!=1021 && [$state Code]!=1043} {Check $state $method}
                set name ""
            } else {
                Check $state $method
                set name [String $object GetNetName]
                if {$name eq ""} {error "$method returned an unnamed connection"}
            }
        } message]
        catch {$state -delete}
        if {$code} {lappend failures $message} elseif {$name ne ""} {return $name}
    }
    if {[llength $failures]} {error "Cannot determine pin network: [join $failures {; }]"}
    return ""
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
    foreach view [Objects $design NewViewsIter NextView delete_DboLibViewsIter $::IterDefs_SCHEMATICS] {
        set schematic [DboViewToDboSchematic $view]
        if {[Null $schematic]} {error "Cannot read a schematic view; export stopped."}
        set schematicName [String $schematic GetName]
        foreach page [Objects $schematic NewPagesIter NextPage delete_DboSchematicPagesIter] {
            set pageName [String $page GetName]
            lappend pages [list "$schematicName / $pageName" $page]
        }
    }
    set rows {}; array set seenPages {}
    foreach pageRecord [lsort -dictionary -index 0 $pages] {
        foreach {pageName page} $pageRecord break
        if {[info exists seenPages($page)]} {continue}
        set seenPages($page) 1; incr stats(pages)
        set parts {}
        foreach part [Objects $page NewPartInstsIter NextPartInst delete_DboPagePartInstsIter] {
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
            if {[catch {String $part GetPartValue} value]} {error "$pageName / $reference: $value"}
            incr stats(parts)
            if {[catch {Objects $part NewPinsIter NextPin delete_DboPartInstPinsIter} pins]} {error "$pageName / $reference: $pins"}
            if {![llength $pins]} {incr stats(noPins)}
            foreach pin $pins {
                set number [String $pin GetPinNumber]
                if {$number eq ""} {error "$pageName / $reference contains a pin with no readable number; export stopped."}
                set pinName [String $pin GetPinName]
                if {[catch {NetName $pin} net]} {error "$pageName / $reference, pin $number: $net"}
                set connection Connected
                if {$net eq ""} {set connection Unconnected}
                # The optional eighth field prevents distinct placed units with
                # duplicate refs/value from being accidentally merged by XLSX.
                lappend rows [list $pageName $reference $value $number $pinName $net $connection [list $page $part]]
                incr stats(pins)
            }
        }
        puts "All-design pin-net export: pages=$stats(pages), placed-units=$stats(parts), pins=$stats(pins)"
    }
    return $rows
}
proc ::DesignPinNetExport::ChooseFile {design} {
    set directory [pwd]; set base Design
    if {![catch {String $design GetName} name] && $name ne ""} {
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
        puts "All-design pin-net export complete: pages=$stats(pages), placed-units=$stats(parts), pins=$stats(pins), zero-pin-units=$stats(noPins), file=$output"
        catch {tk_messageBox -type ok -icon info -title "All Design Pin-Net Export" \
            -message "Export complete.\n\nPages: $stats(pages)\nPlaced units: $stats(parts)\nPins: $stats(pins)\nUnits with no pins (no pin rows): $stats(noPins)\nFile: $output"}
    }
}
