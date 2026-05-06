REPO_DIR := $(CURDIR)
PLUGIN_DIR := $(REPO_DIR)/readeck.koplugin
ROCKSPEC := readeck-koplugin-dev-0.1-1.rockspec

KOREADER_DIR ?= references/koreader
KOREADER_BUILD_DIR ?= $(KOREADER_DIR)/koreader-emulator-x86_64-pc-linux-gnu-debug/koreader
KOREADER_LUAJIT := $(KOREADER_BUILD_DIR)/luajit
KOREADER_RUNTIME_PROBE := $(REPO_DIR)/spec/koreader_runtime_probe.lua

LUA_PATH := ./readeck.koplugin/?.lua;$(LUA_PATH)
export LUA_PATH

BUSTED ?= busted
LUACHECK ?= luacheck
STYLUA ?= stylua

LUA_SOURCES := readeck.koplugin/main.lua readeck.koplugin/_meta.lua readeck.koplugin/readeck spec

.PHONY: check deps test lint format format-check koreader-build koreader-smoke koreader-stub-smoke koreader-runtime-smoke

check: lint format-check test

deps:
	luarocks install --only-deps $(ROCKSPEC)

test:
	$(BUSTED) spec

lint:
	$(LUACHECK) readeck.koplugin/main.lua readeck.koplugin/_meta.lua readeck.koplugin/readeck spec

format:
	$(STYLUA) $(LUA_SOURCES)

format-check:
	$(STYLUA) --check $(LUA_SOURCES)

koreader-build:
	cd "$(KOREADER_DIR)" && ./kodev build emulator

koreader-stub-smoke:
	$(BUSTED) spec/koreader_smoke_spec.lua

koreader-runtime-smoke:
	@if [ ! -x "$(KOREADER_LUAJIT)" ]; then \
		echo "KOReader runtime not found at $(KOREADER_BUILD_DIR). Run 'make koreader-build' first or set KOREADER_BUILD_DIR."; \
		exit 1; \
	fi
	cd "$(KOREADER_BUILD_DIR)" && READECK_PLUGIN_DIR="$(PLUGIN_DIR)" ./luajit "$(KOREADER_RUNTIME_PROBE)"

koreader-smoke: koreader-stub-smoke
	@if [ -x "$(KOREADER_LUAJIT)" ]; then \
		$(MAKE) koreader-runtime-smoke; \
	else \
		echo "Skipping KOReader runtime smoke: $(KOREADER_BUILD_DIR) is not built."; \
	fi
