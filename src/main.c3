module tierlister;

import router;
import templates;
import db::sqlite3;
import db::models;

import std::io;

SQlite3 *db;

fn void main()
{
  Router r = router::new();
  defer r.free();

  r.get("/", fn (Context *ctx)
  {
    ListModel[] lists = sqlite3::@query_all{ListModel}(db, "SELECT * FROM lists");
    int id = lists.len;
    ctx.@render("index.html", "lists", lists);
  });

  r.get("/list/create", fn (Context *ctx)
  {
    ctx.@render("list/create.html");
  });

  r.post("/list/create", fn (Context *ctx)
  {
    String title = ctx.@form("title") ?? "";
    if (title.trim() == "")
    {
      return ctx.@render("list/create.html", "err_title", "Title is required");
    }
    long id = sqlite3::@insert(db, "INSERT INTO lists(title) VALUES(?1)", title);

    ctx.@redirect("/list/:id", id);
  });


  r.get("/list/:id", fn (Context *ctx)
  {
    String? id = ctx.req.params["id"];
    if (catch id) return ctx.@not_found();

    ListModel? list = sqlite3::@query_one{ListModel}(db, "SELECT * FROM lists WHERE id = ?1", id);
    if (catch list) return ctx.@not_found();

    ctx.@render("list/edit.html", "list", list);
  });

  r.put("/list/:id", fn (Context *ctx)
  {
    String? id = ctx.req.params["id"];
    if (catch id) return ctx.@not_found();

    String title = ctx.@form("title") ?? "";
    if (title.trim() == "") return ctx.@error("Title is required");

    sqlite3::@update(db, "UPDATE lists SET title = ?1 WHERE id = ?2", title, id);

    ctx.res.headers.push({"HX-Refresh", "true"});
  });

  r.delete("/list/:id", fn (Context *ctx)
  {
    String? id = ctx.req.params["id"];
    if (catch id) return ctx.@not_found();

    sqlite3::@delete(db, "DELETE FROM lists WHERE id = ?1", id);
  });

  r.handleStatic("web/assets", "/assets");

  router::mhd2::listenAndServe(8080, &r);
}

fn void initDb() @init
{
  assert(sqlite3::open_v2("./data/app.db", &db,
                          OpenFlags.CREATE | OpenFlags.READWRITE | OpenFlags.FULLMUTEX,
                          null) == 0, "Unable to open database");

  sqlite3::busy_timeout(db, 5000);
  sqlite3::@exec_ok(db,
                "PRAGMA journal_mode=WAL;"
                "PRAGMA synchronous=NORMAL;"
                "PRAGMA foreign_keys=ON;"
                "PRAGMA temp_store=MEMORY;");

  ZString schemaSql = $embed("../sql/schema.sql");
  sqlite3::@transaction(db)
  {
    sqlite3::@exec_ok(db, schemaSql);
  };
}

fn void cleanUpDb() @finalizer
{
  if (db == null) return;
  sqlite3::close(db);
  sqlite3::free(null);
}
