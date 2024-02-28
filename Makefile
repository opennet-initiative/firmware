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
QUILT_BIN ?= $(shell which quilt)
PULL_SUBMODULES_BRANCH ?= openwrt-22.03


.PHONY: all clean patch unpatch menuconfig diff-menuconfig feeds init init-git init-git help list-archs doc quilt-check lint test

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
	$(info - pull-submodules	eingebundene git-submodules via 'git pull' aktualisieren)
	$(info - commit-submodules	aktualisierte git-submodules committen)
	$(info - lint			Code-Stil-Prüfungen durchführen)

list-archs:
	$(info $(ARCHS))

$(ARCHS): feeds translate
	@echo "Building for target architecture: $@"
	$(MAKE) "config-$@"
	@# Besonderheit für mikrotik: Wir haben zwei config Dateien, um Mikrotik zu bauen - opennet/config/(mikrotik|mikrotik24)
	@#   Wenn bspw. mikrotik gebaut wird und anschließend mikrotik24, dann löscht der Lauf von mikrotik24 die bin/*
	@#   Dateien des vorherigen mikrotik Laufs. Dies muessen wir verhindern.
	@if [ "$@" != "mikrotik" ] && [ "$@" != "mikrotik24" ]; then \
			[ -d "$(OPENWRT_DIR)/bin/$@" ] && find "$(OPENWRT_DIR)/bin/$@" -maxdepth 1 -type f -name "openwrt-*" -delete || true; \
			$(MAKE) -C "$(OPENWRT_DIR)" clean ; \
	fi
	$(MAKE) -C "$(OPENWRT_DIR)"
	
config-%:
	@[ -f "$(OPENWRT_DIR)/feeds.conf" ] || echo "**** FEHLER! DATEI feeds.conf FEHLT. Fuehre bitte 'make feeds' aus. ****"
	$(MAKE) -C "$(CONFIG_DIR)/" "$(patsubst config-%,%,$@)"

menuconfig:
	$(warning "'menuconfig' gibt es hier nicht - vielleicht meinst du eine der folgenden Aktionen?")
	$(warning " 		make -C openwrt menuconfig")
	$(warning " 		make config-ath79")
	$(warning " 		make diff-menuconfig")
	$(error "unbekanntes Ziel 'menuconfig'")

git-init:
	@# update submodules if necessary
	git submodule init --quiet
	git submodule update
	@[ -z "$$QUILT_DIFF_ARGS" ] && [ ! -e ~/.quiltrc ] && echo >&2 "HINWEIS: falls du Patches aendern moechtest, dann lies bitte doc/Entwicklung.md (Stichwort: 'quilt-Konfiguration')" || true

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
		([ -e "$$pot_filename" ] && [ ! -s "$$pot_filename" ] && rm "$$pot_filename") || true; \
	 done
	@"$(LUCI_DIR)/build/i18n-update.pl" "$(CUSTOM_PO_DIR)"

feeds: patch
	"$(OPENWRT_DIR)/scripts/feeds" update -a
	"$(OPENWRT_DIR)/scripts/feeds" install -a

quilt-check:
	# Pruefung: ist quilt installiert?
	@[ -n "$(QUILT_BIN)" -a -e "$(QUILT_BIN)" ]

patch: quilt-check
	@# apply all patches if there are unapplied ones
	@$(QUILT_BIN) push -a || [ $$? -ne 1 ]

unpatch: quilt-check
	@# revert all patches if there are applied ones
	@$(QUILT_BIN) pop -a || [ $$? -ne 1 ]

pull-submodules: unpatch
	@#use 'git submodule' for updating submodules. When using 'git pull' in submodule directory then the error 'detached head' occurs. There are two ways to solve this:
	@# 1. use 'git submodule update --remote --checkout'
	@# 2. go into every submodules directory, find out which remote branch it relies on, checkout this branch. 
	git submodule update --remote --checkout
	git submodule foreach git checkout "$(PULL_SUBMODULES_BRANCH)"
	git submodule foreach git pull
	@#for openwrt submodule checkout latest tag of branch
	git -C openwrt checkout "$(shell git -C openwrt describe --tags --abbrev=0)"

commit-submodules: unpatch
	detailed_diff=$$(git diff --submodule=short | awk '{ if ($$1 == "---") module=substr($$2, 3); if ($$1 == "-Subproject") old_commit=$$3; if ($$1 == "+Subproject") {new_commit=$$3; print(module":"); system("cd "module"; git --no-pager log --oneline "old_commit".."new_commit); print("")}}'); \
		modules=$$(git submodule status | awk '{print $$2}'); \
		[ -n "$$modules" ] \
		&& git commit --edit -m "Update upstream sources" -m "$$detailed_diff" -- $$modules

# style checks
lint:
	find opennet/packages -type f | opennet/tools/style-check.sh check-python
	find opennet/packages -type f | opennet/tools/style-check.sh check-shell
	# any unknown/unchecked files?
	! find opennet/packages -type f | opennet/tools/style-check.sh list-unknown | sed 's/^/UNKNOWN: /' | grep .

test: lint

clean: unpatch
	$(MAKE) -C $(CUSTOM_DOC_DIR) clean

distclean: clean
	$(MAKE) -C $(OPENWRT_DIR) distclean

# VORSICHT: alle lokalen Aenderungen gehen verloren - dies sollte nie von einem
# Menschen ausgefuehrt werden - es ist lediglich fuer den trac-Autobuilder gedacht
autobuilder-clean:
	git fetch --all
	git reset --hard origin/main
	@# eventuell Reste von (zwischenzeitlich geaenderten) Patches entfernen
	git submodule foreach git reset --hard
	git submodule foreach git clean -f
	git submodule update
	@# eventuelle Patch-Reste entfernen (z.B. die feeds.conf)
	quilt pop -a -f || true
	@# Entferne vorherige Build-Images. Aufgrund der unterschiedlichen Dateinamen pro Build
	@# wuerden sich sonst viele Dateien ansammeln.
	rm -rf "$(OPENWRT_DIR)/bin/targets"
	@# Entferne den vorherigen Zustand des "base-files"-Paket. Andernfalls enthaelt der
	@# naechste Build veraltete Versionsnummern.
	if [ -e "$(OPENWRT_DIR)/build_dir" ]; then \
		find "$(OPENWRT_DIR)/build_dir/" -type d -name base-files \
			| xargs --no-run-if-empty rm -rf; fi
