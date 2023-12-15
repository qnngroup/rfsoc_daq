# get directory of script
set dir [file dirname [file normalize [info script]]]

# get all synth RTL and simulation files
set sim_files [glob -nocomplain "$dir/../src/verif/*"]
set rtl_files [glob -nocomplain "$dir/../src/rtl/*"]
set constraint_files [glob -nocomplain "$dir/../src/constraints/*"]

# clean project directory
source $dir/clean.tcl

# create a project
if { $project_type == "synth" } {
  create_project proj $dir/../build/proj -part xczu28dr-ffvg1517-2-e
  set_property board_part xilinx.com:zcu111:part0:1.4 [current_project]
} elseif { $project_type == "sim" } {
  create_project proj $dir/../build/proj
} else {
  puts "Invalid project type, choose 'sim' or 'synth'"
}

# add files
if {[llength $sim_files] != 0} {
  add_files -fileset sim_1 -norecurse $sim_files
}
if {[llength $rtl_files] != 0} {
  add_files -fileset sources_1 -norecurse $rtl_files
}
if {[llength $constraint_files] != 0} {
  add_files -fileset constrs_1 -norecurse $constraint_files
}

# include all source files in simulation
set_property SOURCE_SET sources_1 [get_filesets sim_1]

# update compile order
update_compile_order -fileset sim_1
update_compile_order -fileset sources_1
