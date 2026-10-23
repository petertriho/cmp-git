# Not `?=`: Neovim sets $NVIM to its server address in :terminal and in jobs. The flake sets $CMP_GIT_NVIM.
NVIM := $(or $(CMP_GIT_NVIM),nvim)
STYLUA ?= stylua
SELENE ?= selene
LUA_LANGUAGE_SERVER ?= lua-language-server
MINI_VERSION := v0.18.0
MINI_DIR := deps/mini.nvim
LUA_PATHS := lua plugin tests benchmarks
REF ?= main

.PHONY: test-deps test test-integration test-file bench bench-compare format format-check lint typecheck ci

test-deps:
	@if [ ! -d "$(MINI_DIR)/.git" ]; then \
		mkdir -p deps; \
		git clone --filter=blob:none --branch "$(MINI_VERSION)" --depth 1 \
			https://github.com/nvim-mini/mini.nvim.git "$(MINI_DIR)"; \
	fi
	@if [ "$$(git -C "$(MINI_DIR)" describe --tags --exact-match 2>/dev/null)" != "$(MINI_VERSION)" ]; then \
		git -C "$(MINI_DIR)" fetch --depth 1 origin tag "$(MINI_VERSION)"; \
		git -C "$(MINI_DIR)" checkout --detach "$(MINI_VERSION)"; \
	fi

# Runs the files in tests/ without tests/integration/
test: test-deps
	$(NVIM) --headless --noplugin -u tests/minimal_init.lua -c "lua MiniTest.run()"

# Runs the files in tests/integration/. They need the CLIs and the servers of `nix develop .#integration`.
test-integration: test-deps
	TEST_SUITE=integration $(NVIM) --headless --noplugin -u tests/minimal_init.lua -c "lua MiniTest.run()"

# Also runs a file in tests/integration/
test-file: test-deps
	@test -n "$(FILE)" || (printf '%s\n' 'Usage: make test-file FILE=tests/**/test_*.lua' >&2; exit 2)
	TEST_FILE="$(FILE)" $(NVIM) --headless --noplugin -u tests/minimal_init.lua \
		-c "lua MiniTest.run_file(vim.env.TEST_FILE)"

# Prints one line for each case. Options go in BENCH_ARGS, for example BENCH_ARGS="--filter keystroke".
bench:
	$(NVIM) --headless --clean -l benchmarks/run.lua $(BENCH_ARGS)

# Compares the benchmarks of REF with the working tree
bench-compare:
	CMP_GIT_NVIM="$(NVIM)" scripts/bench-compare.sh "$(REF)"

format:
	$(STYLUA) $(LUA_PATHS)

format-check:
	$(STYLUA) --check $(LUA_PATHS)

lint:
	$(SELENE) $(LUA_PATHS)

# LuaLS reads the Neovim API types from $VIMRUNTIME/lua, see .luarc.json
typecheck: test-deps
	VIMRUNTIME="$$($(NVIM) --clean --headless -c 'lua io.write(vim.env.VIMRUNTIME)' -c q 2>&1)" \
		$(LUA_LANGUAGE_SERVER) --check=. --checklevel=Warning --check_format=pretty

ci: format-check lint typecheck test
