module tierlister;

import router;
import templates;
import db::models;

import std::io;
import libc;

fn void main()
{
  Router r;
  defer r.free();

  r.get("/", fn (Context *ctx)
  {
    TierList[] tierlists = models::tierlists::get_all()!;
    ctx.@tmpl("index.html", tierlists)!;
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
      return ctx.@tmpl_map("tierlists/create.html", "err_title", "Title is required")!;
    }
    long id = models::tierlists::create(title)!;

    ctx.@redirect("/tierlists/:id", id);
  });

  r.get("/tierlists/:id", fn (Context *ctx)
  {
    int perPage = 15;
    int page    = ctx.req.@query("page", int) ?? 1;
    int offset  = (page - 1) * perPage;
    String id   = ctx.req.@param("id")!;

    TierList tierlist                = models::tierlists::@get_one(id)!;
    TierWithImages[] tiersWithImages = tierlist.get_tiers_with_images()!;
    Image[] images                   = tierlist.@get_available_images(perPage, offset)!;
    long total                       = tierlist.@count_available_images()!;
    int totalPages                   = (int)(total + perPage - 1) / perPage;

    ctx.@tmpl("tierlists/edit.html",
              tierlist, tiersWithImages,
              images, page, totalPages)!;
  });

  r.put("/tierlists/:id", fn (Context *ctx)
  {
    String id    = ctx.req.@param("id")!;
    String title = ctx.req.formData["title"] ?? "";
    if (title.trim() == "") return ctx.@error(400, "Title is required");

    models::tierlists::update(id, title)!;

    ctx.res.@add_header("HX-Refresh", "true");
  });

  r.delete("/tierlists/:id", fn (Context *ctx)
  {
    String id = ctx.req.@param("id")!;

    models::tierlists::delete(id)!;

    if (try ctx.req.headers["HX-Request"])
    {
      ctx.res.@add_header("HX-Redirect", "/");
    }
  });

  r.put("/tierlists/:id/images/:image_id", fn (Context *ctx)
  {
    String id      = ctx.req.@param("id")!;
    String imageId = ctx.req.@param("image_id")!;
    String? tierId = ctx.req.formData["tier_id"]!;
    String? posStr = ctx.req.formData["position"]!;

    int rank = posStr.to_int()!! + 1; // 1-based index from x-sort

    models::tier_images::move(id, imageId, tierId, rank)!;
  });

  r.delete("/tierlists/:id/images/:image_id", fn (Context *ctx)
  {
    String id      = ctx.req.@param("id")!;
    String imageId = ctx.req.@param("image_id")!;

    models::tier_images::@remove(id, imageId)!;
  });

  r.get("/images", fn (Context *ctx)
  {
    int perPage = 15;
    int page    = ctx.req.@query("page", int) ?? 1;
    int offset  = (page - 1) * perPage;

    long total     = models::images::count_all()!;
    int totalPages = (int)(total + perPage - 1) / perPage;
    Image[] images = models::images::@get_all(perPage, offset)!;

    ctx.@tmpl("images.html", images, page, totalPages)!;
  });

  r.post("/images", fn (Context *ctx)
  {
    FileUpload upload = ctx.req.files["image"]!;

    String outPath = string::tformat("data/images/%s", upload.fileName);
    if (libc::rename(upload.path.zstr_tcopy(), outPath.zstr_tcopy()) != 0)
    {
      io::eprintfn("Unable to rename file %s, errno = %d", upload.path, libc::errno());
      return ctx.@error(500);
    }

    long id     = models::images::create(outPath, upload.fileName)!;
    Image image = models::images::@get_by_id(id)!;

    ctx.@status(201);
    if (try ctx.req.headers["HX-Request"])
    {
      ctx.@tmpl_map("partials/image.html", "image", image, "draggable", true)!;
    }
  });

  r.handleStatic("web/assets", "/assets", $feature(EMBED_ASSETS));
  r.handleStatic("data/images", "/uploads/images");

  router::microhttpd2::listenAndServe(8080, &r)!!;
}
