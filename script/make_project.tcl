# get directory of script
set dir [file dirname [file normalize [info script]]]

# https://stackoverflow.com/questions/429386/tcl-recursively-search-subdirectories-to-source-all-tcl-files
# findFiles
# basedir - the directory to start looking in
# pattern - A pattern, as defined by the glob command, that the files must match
proc findFiles { basedir pattern } {
  # Fix the directory name, this ensures the directory name is in the
  # native format for the platform and contains a final directory seperator
  set basedir [string trimright [file join [file normalize $basedir] { }]]
  set fileList {}

  # Look in the current directory for matching files, -type {f r}
  # means ony readable normal files are looked at, -nocomplain stops
  # an error being thrown if the returned list is empty
  foreach fileName [glob -nocomplain -type {f r} -path $basedir $pattern] {
    lappend fileList $fileName
  }

  # Now look for any sub direcories in the current directory
  foreach dirName [glob -nocomplain -type {d  r} -path $basedir *] {
    # Recusively call the routine on the sub directory and append any
    # new files to the results
    set subDirList [findFiles $dirName $pattern]
    if { [llength $subDirList] > 0 } {
      foreach subDirFile $subDirList {
        lappend fileList $subDirFile
      }
    }
  }
  return $fileList
}

# get all synth RTL and simulation files
set sim_files [findFiles "$dir/../src/verif/" "*.sv"]
set rtl_files [findFiles "$dir/../src/rtl/" "*.{sv,v}"]
set constraint_files [glob -nocomplain "$dir/../src/constraints/*"]

# clean project directory
source $dir/clean.tcl

# create a project
if { $project_type == "synth" } {
  create_project proj $dir/../build/proj
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
