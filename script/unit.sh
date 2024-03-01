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

vivado -mode batch -source $script_dir/run_unit_test.tcl -notrace -tclargs $@ | tee $script_dir/vivado.log
return_code=${PIPESTATUS[0]}
fatal_error=$(grep 'FATAL_ERROR' $script_dir/vivado.log)

if [[ $return_code -eq 0 ]] && [[ -z $fatal_error ]]; then
  echo "####################################################################################"
  echo "#                               Passed unit test                                   #"
  echo "####################################################################################"
else
  echo "####################################################################################"
  echo "#                               Failed unit test                                   #"
  echo "####################################################################################"
  if [[ -z $fatal_error ]]; then
    cat $script_dir/errors.out
    rm $script_dir/errors.out
  else
    echo "encountered a fatal error"
  fi
fi
