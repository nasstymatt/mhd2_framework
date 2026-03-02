# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Language & Toolchain

This project is written in **C3** (a modern C-like language). The compiler is `c3c`.

- Build: `c3c build tierlister`
- Run: `./build/tierlister`
- Build configuration: `project.json`

## Third-Party Libraries (Git Submodules)

All three are static libraries linked from `third_party/`:

- `third_party/libmicrohttpd2` — HTTP server (must be built with autotools: `./autogen.sh && ./configure && make`)
- `third_party/lua` — Lua 5.4 (build with `make`)
- `third_party/sqlite` — SQLite3 (build with `make`)

Linker paths and library names are configured in `project.json` under `linker-search-paths` and `linked-libraries`.

## Template System

HTML templates live in `web/views/` and use a Jinja-like syntax:
- `{% lua code %}` — raw Lua statement (loops, conditionals, etc.)
- `{{ expression }}` — output expression (calls `tostring()`)
- `{% extends("base.html") %}` / `{% block("name") %}` / `{% endblock() %}` — inheritance
- `{% include("partial.html") %}` — partial inclusion
- `{% yield("name") %}` — in base templates, renders a named block

Templates are **transpiled to Lua** by `scripts/tpl_transpile.lua`:

```
lua scripts/tpl_transpile.lua
```

This writes `build/web/views/**/*.lua` files. The runtime template engine (`src/templates/templates.c3`) reads these `.lua` files at request time, with hot-reload based on file timestamps.

Per-thread Lua states are created lazily via a `tlocal` variable. Only `base`, `table`, `string`, and `math` Lua stdlib modules are loaded (no `io`, `os`, `debug`, etc.).

## Architecture Overview

Request flow: MHD2 callback → `router::mhd2::handleRequest` → `Router.handleRequest` → `Context.next()` iterates through `Step`s.

### Router (`src/router/`)

The router uses an **interface-based pipeline** of `Step` objects (defined in `router::steps`):

- `RouteStep` — matches method + path pattern (`:param` segments), populates `ctx.req.params`
- `MiddlewareStep` — runs a handler unconditionally
- `MountStaticFolderStep` — serves files from a directory at a URL mount point

Routes are registered on a `Router` via `.get()`, `.post()`, `.put()`, `.delete()`, `.use()`, `.handleStatic()`.

Each step calls `ctx.next()` to pass control to the next step (or sets a response to short-circuit). Default status is 200; no matching step results in 404.

### Context Macros (`src/router/context.c3`)

Route handlers receive `Context *ctx`. Key macros:
- `ctx.@render("template.html", "key", value, ...)` — render Lua template with variables
- `ctx.@form("field")` — read POST form field
- `ctx.@redirect("/path/:id", id)` — redirect with param substitution
- `ctx.@text(str)` / `ctx.@html(str)` — raw text/HTML response
- `ctx.@error("msg", sc: 400)` — error response
- `ctx.@not_found()` — 404

### Database (`src/db/sqlite3.c3i`)

C3 bindings for SQLite3 with macro-based query helpers:
- `sqlite3::@query_all{ModelType}(db, "SELECT ...", args...)` — returns `ModelType[]`
- `sqlite3::@query_one{ModelType}(db, "SELECT ...", args...)` — returns `ModelType?`
- `sqlite3::@insert(db, "INSERT ...", args...)` — returns `long` (last insert row ID)
- `sqlite3::@update(db, "UPDATE ...", args...)` / `@delete(...)` — asserts DONE
- `sqlite3::@transaction(db) { ... }` — wraps body in BEGIN IMMEDIATE / COMMIT / ROLLBACK
- `sqlite3::@exec_ok(db, sql)` — exec with no callback

Model structs in `src/db/models.c3` are mapped automatically by column name. Supported field types: `String`, `bool`, signed/unsigned ints, floats.

The database is opened in `@init` and closed in `@finalizer` functions in `src/main.c3`. Schema from `sql/schema.sql` is embedded at compile time via `$embed("../sql/schema.sql")` and applied on startup.

Database file: `./data/app.db` (WAL mode, foreign keys on).

### MHD2 Integration (`src/router/mhd2_wrapper.c3`)

Runs 8 worker threads. POST/PUT bodies up to 16 KB are buffered via `actionParsePost`; larger bodies abort the request. Each request uses `@pool_init(mem, 64KB)` for arena allocation. Form data is populated into `ctx.req.formData` before the handler is called.

### C3 Patterns Used in This Codebase

- `.c3i` files — C interface bindings with `@cname("c_function_name")`
- `@init` / `@finalizer` attributes — module-level lifecycle functions
- `$embed("file")` — compile-time file embedding
- `@pool_init(mem, size)` — scoped arena allocator
- `tmem` / `tconcat` / `tsplit` / `tcopy` — temporary allocator variants
- Macros prefixed with `@` (e.g., `@render`, `@insert`, `@transaction`)
- Compile-time generics via `<TModel>` and `$typeof`, `$kindof`, `$foreach`
