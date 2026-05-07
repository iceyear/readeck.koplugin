REPO_DIR := $(CURDIR)
PLUGIN_DIR := $(REPO_DIR)/readeck.koplugin
ROCKSPEC := readeck-koplugin-dev-0.1-1.rockspec

KOREADER_DIR ?= references/koreader
KOREADER_BUILD_DIR ?= $(KOREADER_DIR)/koreader-emulator-x86_64-pc-linux-gnu-debug/koreader
KOREADER_LUAJIT := $(KOREADER_BUILD_DIR)/luajit
KOREADER_RUNTIME_PROBE := $(REPO_DIR)/spec/koreader_runtime_probe.lua
KOREADER_NETWORK_PROBE := $(REPO_DIR)/spec/koreader_network_probe.lua
MOCK_READECK_PORT ?= 18080

LUA_PATH := ./readeck.koplugin/?.lua;$(LUA_PATH)
export LUA_PATH

BUSTED ?= busted
LUACHECK ?= luacheck
STYLUA ?= stylua

LUA_SOURCES := readeck.koplugin/main.lua readeck.koplugin/_meta.lua readeck.koplugin/readeck spec

.PHONY: check deps test lint format format-check koreader-build koreader-smoke koreader-stub-smoke koreader-runtime-smoke koreader-network-smoke

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

koreader-network-smoke:
	@if [ ! -x "$(KOREADER_LUAJIT)" ]; then \
		echo "KOReader runtime not found at $(KOREADER_BUILD_DIR). Run 'make koreader-build' first or set KOREADER_BUILD_DIR."; \
		exit 1; \
	fi
	set -e; \
	run_probe() { \
		version="$$1"; \
		port="$$2"; \
		legacy="$$3"; \
		python3 "$(REPO_DIR)/spec/mock_readeck_server.py" --port "$$port" --version "$$version" & \
		server_pid=$$!; \
		trap 'kill $$server_pid 2>/dev/null || true' EXIT INT TERM; \
		sleep 0.5; \
		if ! kill -0 $$server_pid 2>/dev/null; then \
			echo "Mock Readeck server failed to start on port $$port."; \
			exit 1; \
		fi; \
		(cd "$(KOREADER_BUILD_DIR)" && READECK_PLUGIN_DIR="$(PLUGIN_DIR)" READECK_MOCK_URL="http://127.0.0.1:$$port" READECK_EXPECT_VERSION="$$version" READECK_EXPECT_LEGACY="$$legacy" ./luajit "$(KOREADER_NETWORK_PROBE)"); \
		kill $$server_pid 2>/dev/null || true; \
		wait $$server_pid 2>/dev/null || true; \
		trap - EXIT INT TERM; \
	}; \
	run_probe "0.22.2" "$(MOCK_READECK_PORT)" "0"; \
	legacy_port=$$(( $(MOCK_READECK_PORT) + 1 )); \
	run_probe "0.22.1" "$$legacy_port" "1"

koreader-smoke: koreader-stub-smoke
	@if [ -x "$(KOREADER_LUAJIT)" ]; then \
		$(MAKE) koreader-runtime-smoke; \
	else \
		echo "Skipping KOReader runtime smoke: $(KOREADER_BUILD_DIR) is not built."; \
	fi
