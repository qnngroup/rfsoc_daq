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
  launch_simulation
  run all
  if {[get_value -radix unsigned /$module/dbg.error_count]} {
    incr error_count
  }
}

exit $error_count
