#!/bin/sh
set -e

SIM=sim

verilator \
    -j $(nproc) \
    -I../ \
    --binary \
    -o $SIM \
    ../btl.sv \
    ../btl_regs.sv \
    example_regs.sv \
    example_tb.sv \
    example_top.sv

./obj_dir/$SIM
