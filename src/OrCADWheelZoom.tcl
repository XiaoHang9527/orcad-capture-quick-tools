# Tcl 8.4 compatible; optional companion for OrCADWheelZoom.exe.
# Native view identity is checked here, never inferred from page/title text.
namespace eval ::OrCADWheel {
    variable Directory [file dirname [info script]]
    if {![info exists Enabled]} { variable Enabled 0 }
    if {![info exists Timer]} { variable Timer "" }
    if {![info exists CheckTimer]} {variable CheckTimer ""}
    if {![info exists Running]} {variable Running 0}
    foreach {name initial} {WriteFailures 0 HealthFailures 0 Recovering 0 Recoveries 0 RecoveryWindow 0 NextRecovery 0} {
        if {![info exists $name]} {variable $name $initial}
    }
    if {![info exists StateFile]} {
        variable StateFile [file join $::env(TEMP) OrCADWheelZoom-[pid]-[clock clicks].state]
    }
    variable LogFile [file join $::env(TEMP) OrCADWheelZoom-[pid].log]
    variable ControllerLogFile [file join $::env(TEMP) OrCADWheelZoom-[pid]-controller.log]
    set base $::env(TEMP)
    if {[info exists ::env(LOCALAPPDATA)]} {set base $::env(LOCALAPPDATA)}
    variable Preference [file join $base OrCADQuickTools wheel-zoom.enabled]
}

proc ::OrCADWheel::Log {message} {
    variable ControllerLogFile
    set f ""
    catch {
        set f [open $ControllerLogFile a]
        fconfigure $f -encoding utf-8
        puts $f "[clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S}] $message"
        close $f
        set f ""
    }
    if {$f ne ""} {catch {close $f}}
}

# Enabled is the user's intent. Transient runtime faults must not silently turn
# it off. Recovery is single-instance and limited to three attempts per minute.
proc ::OrCADWheel::Recover {reason} {
    variable Enabled; variable Running; variable Recovering
    variable Recoveries; variable RecoveryWindow; variable NextRecovery
    variable Directory; variable StateFile; variable CheckTimer; variable HealthFailures
    if {!$Enabled || $CheckTimer ne ""} {return}
    set now [clock seconds]
    if {$now < $NextRecovery} {return}
    if {$now - $RecoveryWindow >= 60} {set RecoveryWindow $now; set Recoveries 0}
    if {$Recoveries >= 3} {
        set NextRecovery [expr {$RecoveryWindow + 60}]
        Log "Recovery throttled until $NextRecovery; reason=$reason"
        return
    }
    incr Recoveries
    set NextRecovery [expr {$now + 10}]
    set Running 0; set Recovering 1; set HealthFailures 0
    Log "Recovery attempt=$Recoveries; reason=$reason"
    set helper [file join $Directory OrCADWheelZoom.exe]
    if {[catch {
        # Stop waits for the previous helper's single-instance mutex to release.
        # If it cannot stop, do not launch another listener or kill Capture.
        exec $helper --stop [pid]
        ::OrCADWheel::WriteText "$StateFile.status" starting
        ::OrCADWheel::WriteText $StateFile "hover 0"
        exec $helper --run [pid] $StateFile &
    } err]} {
        set Recovering 0
        Log "Recovery could not launch: $err; retry remains enabled"
        return
    }
    set CheckTimer [after 200 [list ::OrCADWheel::CheckStarted 0 0]]
}

proc ::OrCADWheel::ReadText {path} {
    set f [open $path r]
    if {[catch {set result [read $f]; close $f} err]} {catch {close $f}; error $err}
    return [string trim $result]
}

proc ::OrCADWheel::WriteText {path text} {
    set f [open $path w]
    if {[catch {puts $f $text; close $f} err]} {catch {close $f}; error $err}
}

proc ::OrCADWheel::Remember {value} {
    variable Preference
    file mkdir [file dirname $Preference]
    ::OrCADWheel::WriteText $Preference $value
}

proc ::OrCADWheel::Fail {message notify} {
    variable LogFile
    Log "Startup failed: $message"
    catch {::OrCADWheel::Disable}
    puts "Wheel zoom NOT running: $message; log=$LogFile"
    if {$notify} {
        catch {tk_messageBox -icon error -type ok -title "Wheel Zoom" \
            -message "\u6EDA\u8F6E\u7F29\u653E\u672A\u80FD\u542F\u52A8\uFF1A\n$message\n\n\u65E5\u5FD7\uFF1A\n$LogFile"}
    }
}

proc ::OrCADWheel::CheckStarted {attempt notify} {
    variable Enabled
    variable Running
    variable CheckTimer
    variable StateFile
    variable Recovering
    variable HealthFailures
    set CheckTimer ""
    if {!$Enabled} {return}
    set status ""
    catch {set status [::OrCADWheel::ReadText "$StateFile.status"]}
    if {[string match "running*" $status]} {
        if {$Recovering} {Log "Recovery acknowledged; mouse navigation running"}
        set Recovering 0; set HealthFailures 0
        set Running 1
        puts "Mouse navigation helper running: plain wheel zoom and direct right-button grab pan (no middle-button mode)."
        if {$notify} {
            catch {::OrCADWheel::Remember 1}
        }
        return
    }
    if {[string match "error:*" $status] || $status == "stopped" || $attempt >= 25} {
        if {$status == "" || $status == "starting"} {set status "Helper startup timed out."}
        if {$Recovering} {
            set Recovering 0; set Running 0
            Log "Recovery startup failed: $status; will retry with backoff"
            return
        }
        ::OrCADWheel::Fail $status $notify
        return
    }
    set CheckTimer [after 200 [list ::OrCADWheel::CheckStarted [expr {$attempt+1}] $notify]]
}

