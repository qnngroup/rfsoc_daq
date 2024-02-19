#!/usr/bin/bash

script_dir=$(dirname "$(realpath $0)")
list_file=$script_dir/../build/file_order.lst
verilog_regex="\.\(v\|sv\)"
test_regex=".*_\(test\|tb\)"$verilog_regex

echo $script_dir/null_modules/xpm_cdc.sv > $list_file
# first, all the synthesizable RTL (v, sv sources that are not tests)
find $script_dir/../src/rtl/ -type f \( ! -regex $test_regex -a -regex ".*"$verilog_regex \) >> $list_file
# next, sim_util_pkg
echo $script_dir/../src/verif/sim_util_pkg.sv >> $list_file
# then, sample_discriminator_pkg
echo $script_dir/../src/verif/sample_discriminator_pkg.sv >> $list_file
# then all verification utilites/classes
find $script_dir/../src/verif/ -type f -regex ".*\.sv" >> $list_file
# finally the unit tests
find $script_dir/../src/rtl/ -type f -regex $test_regex >> $list_file

# https://stackoverflow.com/questions/11532157/remove-duplicate-lines-without-sorting
awk '!seen[$0]++' $list_file | xargs realpath > $list_file.sorted
mv $list_file.sorted $list_file
