#!/usr/bin/bash

echo "####################################################################################"
echo "#                                Running linter                                    #"
echo "####################################################################################"

script_dir=$(dirname "$(realpath $0)")
error_count=0
echo "VERIBLE"
while read -r fname; do
  verible-verilog-lint --rules_config=$script_dir/lint_rules.txt $(realpath --relative-to=$PWD $fname)
  error_count=$((error_count+$?))
done < <(find $script_dir/../src -type f -regex ".*\.\(v\|sv\)")

echo "SLANG"
slang $(find $script_dir/../src -type f -regex ".*\.\(v\|sv\)") $script_dir/null_modules/xpm_cdc.sv --error-limit=1000
error_count=$((error_count+$?))

if [[ $error_count -eq 0 ]]; then
  echo "####################################################################################"
  echo "#                                Passed linter                                     #"
  echo "####################################################################################"
else
  echo "####################################################################################"
  echo "#                                Failed linter                                     #"
  echo "####################################################################################"
fi
