NVIM ?= nvim
STYLUA ?= stylua
SELENE ?= selene
LUA_LANGUAGE_SERVER ?= lua-language-server
MINI_VERSION := v0.18.0
MINI_DIR := deps/mini.nvim
LUA_PATHS := lua tests

.PHONY: test-deps test test-file format format-check lint typecheck ci

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

test: test-deps
	$(NVIM) --headless --noplugin -u tests/minimal_init.lua -c "lua MiniTest.run()"

test-file: test-deps
	@test -n "$(FILE)" || (printf '%s\n' 'Usage: make test-file FILE=tests/**/test_*.lua' >&2; exit 2)
	TEST_FILE="$(FILE)" $(NVIM) --headless --noplugin -u tests/minimal_init.lua \
		-c "lua MiniTest.run_file(vim.env.TEST_FILE)"

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
