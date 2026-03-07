.PHONY: all dev release deps deps-release clean clean-deps

LIB_MHD_DEV    = third_party/libmicrohttpd2/build-dev/src/mhd2/.libs/libmicrohttpd2.a
LIB_MHD_REL    = third_party/libmicrohttpd2/build-release/src/mhd2/.libs/libmicrohttpd2.a
LIB_LUA        = third_party/lua/liblua.a
LIB_SQLITE_DEV = third_party/sqlite/libsqlite3.a
LIB_SQLITE_REL = third_party/sqlite/build-release/libsqlite3.a

# ── Default: build deps + dev binary ──────────────────────────────────────────

all: deps
	c3c build tierlister --trust=full

release: deps-release
	c3c build tierlister-release --trust=full

# ── App only (skip dep check) ─────────────────────────────────────────────────

dev:
	c3c build tierlister

# ── Deps ──────────────────────────────────────────────────────────────────────

deps:         $(LIB_MHD_DEV) $(LIB_LUA) $(LIB_SQLITE_DEV)
deps-release: $(LIB_MHD_REL) $(LIB_LUA) $(LIB_SQLITE_REL)

# dev: out-of-source, plain build, all features, easier to debug
$(LIB_MHD_DEV):
	cd third_party/libmicrohttpd2 && ./bootstrap
	mkdir -p third_party/libmicrohttpd2/build-dev
	cd third_party/libmicrohttpd2/build-dev && \
		../configure \
			--disable-maintainer-mode \
			--disable-https \
			--disable-basic-auth \
			--disable-digest-auth \
			--disable-httpupgrade \
			--disable-cookie \
			--disable-http2 \
			--disable-doc \
			--disable-examples \
			--disable-tools && \
		$(MAKE)

# release: out-of-source, compact code, no error messages or log strings
$(LIB_MHD_REL):
	cd third_party/libmicrohttpd2 && ./bootstrap
	mkdir -p third_party/libmicrohttpd2/build-release
	cd third_party/libmicrohttpd2/build-release && \
		../configure \
			--disable-maintainer-mode \
			--disable-https \
			--disable-basic-auth \
			--disable-digest-auth \
			--disable-httpupgrade \
			--disable-cookie \
			--disable-http2 \
			--disable-messages \
			--disable-log-messages \
			--enable-compact-code \
			--enable-build-type=release-compact \
			--disable-doc \
			--disable-examples \
			--disable-tools && \
		$(MAKE)

$(LIB_LUA):
	$(MAKE) -C third_party/lua liblua.a CFLAGS="-O2 -DLUA_USE_LINUX -ffunction-sections -fdata-sections"

# ── SQLite ─────────────────────────────────────────────────────────────────────

# dev: plain build, all features, easier to debug
$(LIB_SQLITE_DEV):
	cd third_party/sqlite && \
		./configure && \
		$(MAKE) libsqlite3.a

# release: out-of-source, strips every SQLite feature unused by this app.
# configure flags: static-only, no extensions (load/math/json/carray/tcl/readline).
# CFLAGS omissions (all verified unused by this app):
#   DEFAULT_MEMSTATUS=0  — memory usage tracking (sqlite3_memory_used etc.)
#   OMIT_UTF16           — only UTF-8 used
#   OMIT_DECLTYPE        — sqlite3_column_decltype not bound
#   OMIT_DEPRECATED      — no deprecated API calls
#   OMIT_PROGRESS_CALLBACK — no progress hooks
#   OMIT_TRACE           — no trace/profile hooks
#   OMIT_AUTHORIZATION   — no auth callbacks
#   OMIT_ANALYZE         — ANALYZE command never called
#   OMIT_ALTERTABLE      — no ALTER TABLE in schema
#   OMIT_COMPLETE        — sqlite3_complete not bound
#   OMIT_GET_TABLE       — using prepare_v2, not sqlite3_get_table
#   OMIT_INCRBLOB        — no incremental blob I/O
#   OMIT_BLOB_LITERAL    — no x'...' blob literals in SQL
#   OMIT_EXPLAIN         — no EXPLAIN at runtime
#   OMIT_CTE             — no WITH clauses in SQL
#   OMIT_WINDOWFUNC      — no window functions
SQLITE_REL_CFLAGS = \
	-O2 \
	-DSQLITE_DEFAULT_MEMSTATUS=0 \
	-DSQLITE_OMIT_UTF16 \
	-DSQLITE_OMIT_DECLTYPE \
	-DSQLITE_OMIT_DEPRECATED \
	-DSQLITE_OMIT_PROGRESS_CALLBACK \
	-DSQLITE_OMIT_TRACE \
	-DSQLITE_OMIT_AUTHORIZATION \
	-DSQLITE_OMIT_ANALYZE \
	-DSQLITE_OMIT_ALTERTABLE \
	-DSQLITE_OMIT_COMPLETE \
	-DSQLITE_OMIT_GET_TABLE \
	-DSQLITE_OMIT_INCRBLOB \
	-DSQLITE_OMIT_BLOB_LITERAL \
	-DSQLITE_OMIT_EXPLAIN \
	-DSQLITE_OMIT_CTE \
	-DSQLITE_OMIT_WINDOWFUNC

$(LIB_SQLITE_REL):
	mkdir -p third_party/sqlite/build-release
	cd third_party/sqlite/build-release && \
		../configure \
			--disable-shared \
			--disable-load-extension \
			--disable-math \
			--disable-json \
			--disable-carray \
			--disable-tcl \
			--disable-readline \
			CFLAGS="$(SQLITE_REL_CFLAGS)" && \
		$(MAKE) libsqlite3.a

# ── Clean ─────────────────────────────────────────────────────────────────────

clean:
	rm -rf build/

clean-deps:
	rm -rf third_party/libmicrohttpd2/build-dev
	rm -rf third_party/libmicrohttpd2/build-release
	$(MAKE) -C third_party/lua clean
	$(MAKE) -C third_party/sqlite clean
	rm -rf third_party/sqlite/build-release
