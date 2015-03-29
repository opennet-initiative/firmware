BUILD_DIR = $(shell cd ../../openwrt; pwd)
CURRENT_CONFIG = $(BUILD_DIR)/.config
PREVIOUS_CONFIG = $(BUILD_DIR)/.config.oni
COMMON_CONFIG = common
GIT_COMMIT_COUNT = $(shell git log --oneline | wc -l)
# ermittle die Release-Version (falls die aktuelle Version getaggt wurde) - entferne dabei das fuehrende "v" von "v0.5.0"
GIT_CURRENT_RELEASE_TAG = $(shell git tag -l --points-at HEAD | sed 's/^v//g')
NEXT_VERSION = $(shell grep "^CONFIG_VERSION_NUMBER=" "$(COMMON_CONFIG)" | cut -f 2 -d '"')

SMALLCONFIG = bcm47xx
BIGCONFIG = ar71xx common ixp4xx tl-wr1043nd tl-wr842nd x86

.PHONY: all list $(SMALLCONFIG) $(BIGCONFIG) save-config check-old-config list-subarch help

help:
	$(info Die folgenden Ziele sind verfügbar:)
	$(info - list		Initialisierung des opennet-Repositories)
	$(info - list-subarchs	alle Sub-Architekturen der aktuellen Architektur anzeigen (via 'SUBARCH=foo make ar71xx' compilieren))
	$(info - ARCH		eine Architektur compilieren (inkl. aller standardmaessig aktiven Sub-Architekturen))

list-archs:
	$(info $(ARCHS))

list:
	@echo $(SMALLCONFIG) $(BIGCONFIG) | tr " " "\n"

ARCH_PREFIX=$(shell grep "^CONFIG_TARGET_" "$(CURRENT_CONFIG)" | head -1 | cut -f 1 -d =)
list-subarchs:
	@grep "$(ARCH_PREFIX)_" "$(CURRENT_CONFIG)" | sed 's/^.*$(ARCH_PREFIX)_//' | cut -f 1 -d " " | cut -f 1 -d "="

$(BIGCONFIG) $(SMALLCONFIG):
	@$(MAKE) save-config
	@cat "$@" "$(COMMON_CONFIG)" > "$(CURRENT_CONFIG)"
	@# replace modules with builtins ('=m' -> '=y') for big devices
	@# TODO: pruefen, wie/ob wir zukuenftig small/big (4/8 MB) erzeugen wollen; das Aktivieren aller "m"-Pakete ist keine Option
	@#echo " $(BIGCONFIG) " | grep -q " $@ " && sed -i 's/=m$$/=y/i' "$(CURRENT_CONFIG)"
	@# Optionally an environment variable 'SUBARCH' may be given.
	@# Add something like "CONFIG_TARGET_ar71xx_generic_TLWR1043=y" to
	@# the config file if the environment variable SUBARCH is given.
	@test -n "$(SUBARCH)" && sed -i 's/^\(CONFIG_TARGET_$@_\).*_\?Default\(=y\)$$/\1$(SUBARCH)\2/' "$(CURRENT_CONFIG)" || true
	@# Release eintragen (eventuell ein echtes - oder einen snapshot mit einer commit-Zahl)
	@if [ -n "$(GIT_CURRENT_RELEASE_TAG)" ]; then \
		sed -i '/^CONFIG_VERSION_NUMBER=/s/=.*$$/="$(GIT_CURRENT_RELEASE_TAG)-$(GIT_COMMIT_COUNT)"/' "$(CURRENT_CONFIG)"; \
	else \
		sed -i '/^CONFIG_VERSION_NUMBER=/s/=.*$$/="$(NEXT_VERSION)-unstable-$(GIT_COMMIT_COUNT)"/' "$(CURRENT_CONFIG)"; \
	fi
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

