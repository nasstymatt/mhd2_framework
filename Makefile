.PHONY: all dev release deps lua sqlite mhd2 clean clean-deps

LIB_MHD    = third_party/libmicrohttpd2/src/mhd2/.libs/libmicrohttpd2.a
LIB_LUA    = third_party/lua/liblua.a
LIB_SQLITE = third_party/sqlite/libsqlite3.a

# ── Default: build deps + dev binary ──────────────────────────────────────────

all: deps
	c3c build tierlister --trust=full

release: deps
	c3c build tierlister-release --trust=full

# ── App only (skip dep check) ─────────────────────────────────────────────────

dev:
	c3c build tierlister

# ── Deps ──────────────────────────────────────────────────────────────────────

deps: $(LIB_MHD) $(LIB_LUA) $(LIB_SQLITE)

$(LIB_MHD):
	cd third_party/libmicrohttpd2 && \
		./configure --disable-https && \
		$(MAKE)

$(LIB_LUA):
	$(MAKE) -C third_party/lua liblua.a

$(LIB_SQLITE):
	$(MAKE) -C third_party/sqlite libsqlite3.a

# ── Clean ─────────────────────────────────────────────────────────────────────

clean:
	rm -rf build/

clean-deps:
	$(MAKE) -C third_party/libmicrohttpd2 clean
	$(MAKE) -C third_party/lua clean
	$(MAKE) -C third_party/sqlite clean
