# Isolated Tcl 8.4 mocks: never load into Capture. No design writes allowed.
source [file join [file dirname [info script]] src OrCADQuickTools.core.tcl]
source [file join [file dirname [info script]] src OrCADDesignPinNetExport.tcl]
source [file join [file dirname [info script]] src OrCADPinNetXlsx.tcl]
proc assert {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message}}
set ::IterDefs_SCHEMATICS 7
set ::made 0; set ::deleted 0; set ::states 0; set ::stateDeleted 0
set ::strings 0; set ::stringDeleted 0; set ::fault {}; set ::reused 0
set ::messages {}; set ::active 1; set ::target {}; set ::eofCode 1022
set ::eofToken NULL
array set ::lookups {}
proc DboState {} {
    set name state[incr ::states]; set ::codes($name) 0
    interp alias {} $name {} status $name; return $name
}
proc status {name method args} {
    switch -- $method {
        Succeeded {return [expr {$::codes($name)==0}]}
        Code {return $::codes($name)}
        -delete {unset ::codes($name); rename $name {}; incr ::stateDeleted}
        default {error $method}
    }
}
proc DboTclHelper_sMakeCString {args} {set name str[incr ::strings]; set ::text($name) [lindex $args 0]; return $name}
proc DboTclHelper_sGetConstCharPtr {name} {return $::text($name)}
proc DboTclHelper_sDeleteCString {name} {unset ::text($name); incr ::stringDeleted}
proc IsSchematicViewActive {} {return $::active}
proc GetActivePage {} {return page2}
proc GetActivePMDesign {} {return wrongDesign}
proc DboLibToDboDesign {lib} {assert {$lib eq "design"} "Wrong page owner"; return design}
proc DboViewToDboSchematic {view} {return $view}
proc DboBaseObject_GetObjectType {object} {if {$object eq "power"} {return 50}; return 13}
proc ::PageReferenceFix::GetReference {object} {return $::refs($object)}
proc iterator {items method state} {
    set name iterator[incr ::made]; set ::items($name) $items; set ::next($name) $method
    interp alias {} $name {} iterate $name; return $name
}
proc iterate {name method state} {
    assert {$method eq $::next($name)} "Wrong iterator next method"
    if {$::fault eq $method} {set ::codes($state) 99; return NULL}
    if {![llength $::items($name)]} {set ::codes($state) $::eofCode; return $::eofToken}
    set value [lindex $::items($name) 0]; set ::items($name) [lrange $::items($name) 1 end]; return $value
}
proc destroy {name} {unset ::items($name) ::next($name); rename $name {}; incr ::deleted}
foreach destructor {delete_DboLibViewsIter delete_DboSchematicPagesIter delete_DboPagePartInstsIter delete_DboPartInstPinsIter} {
    interp alias {} $destructor {} destroy
}
proc design {method args} {
    switch -- $method {
        GetName {set ::text([lindex $args 0]) /mock/Design.dsn; return}
        DesignHasReusedSchematics {return $::reused}
        NewViewsIter {return [iterator {schemaB schemaA} NextView [lindex $args 0]]}
        default {error "Unexpected design write/API: $method"}
    }
}
proc schemaA {method args} {
    if {$method eq "GetName"} {set ::text([lindex $args 0]) MAIN; return}
    if {$method eq "NewPagesIter"} {return [iterator {page10 page2 emptyPage} NextPage [lindex $args 0]]}
    error $method
}
proc schemaB {method args} {
    if {$method eq "GetName"} {set ::text([lindex $args 0]) SECOND; return}
    if {$method eq "NewPagesIter"} {return [iterator pageOther NextPage [lindex $args 0]]}
    error $method
}
array set ::names {page2 {P02. MCU} page10 {P10. Power} pageOther {P02. MCU} emptyPage {P03. Empty}}
array set ::parts {page2 {u1b u1 zero power} page10 r1 pageOther c1 emptyPage {}}
array set ::refs {u1 U301 u1b U301 zero TP1 r1 R1001 c1 C201}
array set ::pins {u1 {pin10 pin2 pin1} u1b pin3 zero {} r1 {floating wirePin} c1 {ball10 ball2}}
foreach page {page2 page10 pageOther emptyPage} {interp alias {} $page {} pageCommand $page}
proc pageCommand {page method args} {
    switch -- $method {
        GetContainingLib {return design}
        GetName {set ::text([lindex $args 0]) $::names($page); return}
        NewPartInstsIter {return [iterator $::parts($page) NextPartInst [lindex $args 0]]}
        default {error "Unexpected page write/API: $method"}
    }
}
foreach part {u1 u1b zero r1 c1} {interp alias {} $part {} partCommand $part}
proc partCommand {part method args} {
    switch -- $method {
        GetPartValue {
            set value MCU
            if {$part eq "c1"} {set value {NC,100nF}}
            if {$part eq "r1"} {set value {=SUM(1,2)}}
            set ::text([lindex $args 0]) $value; return
        }
        NewPinsIter {return [iterator $::pins($part) NextPin [lindex $args 0]]}
        default {error "Unexpected component write/API: $method"}
    }
}
array set ::numbers {pin10 10 pin2 2 pin1 1 pin3 3 floating 1 wirePin 2 ball10 A10 ball2 A2}
foreach pin [array names ::numbers] {interp alias {} $pin {} pinCommand $pin}
proc pinCommand {pin method args} {
    switch -- $method {
        GetPinNumber {set ::text([lindex $args 0]) $::numbers($pin); return}
        GetPinName {set ::text([lindex $args 0]) "PIN_$pin"; return}
        GetNet - GetWire {
            set state [lindex $args 0]
            if {$::fault eq "net"} {set ::codes($state) 99; return NULL}
            if {[info exists ::lookups($pin,$method)]} {
                foreach {object status} $::lookups($pin,$method) break
                if {$object eq "throw"} {error "Simulated lookup exception"}
                set ::codes($state) $status; return $object
            }
            if {$pin eq "floating" || ($pin eq "wirePin" && $method eq "GetNet")} {
                set ::codes($state) 1043
                if {$method eq "GetNet"} {set ::codes($state) 1021}
                return NULL
            }
            return net
        }
        default {error "Unexpected pin write/API: $method"}
    }
}
proc net {method value} {assert {$method eq "GetNetName"} "Unexpected net API"; set ::text($value) {NET<&>}; return}
proc tk_messageBox args {lappend ::messages $args; return ok}
rename ::DesignPinNetExport::ChooseFile ::DesignPinNetExport::NativeChooseFile
proc ::DesignPinNetExport::ChooseFile {design} {return $::target}
proc GetSelectedObjects {} {return {u1 u1b zero power}}
rename ::SelectedPinNetExport::ChooseOutputFile ::SelectedPinNetExport::NativeChooseOutputFile
proc ::SelectedPinNetExport::ChooseOutputFile {} {return $::target}

