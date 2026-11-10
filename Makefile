LUA ?= luajit
LUAROCKS ?= luarocks
CARGO ?= cargo

STYLUA_VERSION = 2.6.0

# Dependencies and dev tools are installed into this project-local tree, which takes precedence over
# system-wide installs.
TREE = lua_modules
export PATH := $(CURDIR)/$(TREE)/bin:$(PATH)
export LUA_PATH := $(CURDIR)/$(TREE)/share/lua/5.1/?.lua;$(CURDIR)/$(TREE)/share/lua/5.1/?/init.lua;;
export LUA_CPATH := $(CURDIR)/$(TREE)/lib/lua/5.1/?.so;;

# Every Lua file that luacheck and stylua look at.
LUA_SOURCES = src tests schema bin/clavius

.PHONY: run test lint fmt gen dev

run:
	@./bin/clavius $(ARGS)

test:
	busted --lua=$(LUA)

lint:
	luacheck $(LUA_SOURCES)
	stylua --check $(LUA_SOURCES)

fmt:
	stylua $(LUA_SOURCES)

# Regenerate the node classes from schema/.
gen:
	$(LUA) schema/gen.lua

# Install the runtime dependencies, the test dependencies and stylua into ./$(TREE).
# On LuaRocks >= 3.10, `install --only-deps` and `test --prepare` read both lists from the rockspec.
# LuaRocks < 3.10 ignores --tree when checking installed deps, so `test --prepare` fails there;
# on those versions install each dependency from the rockspec directly instead.
LUAROCKS_PREPARE_MIN = 3.10.0
ROCKSPEC = $(firstword $(wildcard *.rockspec))
dev:
	@lr_version=$$($(LUAROCKS) --version | head -1 | awk '{print $$NF}'); \
	if printf '%s\n' $(LUAROCKS_PREPARE_MIN) "$$lr_version" | sort -V -C; then \
		echo "$(LUAROCKS) --tree $(TREE) install --only-deps $(ROCKSPEC)"; \
		$(LUAROCKS) --tree $(TREE) install --only-deps $(ROCKSPEC) || exit 1; \
		echo "$(LUAROCKS) --tree $(TREE) test --prepare"; \
		$(LUAROCKS) --tree $(TREE) test --prepare; \
	else \
		echo "LuaRocks $$lr_version < $(LUAROCKS_PREPARE_MIN): installing dependencies directly"; \
		$(LUA) -e "local e = {} local f = assert(loadfile('$(ROCKSPEC)')) setfenv(f, e) f() \
			for _, list in ipairs({ e.dependencies or {}, e.test_dependencies or {} }) do \
				for _, d in ipairs(list) do if not d:match('^lua%s') then print((d:gsub('%s*==%s*', ' '))) end end \
			end" \
		| while read -r rock version; do $(LUAROCKS) --tree $(TREE) install $$rock $$version || exit 1; done; \
	fi
	$(CARGO) install stylua --version $(STYLUA_VERSION) --locked --root $(TREE)
