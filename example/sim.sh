#!/bin/sh
set -e

SIM_EXECUTABLE=sim
BUILD_DIR=build
mkdir -p $BUILD_DIR

# generate registers from rdl
peakrdl \
    --peakrdl-cfg ../pyproject.toml \
    btl-reg-exporter \
    example_regs.rdl \
    -o $BUILD_DIR/example_regs.svh

# compile simulation
verilator \
    -Mdir $BUILD_DIR/ \
    -j "$(nproc)" \
    -I../ \
    -Ibuild/ \
    --binary \
    -o $SIM_EXECUTABLE \
    ../btl.sv \
    ../btl_regs.sv \
    example_tb.sv \
    example_top.sv

# run simulation
./$BUILD_DIR/$SIM_EXECUTABLE