set madeBefore $::made
::SelectedPinNetExport::Execute
assert {$::made == $madeBefore} "Cancelled selected export still walked pins"
set ::target mock-selected.xlsx
rename ::OrCADPinNetXlsx::WriteWorkbook ::OrCADPinNetXlsx::NativeWriteWorkbook
proc ::OrCADPinNetXlsx::WriteWorkbook {file rows args} {set ::selectedRows $rows}
set ::eofToken ""
::SelectedPinNetExport::Execute
assert {[llength $::selectedRows] == 4} "Selected export did not finish at empty iterator EOF"
set selectedSheet [::OrCADPinNetXlsx::BuildSheet $::selectedRows]
assert {[regexp -all {>U301</t>} $selectedSheet] == 2} "Selected export merged different placed units with one reference"
set ::fault NextPin
unset ::selectedRows
assert {[catch {::SelectedPinNetExport::Execute} why] && ![info exists ::selectedRows]} "Failed read still exported selected pins"
set ::fault {}; set ::target {}; set ::eofToken NULL
rename ::OrCADPinNetXlsx::WriteWorkbook {}
rename ::OrCADPinNetXlsx::NativeWriteWorkbook ::OrCADPinNetXlsx::WriteWorkbook
puts "PASS: selected export cancels before reads, handles empty EOF, separates units, and aborts on iterator failure"

assert {[::DesignPinNetExport::Design] eq "design" && [::DesignPinNetExport::Enabler]} "Visible page did not override stale PM design"
set rows [::DesignPinNetExport::Collect design stats]
assert {$stats(pages)==4 && $stats(parts)==5 && $stats(pins)==8 && $stats(noPins)==1 && $stats(skipped)==1} "Counts incomplete"
assert {[llength $rows]==8 && [string first {MAIN / P02. MCU} [lindex [lindex $rows 0] 0]]==0} "Pages not naturally ordered"
assert {[lindex [lindex $rows end] 0] eq "SECOND / P02. MCU"} "Same page name in another schematic lost"
assert {[lsearch -exact [lindex $rows end] {NC,100nF}]>=0} "NC component was silently filtered"
set connected 0; set unconnected 0
foreach row $rows {if {[lindex $row 6] eq "Connected"} {incr connected} else {incr unconnected}}
assert {$connected==7 && $unconnected==1} "Connection or wire fallback incorrect"
assert {$::made==$::deleted && $::states==$::stateDeleted && $::strings==$::stringDeleted} "Read resources leaked"
set sheet [::OrCADPinNetXlsx::BuildSheet $rows {All Design Parts Pin-Net Table}]
assert {[string first {All Design Parts Pin-Net Table} $sheet]>=0} "All-design title missing"
assert {[regexp -all {>Reference</t>} $sheet]==4} "Distinct units sharing reference were merged"
assert {[string first {>1</t>} $sheet] < [string first {>2</t>} $sheet] && [string first {>2</t>} $sheet] < [string first {>10</t>} $sheet]} "Pin numeric order changed"
assert {[string first {>A2</t>} $sheet] < [string first {>A10</t>} $sheet]} "Alphanumeric pin order changed"
assert {[string first {NET&lt;&amp;&gt;} $sheet]>=0 && [string first {<f>} $sheet]<0} "Escaping or literal formula text incorrect"

