set dir [file dirname [file normalize [info script]]]

set proj_dir [file normalize $dir/../build/proj_synth]

open_project $proj_dir/proj_synth.xpr

set_param synth.elaboration.rodinMoreOptions "rt::set_parameter var_size_limit 2097152"
set_param messaging.defaultLimit 5000

reset_run synth_1
launch_runs synth_1 -jobs 8
