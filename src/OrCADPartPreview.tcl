# Read-only part preview, Tcl 8.4. No polling, EXE, design writes or global
# pointer cleanup. Triggered by Capture's native OnLButtonUp completion event.
namespace eval ::PartPreview {
    foreach {name value} {Enabled 1 Initialized 0 Registered 0 Pending {} Busy 0 LastSignature {} LastError {}} {
        if {![info exists $name]} {variable $name $value}
    }
    set base $::env(TEMP)
    if {[info exists ::env(LOCALAPPDATA)]} {set base $::env(LOCALAPPDATA)}
    variable Preference [file join $base OrCADQuickTools part-preview.enabled]
}

# Extension point: label, effective-property aliases (in priority order),
# optional native string getter. Add organization-specific keys only locally.
proc ::PartPreview::Fields {} {
    return [list \
        [list "\u4F4D\u53F7" {Reference {Part Reference}} GetReference] \
        [list Value {Value} GetPartValue] \
        [list "\u5C01\u88C5" {{PCB Footprint} {PCB FOOTPRINT} Footprint} {}] \
        [list "\u63CF\u8FF0" {Description DESCRIPTION} {}] \
        [list "\u7269\u6599\u7F16\u7801" {{Part Number} Part_Number MPN {Manufacturer Part Number}} {}] \
        [list "\u5382\u5BB6" {Manufacturer MANUFACTURER MFR} {}]]
}

proc ::PartPreview::FreeString {pointer} {
    if {$pointer ne "" && [llength [info commands DboTclHelper_sDeleteCString]]} {
        catch {DboTclHelper_sDeleteCString $pointer}
    }
}

proc ::PartPreview::ReadString {object property {getter {}}} {
    set name ""; set value ""; set status ""; set text ""
    set code [catch {
        set value [DboTclHelper_sMakeCString]
        if {$getter eq ""} {
            set name [DboTclHelper_sMakeCString $property]
            set status [$object GetEffectivePropStringValue $name $value]
        } else {
            set status [$object $getter $value]
        }
        # Some string getters return void; effective-property reads return a
        # DboState. Failed states must not expose a partially filled buffer.
        set okay 1
        if {$status ne "" && $status ne "NULL"} {
            if {![catch {$status OK} result]} {set okay $result}
        }
        if {$okay} {set text [DboTclHelper_sGetConstCharPtr $value]}
    } message]
    FreeString $name
    FreeString $value
    if {$status ne "" && $status ne "NULL"} {catch {$status -delete}}
    if {$code} {return ""}
    return [string trim $text]
}

proc ::PartPreview::Clean {text} {
    set text [string map [list "\r" " " "\n" " " "\t" " "] $text]
    regsub -all {[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]} $text {} text
    if {[string length $text] > 1000} {set text "[string range $text 0 999]..."}
    return $text
}

proc ::PartPreview::Identity {} {
    if {![IsSchematicViewActive]} {return {}}
    set objects [GetSelectedObjects]
    if {[llength $objects] != 1} {return {}}
    set object [lindex $objects 0]
    set placed 13
    if {[info exists ::DboBaseObject_PLACED_INSTANCE]} {set placed $::DboBaseObject_PLACED_INSTANCE}
    if {[DboBaseObject_GetObjectType $object] != $placed} {return {}}
    set page [GetActivePage]
    if {$page eq "" || $page eq "NULL"} {return {}}
    set state [DboState]
    set code [catch {
        set id [$object GetId $state]
        if {![$state OK]} {error "Cannot read selected part ID"}
    } message]
    catch {$state -delete}
    if {$code} {error $message}
    return [list $page $object $id]
}

proc ::PartPreview::Emit {message} {
    # Preserve other tools' diagnostics. Never clear the log or change focus.
    puts $message
    if {[llength [info commands DboState_WriteToSessionLog]]} {
        set text ""
        catch {
            set text [DboTclHelper_sMakeCString $message]
            DboState_WriteToSessionLog $text
        }
        FreeString $text
    }
}

