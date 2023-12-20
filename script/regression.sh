#!/usr/bin/bash

# https://askubuntu.com/questions/893911/when-writing-a-bash-script-how-do-i-get-the-absolute-path-of-the-location-of-th
script_dir=$(dirname "$(realpath $0)")

modules=$(grep -Pho 'module ([a-zA-Z0-9_]*)_test' $script_dir/../src/verif/* | sed 's/^module //g')

echo "###########################"
echo "# Running regression test #"
echo "###########################"
echo "modules to test: $modules"

# https://unix.stackexchange.com/questions/29509/transform-an-array-into-arguments-of-a-command
vivado -mode batch -source $script_dir/run_unit_test.tcl -tclargs $modules
