# get directory of script
set dir [file dirname [file normalize [info script]]]

# clean up project directory
set proj_files [glob -nocomplain "$dir/../build/proj/*"]
if {[llength $proj_files] != 0} {
  file delete -force -- {*}[glob "$dir/../build/proj/*"]
}

# remove log files
file delete {*}[glob "$dir/../*.log"]
file delete {*}[glob "$dir/../*.jou"]
