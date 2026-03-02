module tierlister;

import router;
import templates;
import db::sqlite3;
import db::models;

import std::io;
import std::io::path;
import libc;


SQlite3 *db;

fn void main()
{
  Router r = router::new();
  defer r.free();


  r.get("/", fn (Context *ctx)
  {
    models::TierList[] tierlists = sqlite3::@query_all{models::TierList}(db, "SELECT * FROM tierlists");
    ctx.@render("index.html", "tierlists", tierlists);
  });


  r.get("/tierlists/create", fn (Context *ctx)
  {
    ctx.@render("tierlists/create.html");
  });

  r.post("/tierlists/create", fn (Context *ctx)
  {
    String title = ctx.req.formData["title"] ?? "";
    if (title.trim() == "")
    {
      return ctx.@render("tierlists/create.html", "err_title", "Title is required");
    }
    long id = sqlite3::@insert(db, "INSERT INTO tierlists(title) VALUES(?1)", title);

    ctx.@redirect("/tierlists/:id", id);
  });


  r.get("/tierlists/:id", fn (Context *ctx)
  {
    String? id = ctx.req.params["id"];
    if (catch id) return ctx.@not_found();

    models::TierList? tierlist = sqlite3::@query_one{models::TierList}(db, "SELECT * FROM tierlists WHERE id = ?1", id);
    if (catch tierlist) return ctx.@not_found();

    ctx.@render("tierlists/edit.html", "tierlist", tierlist);
  });

  r.put("/tierlists/:id", fn (Context *ctx)
  {
    String? id = ctx.req.params["id"];
    if (catch id) return ctx.@not_found();

    String title = ctx.req.formData["title"] ?? "";
    if (title.trim() == "") return ctx.@error(400, "Title is required");

    sqlite3::@update(db, "UPDATE tierlists SET title = ?1 WHERE id = ?2", title, id);

    ctx.res.headers.push({"HX-Refresh", "true"});
  });

  r.delete("/tierlists/:id", fn (Context *ctx)
  {
    String? id = ctx.req.params["id"];
    if (catch id) return ctx.@not_found();

    sqlite3::@delete(db, "DELETE FROM tierlists WHERE id = ?1", id);

    if (try ctx.req.@header("HX-Request"))
    {
      ctx.res.@header("HX-Redirect", "/");
    }
  });


  r.get("/images", fn (Context *ctx)
  {
    models::Image[] images = sqlite3::@query_all{models::Image}(db, "SELECT * FROM images ORDER BY created_at desc");
    // if (try ctx.req.headers["HX-Request"])
    // {
    //   io::printn("HX req!");
    //   return;
    // }
    //

    ctx.@render("images.html", "images", images);
  });

  r.post("/images", fn (Context *ctx)
  {
    FileUpload? uploadImage = ctx.req.files["image"];
    if (catch uploadImage) return ctx.@error(400);

    String outPath = string::join(mem, { "data/images", uploadImage.fileName }, "/");
    if (libc::rename(uploadImage.path.zstr_tcopy(), outPath.zstr_tcopy()) != 0)
    {
      io::eprintfn("Unable to rename file %s, errno = %d", uploadImage.path, libc::errno());
      return ctx.@error(500);
    }

    long id = sqlite3::@insert(db, "INSERT INTO images(image_path, original_filename) VALUES(?1, ?2)", outPath, uploadImage.fileName);
    models::Image image = sqlite3::@query_one{models::Image}(db, "SELECT * FROM images WHERE id = ?1", id)!!;

    ctx.@status(201);
    if (try ctx.req.headers["HX-Request"])
    {
      ctx.@render("partials/image.html", "image", image);
    }
  });

  r.handleStatic("data/images", "/uploads/images");
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
    sqlite3::@exec(db, $embed("../sql/001-schema.sql"));
    sqlite3::@exec(db, $embed("../sql/002-triggers.sql"));
    sqlite3::@exec(db, $embed("../sql/003-indexes.sql"));
  };
}

fn void cleanUpDb() @finalizer
{
  if (db == null) return;
  sqlite3::close(db);
  sqlite3::free(null);
}
