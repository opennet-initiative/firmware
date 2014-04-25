BUILD_DIR = $(shell cd ../openwrt; pwd)
CURRENT_CONFIG = $(BUILD_DIR)/.config
PREVIOUS_CONFIG = $(BUILD_DIR)/.config.oni
COMMON_CONFIG = common

SMALLCONFIG = bcm47xx
BIGCONFIG = ar71xx common ixp4xx tl-wr1043nd tl-wr842nd x86

.PHONY: all list $(SMALLCONFIG) $(BIGCONFIG) save-config check-old-config

list:
	@echo $(SMALLCONFIG) $(BIGCONFIG) | tr " " "\n"

$(SMALLCONFIG):
	@$(MAKE) save-config
	@cat "$@" "$(COMMON_CONFIG)" > "$(CURRENT_CONFIG)"
	@$(MAKE) check-old-config

$(BIGCONFIG):
	@$(MAKE) save-config
	@# BIG CONFIG means that all packages selected as module are now included by default
	@cat "$@" "$(COMMON_CONFIG)" | sed 's/=m$$/=y/i' > "$(CURRENT_CONFIG)"
	@$(MAKE) check-old-config

save-config:
	@# keep the timestamp of the current .config file if there is no change
	@test -f "$(CURRENT_CONFIG)" && mv "$(CURRENT_CONFIG)" "$(PREVIOUS_CONFIG)" || true

check-old-config:
	@# fill in missing default values
	@$(MAKE) -C "$(BUILD_DIR)" defconfig >/dev/null
	@# if previous config has same content as new config, revert new config to indicate build process that nothing has changed 
	@if test -e "$(PREVIOUS_CONFIG)" && diff -q "$(CURRENT_CONFIG)" "$(PREVIOUS_CONFIG)" >/dev/null; then \
			mv "$(PREVIOUS_CONFIG)" "$(CURRENT_CONFIG)"; \
		else	rm -f "$(PREVIOUS_CONFIG)"; fi

