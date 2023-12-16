#!/usr/bin/bash

if [[ $# -lt 1 ]]; then
  echo "invalid number of arguments, please specify at least one module to test"
  exit 1
fi

echo "#####################"
echo "# Running unit test #"
echo "#####################"
echo "modules to test: $@"

vivado -mode batch -source run_unit_test.tcl -tclargs $@
