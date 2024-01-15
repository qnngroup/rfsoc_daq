# get directory of script
set dir [file dirname [file normalize [info script]]]

set proj_dir [file normalize $dir/../build/proj_synth]
set project_type "synth"
source $dir/make_project.tcl
source $dir/top.tcl

make_wrapper -files [get_files $proj_dir/proj_synth.srcs/sources_1/bd/top/top.bd] -top
add_files -norecurse $proj_dir/proj_synth.gen/sources_1/bd/top/hdl/top_wrapper.v
update_compile_order -fileset sources_1
set_property top top_wrapper [current_fileset]
update_compile_order -fileset sources_1
