#!/usr/bin/bash

# https://askubuntu.com/questions/893911/when-writing-a-bash-script-how-do-i-get-the-absolute-path-of-the-location-of-th
script_dir=$(dirname "$(realpath $0)")

#https://unix.stackexchange.com/questions/21033/how-can-i-grep-the-results-of-find-using-exec-and-still-output-to-a-file
# https://stackoverflow.com/questions/1133698/using-find-to-locate-files-that-match-one-of-multiple-patterns
modules=$(find $script_dir/../src/ \( -name "*.sv" -o -name "*.v" \) -print0 | xargs -0 grep -Pho 'module ([a-zA-Z0-9_]*)_test' | sed 's/^module //g')

echo "####################################################################################"
echo "#                           Running regression test                                #"
echo "####################################################################################"
echo -e "modules to test:\n$modules"

# https://unix.stackexchange.com/questions/29509/transform-an-array-into-arguments-of-a-command
vivado -mode batch -source $script_dir/run_unit_test.tcl -notrace -tclargs $modules
return_code=$?

if [[ $return_code -eq 0 ]]; then
  echo "####################################################################################"
  echo "#                            Passed regression test                                #"
  echo "####################################################################################"
else
  echo "####################################################################################"
  echo "#                            Failed regression test                                #"
  echo "####################################################################################"
  cat $script_dir/errors.out
  rm $script_dir/errors.out
fi
