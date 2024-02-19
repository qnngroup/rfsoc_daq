# get directory of script
set dir [file dirname [file normalize [info script]]]

# clean up project directory
set proj_files [glob -nocomplain "$dir/../build/proj_$project_type/*"]
if {[llength $proj_files] != 0} {
  if { $check_for_delete != 0 } {
    puts "proj_$project_type/ contains files that will be deleted, proceed? (y/n) "
    gets stdin response
    if { $response != "y" } {
      puts "not proceeding with delte, please rerun again after saving your files"
      exit 1
    }
  }
  file delete -force -- {*}$proj_files
}

# remove log files in working directory
set wd [pwd]
set log_files [glob -nocomplain "$wd/*.log"]
set jou_files [glob -nocomplain "$wd/*.jou"]
if {[llength $log_files] != 0} {
  file delete {*}$log_files
}
if {[llength $jou_files] != 0} {
  file delete {*}$jou_files
}
