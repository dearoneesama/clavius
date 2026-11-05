LUA ?= luajit
LUAROCKS ?= luarocks
CARGO ?= cargo

STYLUA_VERSION = 2.6.0

# Dev tools are installed into this project-local tree and take precedence on PATH.
TREE = lua_modules
export PATH := $(CURDIR)/$(TREE)/bin:$(PATH)

.PHONY: run test lint fmt dev

run:
	@./bin/clavius $(ARGS)

test:
	@$(LUA) tests/run.lua

lint:
	luacheck src tests bin/*

fmt:
	stylua src tests bin/*

# Install dev tools into ./$(TREE).
# Lua dev deps are the rockspec's test_dependencies, installed by `luarocks test --prepare`.
# LuaRocks < 3.10 ignores --tree when checking installed deps, so `test --prepare` fails there;
# on those versions install each test dependency from the rockspec directly instead.
LUAROCKS_PREPARE_MIN = 3.10.0
ROCKSPEC = $(firstword $(wildcard *.rockspec))
dev:
	@lr_version=$$($(LUAROCKS) --version | head -1 | awk '{print $$NF}'); \
	if printf '%s\n' $(LUAROCKS_PREPARE_MIN) "$$lr_version" | sort -V -C; then \
		echo "$(LUAROCKS) --tree $(TREE) test --prepare"; \
		$(LUAROCKS) --tree $(TREE) test --prepare; \
	else \
		echo "LuaRocks $$lr_version < $(LUAROCKS_PREPARE_MIN): installing test_dependencies directly"; \
		$(LUA) -e "local e = {} local f = assert(loadfile('$(ROCKSPEC)')) setfenv(f, e) f() \
			for _, d in ipairs(e.test_dependencies or {}) do print((d:gsub('%s*==%s*', ' '))) end" \
		| while read -r rock version; do $(LUAROCKS) --tree $(TREE) install $$rock $$version || exit 1; done; \
	fi
	$(CARGO) install stylua --version $(STYLUA_VERSION) --locked --root $(TREE)
