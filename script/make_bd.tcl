# get directory of script
set dir [file dirname [file normalize [info script]]]

set project_type "synth"
source $dir/make_project.tcl
source $dir/top.tcl
