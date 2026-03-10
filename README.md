# mhd2_framework
A minimal web "framework" (thin wrapper) for [C3](https://c3-lang.org), built around 
[libmicrohttpd2](https://www.gnu.org/software/libmicrohttpd/), SQLite, and Lua templates.

**Not a library nor a fully functional framework. This is just my way of doing things. Copy it, modify it, own it.**

## What it is
A working foundation for SSR web apps in C3. Compiles to a single static binary.
**2.8MB** stripped binary including Lua VM, SQLite, embedded assets and templates.

## What's inside
- **Router** — middleware chain, route params, static file serving
- **SQLite macro layer** — compile-time reflection struct mapping:
```c3
TierList[] lists = sqlite3::@query_all{TierList}(db, "SELECT * FROM tierlists");
```
- **Lua template engine** — `extends`, `block`, `include`, hot reload in dev, 
  per-thread Lua VM, file-watch cache invalidation.
- **Request lifecycle** — arena-per-request memory, multipart file uploads, 
  form, headers, query parsing.
- **MHD2 wrapper** — worker thread pool, clean separation from router.

## Basic Example

**Define a model:**
```c3
struct Post
{
  long   id;
  String title;
  String body;
  String created_at;
}
```

**Query and render:**
```c3
module mymodule;

import router;
import db::models;
import db::sqlite3;

SQlite3* db;

fn void init_db() @local @init
{
  if (sqlite3::open_v2("./app.db",
                       &db,
                       OpenFlags.CREATE | OpenFlags.READWRITE | OpenFlags.FULLMUTEX,
                       null
  ) != 0)
  {
    unreachable("DB error: unable to open database: %s", sqlite3::errmsg(db));
  }

  sqlite3::busy_timeout(db, 5000);
  sqlite3::@exec_ok(db,
                "PRAGMA journal_mode=WAL;"
                "PRAGMA synchronous=NORMAL;"
                "PRAGMA foreign_keys=ON;"
                "PRAGMA temp_store=MEMORY;");

  sqlite3::@transaction(db)
  {
    // Init, schema, migrations, etc.
    // sqlite3::@exec(db, $embed("../../sql/schema.sql"))!!;
    // sqlite3::@exec(db, $embed("../../sql/triggers.sql"))!!;
  }!!;
}

fn void close_db() @local @finalizer
{
  if (db == null) return;
  sqlite3::close(db);
  sqlite3::free(null);
}

fn void main()
{
  Router r;
  defer r.free();
  
  r.get("/posts", fn (Context *ctx)
  {
    Post[] posts = sqlite3::@query_all{Post}(db, "SELECT * FROM posts ORDER BY created_at DESC")!;
    ctx.@tmpl("posts.html", posts)!;
  });

  r.get("/posts/:id", fn (Context *ctx)
  {
    String id = ctx.req.@param("id")!;
    Post post = sqlite3::@query_one{Post}(db, "SELECT * FROM posts WHERE id = ?1", id)!;
    ctx.@tmpl("post.html", post)!;
  });

  r.post("/posts", fn (Context *ctx)
  {
    String title = ctx.req.formData["title"] ?? "";
    String body  = ctx.req.formData["body"]  ?? "";
    if (title.trim() == "") return ctx.@error(400, "Title is required");
    long id = sqlite3::@insert(db, "INSERT INTO posts(title, body) VALUES(?1, ?2)", title, body)!;
    ctx.@redirect("/posts/:id", id);
  });

  r.handleStatic("web/assets", "/assets", $feature(EMBED_ASSETS));

  router::mhd2::listenAndServe(8080, &r)!!;
}
```

**Template (`posts.html`):**
```html
{% extends("base.html") %}
{% block("body") %}
<main>
  <h1>Posts</h1>
  {% for _, post in ipairs(posts) do %}
  <article>
    <h2><a href="/posts/{{ post.id }}">{{ post.title }}</a></h2>
    <p>{{ post.created_at }}</p>
  </article>
  {% end %}
</main>
{% endblock() %}
```

**Base layout (`base.html`):**
```html
<!DOCTYPE html>
<html>
  <head><title>My App</title></head>
  <body>
    {% yield("body") %}
  </body>
</html>
```

Struct fields map to columns by name at compile time — no codegen, no runtime reflection, no annotations.

**Compile templates:**
```bash
lua scripts/tpl_transpile.lua
```

**Or embed templates into binary at compile time:**
```sh
c3c build --trust=full -D EMBED_TEMPLATES
```

**And static assets:**
```sh
c3c build --trust=full -D EMBED_TEMPLATES -D EMBED_ASSETS
```

## Building
```bash
make        # build deps + dev binary
make release  # optimized build, stripped SQLite and MHD2
make dev      # app only, skip dep check
make clean
make clean-deps
```

The Makefile builds all three C dependencies from source and links them statically.

**Dev build** — full debug info, all features enabled, easier to iterate.

**Release build** — MHD2 compiled with `--enable-compact-code` and `--disable-messages`, 
SQLite compiled with unused features stripped at the preprocessor level:
no UTF-16, no window functions, no CTEs, no BLOB literals, no incremental I/O, 
no trace hooks, no authorization callbacks, and more — only what this app actually uses.

The result is a single statically linked ELF with no external dependencies at runtime.

## Stack
| Layer | Technology |
|-------|-----------|
| HTTP | libmicrohttpd2 |
| Templates | Lua 5.4 (transpiled from HTML) |
| Database | SQLite (WAL mode) |
| Language | C3 |
| Frontend | HTMX + Alpine.js + Pico CSS |

## Included app
A tier list application — drag-and-drop image ordering across tiers, 
file uploads, fractional position algorithm, HTMX partial updates.
Used as a real-world integration test for the framework.

## Getting started
```bash
git clone ...
# copy src/router, src/db, src/templates into your project
# modify anything
```

See `src/main.c3` for a full example.

## Status
> Personal/experimental. MHD2 is pre-release. 
> Use in production at your own risk — or better, read the source first.
> **Platform:** Linux only (glibc). Tested on x86-64.
> **Protocol:** HTTP/1.1 only — HTTP/2 is disabled in the MHD2 build.
