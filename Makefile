OPENWRT_DIR = openwrt
LUCI_DIR = luci
CUSTOM_PO_DIR = opennet/po
CUSTOM_PACKAGES_DIR = opennet/packages
LANGUAGES = de
COMMON_CONFIG = common
CONFIG_DIR = opennet/config
# list all files except Makefile, common file and hidden files
ARCHS = $(shell ls "$(CONFIG_DIR)/" | grep -v ^Makefile | grep -v "^$(COMMON_CONFIG)$$")
GIT_COMMIT_COUNT=$(shell git log --oneline | wc -l)

.PHONY: all clean patch unpatch menuconfig diff-menuconfig feeds init init-git init-git help list-archs

all: $(ARCHS)

help:
	$(info Die folgenden Ziele sind verfügbar:)
	$(info - init			Initialisierung des opennet-Repositories)
	$(info - all 			alle Architekturen compilieren)
	$(info - list-archs		alle Architekturen anzeigen)
	$(info - ARCH			eine Architektur kompilieren)
	$(info - config-ARCH		die Konfiguration einer Architektur anwenden (dies erzeugt 'openwrt/.config'))
	$(info - diff-menuconfig	vergleichbar mit "make -C openwrt menuconfig" - es wird jedoch anschließend ein diff der Änderungen angezeigt)
	$(info - translate		Übersetzungsdateien (opennet/po/de/*.po) aktualisieren)
	$(info - feeds			die Paket-Feeds (siehe openwrt/feeds.conf) neu einlesen)
	$(info - patch			die opennet-Patches via quilt anwenden (siehe ./patches/*.patch))
	$(info - unpatch		die opennet-Patches zurücknehmen (empfehlenswert vor jedem "git pull"))

list-archs:
	$(info $(ARCHS))

$(ARCHS): feeds translate
	@echo "Building for target architecture: $@"
	$(MAKE) "config-$@"
	@# update the release identifier
	@sed -i 's/PKG_RELEASE:=.*/PKG_RELEASE:=$(GIT_COMMIT_COUNT)/i' $(OPENWRT_DIR)/include/opennet-version.mk
	@# aus irgendeinem Grund wird die opkg.conf sonst nicht aktualisiert
	@touch "$(OPENWRT_DIR)/package/system/opkg/Makefile"
	$(MAKE) -C "$(OPENWRT_DIR)"

config-%:
	@test -f $(OPENWRT_DIR)/feeds.conf || echo "**** FEHLER! DATEI feeds.conf FEHLT. Fuehre bitte 'make feeds' aus. ****"
	$(MAKE) -C "$(CONFIG_DIR)/" "$(patsubst config-%,%,$@)"

menuconfig:
	$(warning "'menuconfig' gibt es hier nicht - vielleicht meinst du eine der folgenden Aktionen?")
	$(warning " 		make -C openwrt menuconfig")
	$(warning " 		make config-ar71xx")
	$(warning " 		make diff-menuconfig")
	$(error "unbekanntes Ziel 'menuconfig'")

git-init:
	@# update submodules if necessary
	git submodule init --quiet
	git submodule update
	@test -z "$$QUILT_DIFF_ARGS" -a ! -e ~/.quiltrc && echo >&2 "HINWEIS: falls du Patches aendern moechtest, dann lies bitte doc/Entwicklung.md (Stichwort: 'quilt-Konfiguration')" || true

init: git-init feeds translate

diff-menuconfig: feeds
	@# verfolge Aenderungen an der .config-Datei und zeige sie nach menuconfig an
	@quilt new "temp-menuconfig-$(shell date +%Y%m%d%H%M)"
	@quilt add "$(OPENWRT_DIR)/.config"
	$(MAKE) -C "$(OPENWRT_DIR)" menuconfig
	@quilt diff
	@quilt delete

translate:
	@find "$(CUSTOM_PACKAGES_DIR)" -mindepth 1 -maxdepth 1 -type d | while read dname; do \
		echo "$$dname" "$(CUSTOM_PO_DIR)/templates/$$(basename "$$dname").pot"; \
	 done | while read dname pot_filename; do \
		"$(LUCI_DIR)/build/i18n-scan.pl" "$$dname" >"$$pot_filename"; \
		false COMMENT: remove zero-sized pot files; \
		(test -e "$$pot_filename" -a ! -s "$$pot_filename" && rm "$$pot_filename") || true; \
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
	@# first reset a local change
	@[ -e "$(OPENWRT_DIR)/include/opennet-version.mk" ] && sed -i 's/PKG_RELEASE:=.*/PKG_RELEASE:=1/i' $(OPENWRT_DIR)/include/opennet-version.mk || true
	@# now make unpatch
	@test -n "$(shell quilt applied 2>/dev/null)" && quilt pop -a || true

clean: unpatch

# VORSICHT: alle lokalen Aenderungen gehen verloren - dies sollte nie von einem
# Menschen ausgefuehrt werden - es ist lediglich fuer den trac-Autobuilder gedacht
autobuilder-clean:
	git fetch --all
	git reset --hard origin/master
	git submodule update

