OPENWRT_DIR = openwrt
LUCI_DIR = luci
CUSTOM_PO_DIR = opennet/po
CUSTOM_PACKAGES_DIR = opennet/packages
LANGUAGES = de

.PHONY: all clean patch unpatch menuconfig feeds

all: feeds
	@$(MAKE) -C on-configs list | grep "^[a-zA-Z0-9_-]\+$$" | while read arch; do \
		$(MAKE) -C on-configs $$arch; \
		$(MAKE) -C "$(OPENWRT_DIR)"; \
	 done

init:
	@# update submodules if necessary
	@test ! -d "$(OPENWRT_DIR)/package" && git submodule init || true
	@git submodule update
	@test -z "$$QUILT_DIFF_ARGS" && echo >&2 "ACHTUNG: Die erforderlichen quilt-Einstellungen sind derzeit nicht aktiv. Im zweiten Absatz von Readme.md werden die Konsequenzen und die Behebung dieses Mangels erklaert."

menuconfig: feeds
	@# verfolge Aenderungen an der .config-Datei und zeige sie nach menuconfig an
	@quilt new "temp-menuconfig-$(shell date +%Y%m%d%H%M)"
	@quilt add "$(OPENWRT_DIR)/.config"
	$(MAKE) -C "$(OPENWRT_DIR)" menuconfig
	@quilt diff
	@quilt delete

translate:
	@find "$(CUSTOM_PACKAGES_DIR)" -mindepth 1 -maxdepth 1 -type d | while read dname; do \
		"$(LUCI_DIR)/build/i18n-scan.pl" "$$dname" >"$(CUSTOM_PO_DIR)/templates/$$(basename "$$dname").pot"; \
		for lang in $(LANGUAGES); do \
			echo "$(CUSTOM_PO_DIR)/$$lang/$$(basename "$$dname").po"; \
		 done | while read fname; do test ! -e "$$fname" && touch "$$fname" || true; done; \
	 done
	@"$(LUCI_DIR)/build/i18n-update.pl" "$(CUSTOM_PO_DIR)"

feeds: patch
	"$(OPENWRT_DIR)/scripts/feeds" update -a
	"$(OPENWRT_DIR)/scripts/feeds" install -a

patch:
	@# apply all patches if there are unapplied ones
	@test -n "$(shell quilt unapplied 2>/dev/null)" && quilt push -a || true

unpatch:
	@# revert all patches if there are applied ones
	@test -n "$(shell quilt applied 2>/dev/null)" && quilt pop -a || true

clean: unpatch

