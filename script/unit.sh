#!/usr/bin/bash

if [[ $# -lt 1 ]]; then
  echo "invalid number of arguments, please specify at least one module to test"
  exit 1
fi

echo "####################################################################################"
echo "#                              Running unit test                                   #"
echo "####################################################################################"
echo "modules to test: $@"

script_dir=$(dirname "$(realpath $0)")

vivado -mode batch -source $script_dir/run_unit_test.tcl -tclargs $@
