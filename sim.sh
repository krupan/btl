#!/bin/sh
set -e
verilator -j 4 --binary btl.sv example_tb.sv example_top.sv
./obj_dir/Vbtl
