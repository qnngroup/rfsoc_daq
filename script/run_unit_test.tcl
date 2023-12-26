if {$argc <= 0} {
  puts "run_unit_test.tcl requires one or more arguments"
  exit 1
}

# get directory of script
set dir [file dirname [file normalize [info script]]]

# make project
set project_type "sim"
source $dir/make_project.tcl

set error_count 0

set_property -name {xsim.simulate.runtime} -value {0} -objects [get_filesets sim_1]
# set toplevel for simulation
foreach module $argv {
  set_property top $module [current_fileset -sims]
  if {[catch {launch_simulation} err]} {
    puts "failed to launch simulation for module $module"
    incr error_count 1
    lappend failing_modules $module
  } else {
    run all
    if {[get_value -radix unsigned /$module/dbg.error_count]} {
      incr error_count [get_value -radix unsigned /$module/dbg.error_count]
      lappend failing_modules $module
    }
  }
}

if {$error_count != 0} {
  cd $dir
  set err_file [open "errors.out" w]
  puts $err_file "total errors: $error_count"
  puts $err_file "failing module count: [llength $failing_modules]"
  puts $err_file "failing modules:"
  foreach module $failing_modules {
    puts $err_file $module
  }
  close $err_file
  exit 1
}

exit 0
