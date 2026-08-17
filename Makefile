# mySolat — build system
#
# Deliberately plain `swiftc` + `make`: no Xcode project and no SwiftPM manifest,
# so the app builds with only the Command Line Tools installed. Every target
# produces a universal (arm64 + x86_64) binary.
#
#   make            build a universal mySolat.app into build/
#   make run        build, install to ~/Applications, and launch
#   make native     fast single-architecture build for iterating
#   make zip        release archive + checksums.txt (what the updater downloads)
#   make dmg        drag-install disk image
#   make release    zip + dmg + checksums
#   make sign-release  sign the zip with the Ed25519 update key
#   make updater-keys  generate the Ed25519 key pair used by sign-release
#   make test        run the test suite
#   make screenshots regenerate the widget images used in the README
#   make clean

APP_NAME      := mySolat
WIDGET_NAME   := SolatWidget
BUNDLE_ID     := com.syahrul.mySolat
VERSION       ?= 1.0.0
BUILD_NUMBER  ?= 1
DEPLOY_TARGET := 13.0

BUILD_DIR   := build
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
APPEX       := $(APP_BUNDLE)/Contents/PlugIns/$(WIDGET_NAME).appex
DIST_DIR    := dist

SHARED_SRC := $(wildcard Sources/Shared/*.swift)
APP_SRC    := $(wildcard Sources/App/*.swift)
WIDGET_SRC := $(wildcard Sources/Widget/*.swift)
TEST_SRC   := $(wildcard Tests/*.swift)

ARCHS       := arm64 x86_64
# Frameworks are auto-linked from the `import` statements; listing them again here
# only produced duplicate LC_LOAD_DYLIB entries.
SWIFT_FLAGS := -O -parse-as-library -swift-version 5

# Ad-hoc signature. Set CODESIGN_ID="Developer ID Application: …" to sign properly.
CODESIGN_ID ?= -

.DEFAULT_GOAL := app
.PHONY: app native run install zip dmg release sign-release updater-keys clean check test screenshots version help

help:
	@grep -E '^#   make' Makefile | sed 's/^#   //'

# ---------------------------------------------------------------- app bundle

app: $(APP_BUNDLE)
	@echo "✓ $(APP_BUNDLE)  ($(VERSION) build $(BUILD_NUMBER), universal)"
	@lipo -archs $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME) | sed 's/^/  app:    /'
	@lipo -archs $(APPEX)/Contents/MacOS/$(WIDGET_NAME) | sed 's/^/  widget: /'

$(APP_BUNDLE): $(SHARED_SRC) $(APP_SRC) $(WIDGET_SRC) Resources/App-Info.plist Resources/Widget-Info.plist Resources/zones.json $(BUILD_DIR)/.mode-universal
	@$(MAKE) --no-print-directory bundle ARCH_MODE=universal

# Both modes write to the same bundle path, so a mode marker forces a rebuild when
# switching between them — otherwise `make` after `make native` would leave the
# single-architecture binary in place and silently ship it.
$(BUILD_DIR)/.mode-universal:
	@mkdir -p $(BUILD_DIR)
	@rm -f $(BUILD_DIR)/.mode-native
	@touch $@

native:
	@mkdir -p $(BUILD_DIR)
	@rm -f $(BUILD_DIR)/.mode-universal
	@touch $(BUILD_DIR)/.mode-native
	@$(MAKE) --no-print-directory bundle ARCH_MODE=native
	@echo "✓ $(APP_BUNDLE)  (native only — use 'make' for a universal build)"

# Assembles the whole bundle. ARCH_MODE selects universal vs. host-only.
.PHONY: bundle
bundle:
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS \
	          $(APP_BUNDLE)/Contents/Resources \
	          $(APPEX)/Contents/MacOS \
	          $(APPEX)/Contents/Resources \
	          $(BUILD_DIR)/obj

	@echo "→ compiling $(APP_NAME) ($(ARCH_MODE))"
	@$(MAKE) --no-print-directory link \
	    OUT=$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME) \
	    SRC="$(SHARED_SRC) $(APP_SRC)" \
	    MODULE=$(APP_NAME)

	@echo "→ compiling $(WIDGET_NAME) ($(ARCH_MODE))"
	@# An app extension must enter through NSExtensionMain, which performs the
	@# classic NSExtension bootstrap and lets WidgetKit hand the host our
	@# WidgetBundle. Left at the default `_main`, Swift's @main instead takes the
	@# newer ExtensionFoundation path, which has no EXAppExtensionAttributes to
	@# match and aborts with "Unrecognized extension type" — so the widget never
	@# reports its configuration and never shows up in the widget gallery.
	@# Apple's own widget binaries link the same way.
	@$(MAKE) --no-print-directory link \
	    OUT=$(APPEX)/Contents/MacOS/$(WIDGET_NAME) \
	    SRC="$(SHARED_SRC) $(WIDGET_SRC)" \
	    MODULE=$(WIDGET_NAME) \
	    EXTRA="-Xlinker -e -Xlinker _NSExtensionMain"

	@echo "→ assembling resources"
	@sed -e 's/__VERSION__/$(VERSION)/g' -e 's/__BUILD__/$(BUILD_NUMBER)/g' \
	    Resources/App-Info.plist > $(APP_BUNDLE)/Contents/Info.plist
	@sed -e 's/__VERSION__/$(VERSION)/g' -e 's/__BUILD__/$(BUILD_NUMBER)/g' \
	    Resources/Widget-Info.plist > $(APPEX)/Contents/Info.plist
	@printf 'APPL????' > $(APP_BUNDLE)/Contents/PkgInfo
	@cp Resources/zones.json $(APP_BUNDLE)/Contents/Resources/
	@cp Resources/zones.json $(APPEX)/Contents/Resources/
	@cp Resources/logo.png $(APP_BUNDLE)/Contents/Resources/
	@$(MAKE) --no-print-directory icon

	@echo "→ signing ($(CODESIGN_ID))"
	@# Extended attributes on copied resources make codesign refuse the bundle.
	@xattr -cr $(APP_BUNDLE)
	@# Inside-out: the nested appex must be sealed before the outer app.
	@codesign --force --timestamp=none \
	    --entitlements Resources/SolatWidget.entitlements \
	    --sign "$(CODESIGN_ID)" $(APPEX)
	@codesign --force --timestamp=none \
	    --entitlements Resources/mySolat.entitlements \
	    --sign "$(CODESIGN_ID)" $(APP_BUNDLE)
	@codesign --verify --deep --strict $(APP_BUNDLE)

# Compiles SRC for each architecture and lipos the slices together.
.PHONY: link
link:
ifeq ($(ARCH_MODE),native)
	@swiftc $(SWIFT_FLAGS) -module-name $(MODULE) \
	    -target $$(uname -m)-apple-macosx$(DEPLOY_TARGET) $(EXTRA) \
	    -o $(OUT) $(SRC)
else
	@for arch in $(ARCHS); do \
	  swiftc $(SWIFT_FLAGS) -module-name $(MODULE) \
	      -target $$arch-apple-macosx$(DEPLOY_TARGET) $(EXTRA) \
	      -o $(BUILD_DIR)/obj/$(MODULE)-$$arch $(SRC) || exit 1; \
	done
	@lipo -create $(foreach a,$(ARCHS),$(BUILD_DIR)/obj/$(MODULE)-$(a)) -output $(OUT)
endif

# Builds AppIcon.icns from Resources/logo.png (cached — the logo rarely changes).
.PHONY: icon
icon: $(BUILD_DIR)/AppIcon.icns
	@cp $(BUILD_DIR)/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns

$(BUILD_DIR)/AppIcon.icns: Resources/logo.png scripts/make-icon.sh
	@mkdir -p $(BUILD_DIR)
	@scripts/make-icon.sh $@ >/dev/null

# ---------------------------------------------------------------- install/run

install: app
	@mkdir -p $$HOME/Applications
	@rm -rf $$HOME/Applications/$(APP_NAME).app
	@cp -R $(APP_BUNDLE) $$HOME/Applications/
	@echo "✓ installed to ~/Applications/$(APP_NAME).app"

run: install
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@sleep 0.5
	@open $$HOME/Applications/$(APP_NAME).app
	@echo "✓ launched — look for the moon icon in your menu bar"

# ---------------------------------------------------------------- distribution

# The updater downloads this exact archive and verifies it against checksums.txt.
zip: app
	@mkdir -p $(DIST_DIR)
	@rm -f $(DIST_DIR)/$(APP_NAME)-$(VERSION)-universal.zip
	@ditto -c -k --sequesterRsrc --keepParent \
	    $(APP_BUNDLE) $(DIST_DIR)/$(APP_NAME)-$(VERSION)-universal.zip
	@cd $(DIST_DIR) && shasum -a 256 $(APP_NAME)-$(VERSION)-universal.zip > checksums.txt
	@cd $(DIST_DIR) && [ -f $(APP_NAME)-$(VERSION).dmg ] && \
	    shasum -a 256 $(APP_NAME)-$(VERSION).dmg >> checksums.txt || true
	@echo "✓ $(DIST_DIR)/$(APP_NAME)-$(VERSION)-universal.zip"
	@cat $(DIST_DIR)/checksums.txt | sed 's/^/  /'

dmg: app
	@mkdir -p $(DIST_DIR)
	@scripts/make-dmg.sh "$(APP_BUNDLE)" "$(DIST_DIR)/$(APP_NAME)-$(VERSION).dmg" "$(APP_NAME)"
	@echo "✓ $(DIST_DIR)/$(APP_NAME)-$(VERSION).dmg"

release: dmg zip
	@echo "✓ release artifacts in $(DIST_DIR)/"

# Signs the release zip with the Ed25519 key so the in-app updater can verify it.
sign-release:
	@scripts/sign-update.sh "$(DIST_DIR)/$(APP_NAME)-$(VERSION)-universal.zip"

updater-keys:
	@scripts/generate-update-keys.sh

# ---------------------------------------------------------------- misc

test: $(BUILD_DIR)/solat-tests
	@$(BUILD_DIR)/solat-tests

# Regenerates the widget images in the README from the real views and the real
# cached prayer times. SolatWidget.swift is excluded because its @main would
# collide with the renderer's.
WIDGET_VIEW_SRC := $(filter-out Sources/Widget/SolatWidget.swift,$(WIDGET_SRC))

screenshots: $(BUILD_DIR)/render-widgets
	@$(BUILD_DIR)/render-widgets docs/screenshots

$(BUILD_DIR)/render-widgets: $(SHARED_SRC) $(WIDGET_VIEW_SRC) scripts/render-widgets.swift
	@mkdir -p $(BUILD_DIR)
	@swiftc -swift-version 5 -parse-as-library \
	    -target $$(uname -m)-apple-macosx$(DEPLOY_TARGET) \
	    -module-name RenderWidgets \
	    -o $@ $(SHARED_SRC) $(WIDGET_VIEW_SRC) scripts/render-widgets.swift

$(BUILD_DIR)/solat-tests: $(SHARED_SRC) $(TEST_SRC)
	@mkdir -p $(BUILD_DIR)
	@swiftc -swift-version 5 -parse-as-library \
	    -target $$(uname -m)-apple-macosx$(DEPLOY_TARGET) \
	    -module-name SolatTests -framework AppKit \
	    -o $@ $(SHARED_SRC) $(TEST_SRC)

check:
	@echo "→ type-checking (no output means clean)"
	@swiftc -typecheck -swift-version 5 \
	    -target $$(uname -m)-apple-macosx$(DEPLOY_TARGET) \
	    -module-name $(APP_NAME) $(SHARED_SRC) $(APP_SRC)
	@swiftc -typecheck -swift-version 5 \
	    -target $$(uname -m)-apple-macosx$(DEPLOY_TARGET) \
	    -module-name $(WIDGET_NAME) $(SHARED_SRC) $(WIDGET_SRC)
	@echo "✓ both targets type-check"

version:
	@echo "$(VERSION) (build $(BUILD_NUMBER))"

clean:
	@rm -rf $(BUILD_DIR) $(DIST_DIR)
	@echo "✓ cleaned"