proc ::OrCADWheel::Heartbeat {} {
    variable Enabled
    variable Timer
    variable StateFile
    variable Running
    variable WriteFailures
    variable HealthFailures
    variable CheckTimer
    set Timer ""
    if {!$Enabled} {return}
    set active 0
    catch {set active [expr {[IsSchematicViewActive] == 1}]}
    if {[catch {
        # Fresh controller state enables hover routing. Native window class and
        # active MDI page determine scope even when an edit field owns focus.
        ::OrCADWheel::WriteText $StateFile "hover $active"
    } err]} {
        incr WriteFailures
        if {$WriteFailures == 1 || $WriteFailures % 25 == 0} {
            Log "Controller write delayed count=$WriteFailures: $err; retry without disabling"
        }
        set Timer [after 400 ::OrCADWheel::Heartbeat]
        return
    }
    if {$WriteFailures > 0} {Log "Controller writes resumed after $WriteFailures failures"; set WriteFailures 0}
    if {$Running && [catch {
        if {[clock seconds] - [file mtime "$StateFile.status"] > 5} {error "Helper heartbeat expired."}
        set status ""
        set status [::OrCADWheel::ReadText "$StateFile.status"]
        # An empty read may overlap the helper's small status write.
        if {$status == "stopped" || [string match "error:*" $status]} {error "Helper is not running: $status"}
    } err]} {
        incr HealthFailures
        if {$HealthFailures == 1} {Log "Helper health suspect: $err; confirming with repeated samples"}
        if {$HealthFailures >= 3} {::OrCADWheel::Recover $err}
    } else {
        set HealthFailures 0
    }
    if {!$Running && $CheckTimer eq ""} {::OrCADWheel::Recover "Helper not running"}
    set Timer [after 400 ::OrCADWheel::Heartbeat]
}

proc ::OrCADWheel::Enable {{notify 0}} {
    variable Directory
    variable Enabled
    variable StateFile
    variable Running
    variable CheckTimer
    variable Recovering; variable Recoveries; variable NextRecovery
    variable WriteFailures; variable HealthFailures
    if {$Enabled} {return}
    set Recovering 0; set Recoveries 0; set NextRecovery 0
    set WriteFailures 0; set HealthFailures 0
    Log "Enable requested; notify=$notify"
    set helper [file join $Directory OrCADWheelZoom.exe]
    if {![file exists $helper]} {error "Missing OrCADWheelZoom.exe; run build_wheel_zoom.ps1 first."}
    ::OrCADWheel::WriteText "$StateFile.status" "starting"
    set Enabled 1
    set Running 0
    # Mark initial startup before Heartbeat, so it cannot start a recovery helper.
    set CheckTimer [after 200 [list ::OrCADWheel::CheckStarted 0 $notify]]
    ::OrCADWheel::Heartbeat
    if {!$Enabled} {error "Cannot write wheel state file."}
    if {[catch {exec $helper --run [pid] $StateFile &} err]} {
        catch {::OrCADWheel::Disable}
        error $err
    }
}

proc ::OrCADWheel::Disable {} {
    variable Directory
    variable Enabled
    variable Timer
    variable StateFile
    variable Running
    variable CheckTimer
    variable Recovering
    Log "Disable requested; enabled=$Enabled running=$Running"
    set Enabled 0
    set Running 0
    set Recovering 0
    if {$Timer != ""} {after cancel $Timer; set Timer ""}
    if {$CheckTimer != ""} {after cancel $CheckTimer; set CheckTimer ""}
    catch {::OrCADWheel::WriteText $StateFile 0}
    exec [file join $Directory OrCADWheelZoom.exe] --stop [pid]
    puts "Wheel zoom disabled."
}

proc ::OrCADWheel::Toggle {} {
    variable Enabled
    Log "User menu toggle; enabled=$Enabled"
    if {[catch {
        if {$Enabled} {
            ::OrCADWheel::Disable
            ::OrCADWheel::Remember 0
        } else {::OrCADWheel::Enable 1}
    } err]} {
        tk_messageBox -icon error -type ok -title "Wheel Zoom" -message $err
        return
    }
    # Successful enable/disable is quiet; usage is available in Alt+F1.
}

proc ::OrCADWheel::AutoStart {} {
    variable Preference
    if {[file exists $Preference]} {
        if {[catch {set value [::OrCADWheel::ReadText $Preference]}]} {return}
        if {$value == "0"} {return}
    }
    if {[catch {::OrCADWheel::Enable} err]} {::OrCADWheel::Fail $err 0}
}

# Called by the merged entry only after every module has been defined.
# Only in Capture. No Windows startup task, no design modifications.
proc ::OrCADWheel::Initialize {} {
    if {[llength [info commands IsSchematicViewActive]] && ![info exists ::OrCADWheel::Initialized]} {
        set ::OrCADWheel::Initialized 1
        after idle ::OrCADWheel::AutoStart
    }
}
