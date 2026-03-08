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
  Router r;
  defer r.free();

  r.get("/", fn (Context *ctx)
  {
    TierList[] tierlists = sqlite3::@query_all{TierList}(db, "SELECT * FROM tierlists")!;
    ctx.@tmpl("index.html", "tierlists", tierlists)!;
  });

  r.get("/tierlists/create", fn (Context *ctx)
  {
    ctx.@tmpl("tierlists/create.html")!;
  });

  r.post("/tierlists/create", fn (Context *ctx)
  {
    String title = ctx.req.formData["title"] ?? "";
    if (title.trim() == "")
    {
      return ctx.@tmpl("tierlists/create.html", "err_title", "Title is required")!;
    }
    long id = sqlite3::@insert(db, "INSERT INTO tierlists(title) VALUES(?1)", title)!;

    ctx.@redirect("/tierlists/:id", id);
  });

  r.get("/tierlists/:id", fn (Context *ctx)
  {
    String id = ctx.req.@param("id")!;

    // TODO: refactor
    TierList tierlist = sqlite3::@query_one{TierList}(db, "SELECT * FROM tierlists WHERE id = ?1", id)!;
    Tier[] tiers = sqlite3::@query_all{Tier}(db, "SELECT * FROM tiers WHERE tierlist_id = ?1", tierlist.id)!;
    TierImage[] tierImages =
      sqlite3::@query_all{TierImage}(db,
                                     "SELECT * FROM tier_images "
                                     "WHERE tierlist_id = ?1 "
                                     "ORDER BY tier_id, position",
                                     tierlist.id)!;
    Image[] allImages = sqlite3::@query_all{Image}(db, "SELECT * FROM images",)!;
    Image[] images =
      sqlite3::@query_all{Image}(db,
                                 "SELECT * FROM images "
                                 "WHERE id NOT IN (SELECT image_id FROM tier_images WHERE tierlist_id = ?1) "
                                 "ORDER BY created_at DESC",
                                 tierlist.id)!;

    ctx.@tmpl("tierlists/edit.html",
                "tierlist",   tierlist,
                "tiers",      tiers,
                "images",     images,
                "tierImages", tierImages,
                "allImages",  allImages
    )!;
  });

  r.put("/tierlists/:id", fn (Context *ctx)
  {
    String? id = ctx.req.@param("id");
    if (catch id) return ctx.@not_found();

    String title = ctx.req.formData["title"] ?? "";
    if (title.trim() == "") return ctx.@error(400, "Title is required");

    sqlite3::@update(db, "UPDATE tierlists SET title = ?1 WHERE id = ?2", title, id)!;

    ctx.res.@add_header("HX-Refresh", "true");
  });

  r.put("/tierlists/:id/images/:image_id", fn (Context *ctx) {
    String? id         = ctx.req.@param("id");
    if (catch id) return ctx.@not_found();
    String? imageId    = ctx.req.@param("image_id");
    if (catch imageId) return ctx.@not_found();
    String? tierId     = ctx.req.formData["tier_id"];
    if (catch tierId) return ctx.@error(400);
    String? posStr     = ctx.req.formData["position"];
    if (catch posStr) return ctx.@error(400);

    int rank = posStr.to_int()!! + 1; // 1-based index from x-sort
    // Fetch existing positions in the destination tier, excluding this image
    double[]? positions = sqlite3::@query_all{double}(db,
                                                      "SELECT position FROM tier_images WHERE tierlist_id=?1 AND tier_id=?2 AND image_id!=?3 ORDER BY position",
                                                      id, tierId, imageId);
    if (catch positions) return ctx.@error(500);

    // NOTE: Reranking, possibly fragile part
    double prev = rank >= 2 ? positions[rank - 2] : 0.0;
    double next = (rank - 1) < positions.len ? positions[rank - 1] : prev + 2000.0;
    double new_pos = (prev + next) / 2.0;
    double gap = next - prev;

    if (gap < 1.0) {
      double[]? all_ids = sqlite3::@query_all{double}(db,
                                                      "SELECT image_id FROM tier_images WHERE tierlist_id=?1 AND tier_id=?2 ORDER BY position",
                                                      id, tierId);
      if (catch all_ids) return ctx.@error(500);

      foreach (i, _id : all_ids) {
        sqlite3::@insert(db,
                         "UPDATE tier_images SET position=?1 WHERE image_id=?2 AND tierlist_id=?3",
                         (double)(i + 1) * 1000.0, all_ids[i], id)!;
      }
    } else {
      sqlite3::@insert(db,
                       "INSERT OR REPLACE INTO tier_images(image_id, tier_id, tierlist_id, position) VALUES(?1,?2,?3,?4)",
                       imageId, tierId, id, new_pos)!;
    }
  });

  r.delete("/tierlists/:id/images/:image_id", fn (Context *ctx) {
    String? id         = ctx.req.@param("id");
    if (catch id) return ctx.@not_found();
    String? imageId    = ctx.req.@param("image_id");
    if (catch imageId) return ctx.@not_found();

    sqlite3::@delete(db, "DELETE FROM tier_images WHERE tierlist_id = ?1 AND image_id = ?2", id, imageId)!;
  });

  r.delete("/tierlists/:id", fn (Context *ctx)
  {
    String? id = ctx.req.@param("id");
    if (catch id) return ctx.@not_found();

    sqlite3::@delete(db, "DELETE FROM tierlists WHERE id = ?1", id)!;

    if (try ctx.req.headers["HX-Request"])
    {
      ctx.res.@add_header("HX-Redirect", "/");
    }
  });


  r.get("/images", fn (Context *ctx)
  {
    Image[] images = sqlite3::@query_all{Image}(db, "SELECT * FROM images ORDER BY created_at desc")!;
    ctx.@tmpl("images.html", "images", images)!;
  });

  r.post("/images", fn (Context *ctx)
  {
    FileUpload? uploadImage = ctx.req.files["image"];
    if (catch uploadImage) return ctx.@error(400);

    String outPath = string::join(tmem, { "data/images", uploadImage.fileName }, "/");
    if (libc::rename(uploadImage.path.zstr_tcopy(), outPath.zstr_tcopy()) != 0)
    {
      io::eprintfn("Unable to rename file %s, errno = %d", uploadImage.path, libc::errno());
      return ctx.@error(500);
    }

    long id = sqlite3::@insert(db, "INSERT INTO images(image_path, original_filename) VALUES(?1, ?2)", outPath, uploadImage.fileName)!;
    Image image = sqlite3::@query_one{Image}(db, "SELECT * FROM images WHERE id = ?1", id)!!;

    ctx.@status(201);
    if (try ctx.req.headers["HX-Request"])
    {
      ctx.@tmpl("partials/image.html",
                  "image",     image,
                  "draggable", true
      )!;
    }
  });

  r.handleStatic("web/assets", "/assets", $feature(EMBED_ASSETS));
  r.handleStatic("data/images", "/uploads/images");

  router::mhd2::listenAndServe(8080, &r)!!;
}

fn void initDb() @init
{
  if (sqlite3::open_v2("./data/app.db",
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
    sqlite3::@exec(db, $embed("../sql/001-schema.sql"))!!;
    sqlite3::@exec(db, $embed("../sql/002-triggers.sql"))!!;
    sqlite3::@exec(db, $embed("../sql/003-indexes.sql"))!!;
  }!!;
}

fn void cleanUpDb() @finalizer
{
  if (db == null) return;
  sqlite3::close(db);
  sqlite3::free(null);
}