# A NULL network lookup may report Object Not Found (1021), including MARK
# pins. Retain the pin only after both lookups indicate ordinary absence.
foreach absenceCodes {{1021 1021} {1021 1043} {1021 0} {0 1021} {1043 1021}} {
    set ::lookups(floating,GetNet) [list NULL [lindex $absenceCodes 0]]
    set ::lookups(floating,GetWire) [list NULL [lindex $absenceCodes 1]]
    assert {[::DesignPinNetExport::NetName floating] eq ""} "NULL absence status combination rejected"
}
set ::refs(r1) MARK201
set markRows [::DesignPinNetExport::Collect design markStats]
set found 0
foreach row $markRows {
    if {[lindex $row 1] eq "MARK201" && [lindex $row 3] eq "1"} {
        assert {[lindex $row 5] eq "" && [lindex $row 6] eq "Unconnected"} "MARK pin was not retained as unconnected"
        incr found
    }
}
assert {$found==1 && [llength $markRows]==8} "Unconnected MARK pin was silently skipped"
set ::refs(r1) R1001
set ::lookups(floating,GetNet) {NULL 1021}
set ::lookups(floating,GetWire) {net 0}
assert {[::DesignPinNetExport::NetName floating] eq {NET<&>}} "1021 GetNet prevented valid wire fallback"
foreach pair {{{net 1021} {NULL 1043}} {{NULL 99} {NULL 1043}} {{NULL 1021} {NULL 99}} {{NULL 1021} {throw 0}}} {
    set ::lookups(floating,GetNet) [lindex $pair 0]
    set ::lookups(floating,GetWire) [lindex $pair 1]
    assert {[catch {::DesignPinNetExport::NetName floating} why]} "Invalid connection lookup was treated as unconnected"
    assert {$::states==$::stateDeleted && $::strings==$::stringDeleted} "Connection lookup failure leaked resources"
}
array unset ::lookups
set ::eofCode 1021
assert {[catch {::DesignPinNetExport::Collect design errorStats} why]} "1021 iterator failure was mistaken for EOF"
assert {$::made==$::deleted && $::states==$::stateDeleted && $::strings==$::stringDeleted} "1021 iterator failure leaked resources"
set ::eofCode 1022

# End-of-iteration is accepted only for NULL, without masking real errors.
set ::eofCode 0
assert {[llength [::DesignPinNetExport::Collect design repeatStats]]==8} "Successful NULL EOF unsupported"
set ::eofCode 1022
foreach fault {NextView NextPage NextPartInst NextPin net} {
    set ::fault $fault
    assert {[catch {::DesignPinNetExport::Collect design errorStats} why]} "Read failure was hidden"
    assert {$::made==$::deleted && $::states==$::stateDeleted && $::strings==$::stringDeleted} "Failure leaked read resources"
}
set ::fault {}; set ::reused 1
assert {[catch {::DesignPinNetExport::Collect design errorStats} why] && [string first hierarchical $why]>=0} "Repeated hierarchy was exported as misleading complete data"
set ::reused 0
set count $::made
::DesignPinNetExport::Run
assert {$::made==$count && !$::DesignPinNetExport::Busy} "Cancel traversed design or leaked busy"
set ::DesignPinNetExport::Busy 1
::DesignPinNetExport::Run
assert {$::made==$count} "Repeated request dispatched twice"
set ::DesignPinNetExport::Busy 0
if {[info exists ::env(ORCAD_DESIGN_EXPORT_TEST_XLSX)]} {
    set ::target $::env(ORCAD_DESIGN_EXPORT_TEST_XLSX)
    set ::fault NextPin
    ::DesignPinNetExport::Run
    assert {![file exists $::target] && !$::DesignPinNetExport::Busy} "Incomplete export wrote a workbook or leaked busy"
    set ::fault {}
    ::DesignPinNetExport::Run
    assert {[file exists $::target] && !$::DesignPinNetExport::Busy} "Full-design workbook not created"
}
puts "PASS: all pages/schematics, visible design, natural order, NC and unconnected MARK pins, NULL 1021/1043/0, wire fallback, invalid lookup/iterator errors, duplicate refs, no-pin counts, cleanup, cancellation, repeat guard; no design writes"
