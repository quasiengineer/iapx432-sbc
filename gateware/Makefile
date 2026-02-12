SHELL        := bash
TOP          ?=
PROJECT_NAME := iapx432-sbc$(if $(TOP),-$(TOP),)

TOP_MODULE  := top$(if $(TOP),_$(TOP),)
TOP_VERILOG := ./top/$(TOP_MODULE).v
VERILOG     := $(wildcard ./rtl/*.v)
PCF         := io.pcf
CONSTRAINTS := constraints.sdc

YOSYS    := yosys
NEXTPNR  := nextpnr-ice40
ICEPACK  := icepack
ICEPROG  := iceprog

DEVICE   := hx4k
PACKAGE  := tq144

JSON     := build/$(PROJECT_NAME).json
ASC      := build/$(PROJECT_NAME).asc
BIN      := build/$(PROJECT_NAME).bin
REPORT   := build/$(PROJECT_NAME)_report.json

all: $(BIN)

build:
	mkdir -p build

$(JSON): $(TOP_VERILOG) $(VERILOG) | build
	$(YOSYS) -DICE40 -p "read_verilog -noautowire $(TOP_VERILOG) $(VERILOG); synth_ice40 -dffe_min_ce_use 32 -abc9 -top $(TOP_MODULE) -json $@"

$(ASC): $(JSON) $(PCF) $(CONSTRAINTS)
	@set +e; set -o pipefail; \
	$(NEXTPNR) \
		--$(DEVICE) \
		--package $(PACKAGE) \
		--json $(JSON) \
		--pcf $(PCF) \
		--asc $(ASC) \
		--pre-pack $(CONSTRAINTS) \
		--opt-timing \
		--report $(REPORT) \
		--pcf-allow-unconstrained \
		--Werror \
		--seed 2 \
		2>&1 | tee nextpnr.log; \
	status=$$?; \
	if [ "$$status" -ne 0 ]; then \
		echo "========== nextpnr ERROR SUMMARY =========="; \
		grep -E "^(ERROR:)" nextpnr.log | sed 's/^/  /' || true; \
	fi; \
	exit $$status
	@echo "Utilization:"
	@jq -r '.utilization | to_entries | sort_by(.key) | .[] | "\(.key)\t\(.value.used)\t\(.value.available)\t\(((.value.used / .value.available) * 100) * 100 | round / 100)"' $(REPORT) | column -t -N "Resource,Used,Available,Percent"

$(BIN): $(ASC)
	$(ICEPACK) $(ASC) $(BIN)

flash: $(BIN)
	$(ICEPROG) -X $(BIN)
	./scripts/ft232_uart.py

reset:
	$(ICEPROG) -t
	./scripts/ft232_uart.py

clean:
	rm -rf build

.PHONY: all clean flash reset