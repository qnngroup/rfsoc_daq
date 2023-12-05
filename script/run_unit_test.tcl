if {$argc <= 0} {
  puts "run_unit_test.tcl requires one or more arguments"
  exit 1
}

# get directory of script
set dir [file dirname [file normalize [info script]]]

# make project
source $dir/make_project.tcl

# set toplevel for simulation
foreach module $argv {
  set_property top $module [current_fileset -sims]
  launch_simulation
  run all
}
exit 0
