module tierlister;

import router;
import templates;
import db::sqlite3;

import std::io;

struct ListModel
{
  long id;
  String title;
  String created_at;
}

SQlite3 *db;

fn void main()
{
  Router r = router::new();

  assert(sqlite3::open_v2("./data/app.db", &db,
                          OpenFlags.CREATE | OpenFlags.READWRITE | OpenFlags.FULLMUTEX,
                          null) == 0, "Unable to open database");

  defer
  {
    sqlite3::close(db);
    sqlite3::free(null);
    r.free();
  }

  initDb(db);

  r.get("/", fn (Context *ctx) {
    ListModel[] lists = sqlite3::@query_all{ListModel}(db, "SELECT * FROM lists");
    ctx.html(templates::@render("index.html", "lists", lists));
  });

  r.get("/list/create", fn (Context *ctx) {
    ctx.html(templates::@render("list/create.html"));
  });

  r.post("/list/create", fn (Context *ctx) {
    String? title = ctx.req.formData["title"];
    if (catch title)
    {
      ctx.html(templates::@render("list/create.html", "err_title", "Title is required"));
      return;
    }

    long id = sqlite3::@insert(db, "INSERT INTO lists(title) VALUES(?1)", title);
    ctx.text("Created!");
  });

  r.handleStatic("web/assets", "/assets");

  router::mhd2::listenAndServe(8080, &r);
}

fn void initDb(SQlite3 *db)
{
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
