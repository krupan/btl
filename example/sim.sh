#!/bin/sh
set -e

SIM_EXECUTABLE=sim
BUILD_DIR=build
mkdir -p $BUILD_DIR

# generate diagrams from rdl
if type plantuml > /dev/null 2>&1; then
    plantuml --svg ./*.puml --output-dir build/
    echo "generated diagrams, see $BUILD_DIR/*.svg"
else
    echo "WARNING: plantuml executable not found, not generating diagrams"
fi

# generate registers from rdl
if type peakrdl > /dev/null 2>&1; then
    peakrdl \
        --peakrdl-cfg ../pyproject.toml \
        btl-reg-exporter \
        example_regs.rdl \
        -o $BUILD_DIR/example_regs.svh
    echo "generated btl_reg code from rdl, see $BUILD_DIR/*.svh"
else
    echo "ERROR: peakrdl executable not found, can't generage btl_reg code"
    exit 1
fi

# compile simulation
if type verilator > /dev/null 2>&1; then
    verilator \
        --quiet-build \
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
    if ./$BUILD_DIR/$SIM_EXECUTABLE > $BUILD_DIR/sim.log; then
        echo ""
        echo "SIMULATION PASSED! see output in $BUILD_DIR/sim.log"
    else
        echo ""
        echo "SIMULATION FAILED! see output in $BUILD_DIR/sim.log"
        exit 1
    fi
else
    echo "ERROR: verilator executable not found, can't compile and run simulation"
fi
