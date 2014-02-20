BUILD_DIR = $(shell cd ../openwrt; pwd)
CURRENT_CONFIG = $(BUILD_DIR)/.config
PREVIOUS_CONFIG = $(BUILD_DIR)/.config.oni
COMMON_CONFIG = common

# no hidden files, no Makefile
CONFIGS = $(shell ls | grep -v ^Makefile | grep -v "^$(COMMON_CONFIG)$$")

.PHONY: all list $(CONFIGS)

all: $(CONFIGS)

$(CONFIGS):
	@# keep the timestamp of the current .config file if there is no change
	@test -f "$(CURRENT_CONFIG)" && mv "$(CURRENT_CONFIG)" "$(PREVIOUS_CONFIG)" || true
	@cat "$@" "$(COMMON_CONFIG)" > "$(CURRENT_CONFIG)"
	@$(MAKE) -C "$(BUILD_DIR)" defconfig >/dev/null
	@if diff -q "$(CURRENT_CONFIG)" "$(PREVIOUS_CONFIG)" >/dev/null; then \
			mv "$(PREVIOUS_CONFIG)" "$(CURRENT_CONFIG)"; \
		else	rm -f "$(PREVIOUS_CONFIG)"; fi
	@$(MAKE) -C "$(BUILD_DIR)"

list:
	@echo $(CONFIGS) | tr " " "\n"

