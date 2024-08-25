set dir [file dirname [file normalize [info script]]]

source $dir/run_synth.tcl

launch_runs impl_1 -jobs 8
