# get directory of script
set dir [file dirname [file normalize [info script]]]

source $dir/make_bd.tcl

launch_runs synth_1 -jobs 8