proc ::PartPreview::Display {} {
    variable LastSignature
    set identity [Identity]
    if {![llength $identity]} {set LastSignature ""; return}
    set object [lindex $identity 1]
    set lines {}
    foreach field [Fields] {
        foreach {label aliases getter} $field break
        set value ""
        foreach alias $aliases {
            set value [ReadString $object $alias]
            if {$value ne ""} {break}
        }
        if {$value eq "" && $getter ne ""} {set value [ReadString $object {} $getter]}
        if {$value ne ""} {lappend lines "$label\uFF1A[Clean $value]"}
    }
    if {![llength $lines]} {return}
    # Re-read selection rather than retaining a database pointer across idle
    # callbacks. Refuse output if a nested editor operation changed the target.
    if {[Identity] ne $identity} {return}
    set signature [list $identity $lines]
    if {$signature eq $LastSignature} {return}
    set message "----- \u5668\u4EF6\u53C2\u6570 -----\n[join $lines \n]\n--------------------"
    Emit $message
    set LastSignature $signature
}

proc ::PartPreview::Flush {} {
    variable Pending; variable Busy; variable Enabled; variable LastError
    set Pending ""
    if {!$Enabled || $Busy} {return}
    set Busy 1
    set code [catch {Display} message]
    set Busy 0
    if {$code} {
        if {$message ne $LastError} {catch {puts "Part preview: $message"}; set LastError $message}
    } else {set LastError ""}
}

proc ::PartPreview::NeedsCallback {command args} {
    variable Enabled; variable Busy
    return [expr {$Enabled && !$Busy && $command eq "OnLButtonUp"}]
}

proc ::PartPreview::OnCommand {command args} {
    variable Pending
    if {![NeedsCallback $command]} {return}
    # Do not read DB objects inside Capture's mouse handler. Collapse a burst
    # of callbacks into one current-selection read after the command completes.
    if {$Pending ne ""} {after cancel $Pending}
    set Pending [after idle ::PartPreview::Flush]
}

proc ::PartPreview::Toggle {} {
    variable Enabled; variable Preference; variable Pending; variable LastSignature
    set Enabled [expr {!$Enabled}]
    if {$Pending ne ""} {after cancel $Pending; set Pending ""}
    set LastSignature ""
    set f ""; set staging "$Preference.[pid]-[clock clicks].tmp"
    if {[catch {
        file mkdir [file dirname $Preference]
        set f [open $staging {WRONLY CREAT EXCL}]
        puts -nonewline $f $Enabled
        close $f; set f ""
        file rename -force $staging $Preference
    } message]} {
        if {$f ne ""} {catch {close $f}}
        catch {file delete $staging}
        puts "Part preview: preference could not be saved: $message"
    }
    if {$Enabled} {puts "\u5668\u4EF6\u53C2\u6570\u9884\u89C8\uFF1A\u5DF2\u5F00\u542F"} \
    else {puts "\u5668\u4EF6\u53C2\u6570\u9884\u89C8\uFF1A\u5DF2\u5173\u95ED"}
}

proc ::PartPreview::Initialize {} {
    variable Registered; variable Initialized; variable Preference; variable Enabled
    if {![llength [info commands RegisterAction]]} {return}
    if {!$Initialized} {
        set Initialized 1
        set f ""
        catch {
            if {[file exists $Preference]} {
                set f [open $Preference r]; set saved [string trim [read $f 16]]
                close $f; set f ""
                if {$saved eq "0" || $saved eq "1"} {set Enabled $saved}
            }
        }
        if {$f ne ""} {catch {close $f}}
    }
    if {!$Registered} {
        RegisterAction "_cdnOrSchViewCmdComplete" "::PartPreview::NeedsCallback" "" "::PartPreview::OnCommand" ""
        set Registered 1
    }
}
