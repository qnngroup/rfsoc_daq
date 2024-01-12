#!/usr/bin/bash

script_dir=$(dirname "$(realpath $0)")

if [[ $# -ne 0 ]]; then
  if [[ $1 -eq 1]]; then
    # rerun project setup
    vivado -mode batch -source $script_dir/make_bd.tcl -notrace
  fi
fi

vivado -mode batch -source $script_dir/make_bitstream.tcl -notrace
