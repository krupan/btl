# see help at end of file

.DEFAULT_GOAL := sim

SIM_EXECUTABLE = sim
BUILD_DIR = build
BUILD_DIR_TARGET = $(BUILD_DIR)/.gitignore

$(BUILD_DIR_TARGET):
	@echo "Creating output dir: $(BUILD_DIR)"
	@mkdir -p $(BUILD_DIR)
	@printf "# ignore all files in this directory\n" > $(BUILD_DIR_TARGET)
	@printf "*\n" >> $(BUILD_DIR_TARGET)
	@printf "# except this .gitignore file\n" >> $(BUILD_DIR_TARGET)
	@printf "!.gitignore" >> $(BUILD_DIR_TARGET)

DIAGRAM_SRCS = $(wildcard *.puml)
DIAGRAM_FILES = $(DIAGRAM_SRCS:.puml=.svg)
DIAGRAM_TGTS = $(foreach FILE,$(DIAGRAM_FILES),$(BUILD_DIR)/$(FILE))

$(BUILD_DIR)/%.svg: %.puml $(BUILD_DIR_TARGET)
	@echo "Generating SVG diagram from PlantUML"
	@plantuml --svg "$<" --output-dir $(BUILD_DIR)

RDL_SRCS = $(wildcard *.rdl)
RDL_FILES = $(RDL_SRCS:.rdl=.svh)
RDL_TGTS = $(foreach FILE,$(RDL_FILES),$(BUILD_DIR)/$(FILE))

$(BUILD_DIR)/%.svh: %.rdl $(BUILD_DIR_TARGET)
	@echo "Generating btl_reg code from SystemRDL"
	@peakrdl --peakrdl-cfg ../pyproject.toml btl-reg-exporter "$<" -o $@

SIM_SRCS = ../btl.sv ../btl_regs.sv example_tb.sv example_top.sv
SIM_TGT = $(BUILD_DIR)/$(SIM_EXECUTABLE)

$(SIM_TGT): $(SIM_SRCS) $(RDL_TGTS) $(BUILD_DIR_TARGET)
	@echo "Compiling Sim"
	@verilator \
	  --quiet-build \
	  -Mdir $(BUILD_DIR)/ \
	  -j "$(nproc)" \
	  -I../ \
	  -I$(BUILD_DIR)/ \
	  --binary \
	  -o $(SIM_EXECUTABLE) \
	  $(SIM_SRCS)

SIM_LOG = $(BUILD_DIR)/$(SIM_EXECUTABLE).log
SIM_FAIL_LOG = $(BUILD_DIR)/$(SIM_EXECUTABLE)_FAIL.log
$(SIM_LOG): $(RDL_TGTS) $(SIM_TGT)
	@echo "Running sim"
	@rm -f $(SIM_LOG) $(SIM_FAIL_LOG)
	@if ./$(BUILD_DIR)/$(SIM_EXECUTABLE) > $(SIM_LOG); then \
	    echo ""; \
	    echo "SIMULATION PASSED! see output in $(SIM_LOG)"; \
	    echo ""; \
	    exit 0; \
	  fi; \
	  mv $(SIM_LOG) $(SIM_FAIL_LOG); \
	  echo ""; \
	  echo "SIMULATION FAILED! see output in $(SIM_FAIL_LOG)"; \
	  echo ""; \
	  exit 1

.PHONY: clean
clean:
	rm -f $(BUILD_DIR)/*

.PHONY: diagrams
diagrams: $(DIAGRAM_TGTS)

.PHONY: sim
sim: $(BUILD_DIR)/sim.log

.PHONY: all
all: diagrams sim

.PHONY: help
help:
	@echo "run 'make diagrams' to generate diagrams"
	@echo "run 'make' or 'make sim' to compile the simulation and run it"
	@echo "run 'make all' to generate diagrams, compile the simulation, and run it"
	@echo "run 'make clean' to delete all generated files"
	@echo "run 'make help' to print this"
