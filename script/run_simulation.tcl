if { $argc != 1 } {
  # iterate over each module-level file
}

# get directory of script
set dir [file dirname [file normalize [info script]]]

# make project
source $dir/make_project.tcl

# set toplevel
