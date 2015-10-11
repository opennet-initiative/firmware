OPENWRT_DIR = openwrt
LUCI_DIR = luci
CUSTOM_PO_DIR = opennet/po
CUSTOM_PACKAGES_DIR = opennet/packages
CUSTOM_DOC_DIR = opennet/doc
LANGUAGES = de
COMMON_CONFIG = common
CONFIG_DIR = opennet/config
# list all files except Makefile, common file and hidden files
ARCHS = $(shell ls "$(CONFIG_DIR)/" | grep -v ^Makefile | grep -v "^$(COMMON_CONFIG)$$")

.PHONY: all clean patch unpatch menuconfig diff-menuconfig feeds init init-git init-git help list-archs doc

all: $(ARCHS)

help:
	$(info Die folgenden Ziele sind verfügbar:)
	$(info - init			Initialisierung des opennet-Repositories)
	$(info - all 			alle Architekturen compilieren)
	$(info - list-archs		alle Architekturen anzeigen)
	$(info - ARCH			eine Architektur kompilieren)
	$(info - config-ARCH		die Konfiguration einer Architektur anwenden (dies erzeugt 'openwrt/.config'))
	$(info - diff-menuconfig	vergleichbar mit "make -C openwrt menuconfig" - es wird jedoch anschließend ein diff der Änderungen angezeigt)
	$(info - doc			Dokumentation aktualisieren)
	$(info - translate		Übersetzungsdateien (opennet/po/de/*.po) aktualisieren)
	$(info - feeds			die Paket-Feeds (siehe openwrt/feeds.conf) neu einlesen)
	$(info - patch			die opennet-Patches via quilt anwenden (siehe ./patches/*.patch))
	$(info - unpatch		die opennet-Patches zurücknehmen (empfehlenswert vor jedem "git pull"))

list-archs:
	$(info $(ARCHS))

$(ARCHS): feeds translate
	@echo "Building for target architecture: $@"
	$(MAKE) "config-$@"
	@# alte Build-Images erzeugen (seit Chaos Calmer enthalten die Namen die Release-Nummer - er ist also veraenderlich)
	@[ -d "$(OPENWRT_DIR)/bin/$@" ] && find "$(OPENWRT_DIR)/bin/$@" -maxdepth 1 -type f -name "openwrt-*" -delete || true
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

doc: patch
	$(MAKE) -C $(CUSTOM_DOC_DIR)

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
	######### TODO: GPIO-SWITCH-HACK nach dem wechsel weg von Chaos Calmer entfernen ##########
	@# quilt kann keine Dateirechte erhalten - daher muessen wir es manuell nachpflegen
	chmod +x "$(OPENWRT_DIR)/package/base-files/files/etc/init.d/gpio_switch"

unpatch:
	@# revert all patches if there are applied ones
	@test -n "$(shell quilt applied 2>/dev/null)" && quilt pop -a || true

clean: unpatch
	$(MAKE) -C $(CUSTOM_DOC_DIR) clean

# VORSICHT: alle lokalen Aenderungen gehen verloren - dies sollte nie von einem
# Menschen ausgefuehrt werden - es ist lediglich fuer den trac-Autobuilder gedacht
autobuilder-clean:
	git fetch --all
	git reset --hard origin/master
	git submodule update
	@# eventuell Reste von (zwischenzeitlich geaenderten) Patches entfernen
	git submodule foreach git reset --hard
	git submodule foreach git clean -f
	@# eventuelle Patch-Reste entfernen (z.B. die feeds.conf)
	quilt pop -a -f || true
