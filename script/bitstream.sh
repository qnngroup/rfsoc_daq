#!/usr/bin/bash

script_dir=$(dirname "$(realpath $0)")

vivado -mode batch -source $script_dir/make_bitstream.tcl -notrace
