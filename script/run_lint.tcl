set script_dir [file dirname [file normalize [info script]]]
set project_type "sim"
source $script_dir/make_project.tcl

check_syntax -fileset [get_filesets sim_1]
set num_warning [get_msg_config -severity {WARNING} -count]
set num_error [get_msg_config -severity {ERROR} -count]
set num_crit [get_msg_config -severity {CRITICAL WARNING} -count]
if {($num_warning + $num_error + $num_crit) > 0} {
  puts "### LINT FAILED ###"
  puts "### PLEASE FIX ISSUES AND RERUN SIMULATION ###"
  cd $script_dir
  set err_file [open "errors.out" w]
  puts $err_file "total errors: $num_error"
  puts $err_file "total critical warnings: $num_crit"
  puts $err_file "total warnings: $num_warning"
  close $err_file
  exit 1
}

exit 0
