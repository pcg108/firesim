# See LICENSE for license details.

####################################
# Verilator MIDAS-Level Simulators #
####################################

VERILATOR_CXXOPTS ?= -O2
VERILATOR_MAKEFLAGS ?= -j8 VM_PARALLEL_BUILDS=1

verilator = $(GENERATED_DIR)/V$(DESIGN)
verilator_debug = $(GENERATED_DIR)/V$(DESIGN)-debug
verilator_narrow_waveform_enabled := $(filter 1 yes true,$(VERILATOR_NARROW_WAVEFORM))
verilator_debug_mode := $(if $(verilator_narrow_waveform_enabled),on,off)
verilator_debug_mode_stamp := $(GENERATED_DIR)/.V$(DESIGN)-debug-narrow-waveform-$(verilator_debug_mode)

$(verilator) $(verilator_debug): export CXXFLAGS := $(CXXFLAGS) $(common_cxx_flags) $(VERILATOR_CXXOPTS) -D RTLSIM
$(verilator) $(verilator_debug): export LDFLAGS := $(LDFLAGS) $(common_ld_flags) -Wl,-rpath='$$$$ORIGIN'

verilator_driver_deps := $(header) $(DRIVER_CC) $(DRIVER_H) $(midas_cc) $(midas_h) $(simulator_verilog)

define make_verilator
        $(MAKE) -C $(simif_dir) $(VERILATOR_MAKEFLAGS) $(1) \
                PLATFORM=$(PLATFORM) \
                DRIVER_NAME=$(DESIGN) \
                GEN_FILE_BASENAME=$(BASE_FILE_NAME) \
                GEN_DIR=$(GENERATED_DIR) \
                DRIVER="$(DRIVER_CC)" \
		VERILATOR_NARROW_WAVEFORM="$(VERILATOR_NARROW_WAVEFORM)" \
		VERILATOR_FLAGS="$(EXTRA_VERILATOR_FLAGS)"
endef

$(verilator): $(verilator_driver_deps)
	$(call make_verilator, verilator)

$(verilator_debug_mode_stamp):
	touch $@

$(verilator_debug): $(verilator_driver_deps) $(verilator_debug_mode_stamp)
	$(call make_verilator, verilator-debug)

.PHONY: verilator verilator-debug
verilator: $(verilator)
verilator-debug: $(verilator_debug)
