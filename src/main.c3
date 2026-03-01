module tierlister;

import router;
import templates;
import db::sqlite3;
import db::models;

import std::io;
import libc;


SQlite3 *db;

fn void main()
{
  Router r = router::new();
  defer r.free();


  r.get("/", fn (Context *ctx)
  {
    models::List[] lists = sqlite3::@query_all{models::List}(db, "SELECT * FROM lists");
    ctx.@render("index.html", "lists", lists);
  });


  r.get("/lists/create", fn (Context *ctx)
  {
    ctx.@render("lists/create.html");
  });

  r.post("/lists/create", fn (Context *ctx)
  {
    String title = ctx.@form("title") ?? "";
    if (title.trim() == "")
    {
      return ctx.@render("lists/create.html", "err_title", "Title is required");
    }
    long id = sqlite3::@insert(db, "INSERT INTO lists(title) VALUES(?1)", title);

    ctx.@redirect("/lists/:id", id);
  });


  r.get("/lists/:id", fn (Context *ctx)
  {
    String? id = ctx.req.params["id"];
    if (catch id) return ctx.@not_found();

    models::List? list = sqlite3::@query_one{models::List}(db, "SELECT * FROM lists WHERE id = ?1", id);
    if (catch list) return ctx.@not_found();

    ctx.@render("lists/edit.html", "list", list);
  });

  r.put("/lists/:id", fn (Context *ctx)
  {
    String? id = ctx.req.params["id"];
    if (catch id) return ctx.@not_found();

    String title = ctx.@form("title") ?? "";
    if (title.trim() == "") return ctx.@error(400, "Title is required");

    sqlite3::@update(db, "UPDATE lists SET title = ?1 WHERE id = ?2", title, id);

    ctx.res.headers.push({"HX-Refresh", "true"});
  });

  r.delete("/lists/:id", fn (Context *ctx)
  {
    String? id = ctx.req.params["id"];
    if (catch id) return ctx.@not_found();

    sqlite3::@delete(db, "DELETE FROM lists WHERE id = ?1", id);
  });


  r.get("/cards", fn (Context *ctx)
  {
    models::Card[] cards = sqlite3::@query_all{models::Card}(db, "SELECT * FROM cards");
    // if (try ctx.req.headers["HX-Request"])
    // {
    //   io::printn("HX req!");
    //   return;
    // }

    ctx.@render("cards.html", "cards", cards);
  });

  r.post("/cards", fn (Context *ctx)
  {
    FileUpload? image = ctx.req.files["image"];
    if (catch image) return ctx.@error(400);

    String outPath = string::join(tmem, {image.path, image.fileName}, "_");
    if (libc::rename(image.path.zstr_tcopy(), outPath.zstr_tcopy()) != 0)
    {
      io::eprintfn("Unable to rename file %s, errno = %d", image.path, libc::errno());
      return ctx.@error(500);
    }

    long id = sqlite3::@insert(db, "INSERT INTO cards(image_path, original_filename) VALUES(?1, ?2)", outPath, image.fileName);
    models::Card card = sqlite3::@query_one{models::Card}(db, "SELECT * FROM cards WHERE id = ?1", id)!!;

    ctx.@status(201);
    if (try ctx.req.headers["HX-Request"])
    {
      ctx.@render("partials/card.html", "card", card);
    }
  });

  r.handleStatic("data/cards", "/uploads/cards");
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

  sqlite3::@transaction(db)
  {
    sqlite3::@exec(db, $embed("../sql/schema.sql"));
  };
}

fn void cleanUpDb() @finalizer
{
  if (db == null) return;
  sqlite3::close(db);
  sqlite3::free(null);
}
