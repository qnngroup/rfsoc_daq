#!/usr/bin/bash

echo "####################################################################################"
echo "#                                Running linter                                    #"
echo "####################################################################################"

script_dir=$(dirname "$(realpath $0)")
source $script_dir/get_compilation_order.sh

verilator --timing --lint-only $script_dir/verilator_config.vlt $(cat $script_dir/../build/file_order.lst)
return_code=$?

if [[ $return_code -eq 0 ]]; then
  echo "####################################################################################"
  echo "#                                Passed linter                                     #"
  echo "####################################################################################"
else
  echo "####################################################################################"
  echo "#                                Failed linter                                     #"
  echo "####################################################################################"
fi
