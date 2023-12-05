# get directory of script
set dir [file dirname [file normalize [info script]]]

# get all synth RTL and simulation files
set sim_files [glob $dir/../src/verif/*]
set rtl_files [glob $dir/../src/rtl/*]
set constriant_files [glob $dir/../src/constraints/*]

puts $dir
puts $sim_files
puts $rtl_files

# clean up project directory
file delete -force -- $dir/../build/proj/*

# create a project
create_project proj $dir/../build/proj -part xczu28dr-ffvg1517-2-e
set_property board_part xilinx.com:zcu111:part0:1.4 [current_project]

# add files
add_files -fileset sim_1 -norecurse $sim_files
add_files -fileset sources_1 -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse $constraint_files

# include all source files in simulation
set_property SOURCE_SET sources_1 [get_filesets sim_1]

# update compile order
update_compile_order -fileset sim_1
update_compile_order -fileset sources_1
