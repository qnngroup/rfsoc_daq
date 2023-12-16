#!/usr/bin/bash

modules=$(grep -Pho 'module ([a-zA-Z0-9_]*)_test' ../src/verif/* | sed 's/^module //g')

echo "###########################"
echo "# Running regression test #"
echo "###########################"
echo "modules to test: $modules"

# https://unix.stackexchange.com/questions/29509/transform-an-array-into-arguments-of-a-command
vivado -mode batch -source run_unit_test.tcl -tclargs $modules
