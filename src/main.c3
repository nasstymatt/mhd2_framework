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

  r.get("/", fn (Response* w, Request* r)
  {
    TierList[] tierlists = models::tierlists::get_all()!;
    templates::@render(w, "index.html", tierlists)!;
  });

  r.get("/tierlists/create", fn (Response* w, Request* r)
  {
    templates::@render(w, "tierlists/create.html")!;
  });

  r.post("/tierlists/create", fn (Response* w, Request* r)
  {
    String title = r.form_data["title"] ?? "";
    if (title.trim() == "")
    {
      return templates::@render_kv(w, "tierlists/create.html", "err_title", "Title is required")!;
    }
    long id = models::tierlists::create(title)!;

    w.@redirect("/tierlists/:id", id);
  });

  r.@group("/tierlists/:id")
  {
    r.get("/", fn (Response* w, Request* r)
    {
      int per_page = 15;
      int page     = r.@query("page", int) ?? 1;
      int offset   = (page - 1) * per_page;
      String id    = r.@param("id")!;

      TierList tierlist                  = models::tierlists::@get_one(id)!;
      TierWithImages[] tiers_with_images = tierlist.get_tiers_with_images()!;
      Image[] images                     = tierlist.get_available_images(per_page, offset)!;
      long total                         = tierlist.count_available_images()!;
      int total_pages                    = (int)(total + per_page - 1) / per_page;

      templates::@render(w, "tierlists/edit.html",
                         tierlist, tiers_with_images,
                         images, page, total_pages)!;
    });

    r.put("/", fn (Response* w, Request* r)
    {
      String id    = r.@param("id")!;
      String title = r.form_data["title"] ?? "";
      if (title.trim() == "") return w.error(400, "Title is required");

      models::tierlists::update(id, title)!;

      w.headers.push({ "HX-Refresh", "true"});
    });

    r.delete("/", fn (Response* w, Request* r)
    {
      String id = r.@param("id")!;
      models::tierlists::delete(id)!;

      if (try r.headers["HX-Request"]) w.headers.push({ "HX-Redirect", "/" });
    });
  };

  r.put("/tierlists/:id/images/:image_id", fn (Response* w, Request* r)
  {
    String tierlist_id = r.@param("id")!;
    String image_id    = r.@param("image_id")!;
    String? tier_id    = r.form_data["tier_id"]!;
    String? pos_str    = r.form_data["position"]!;

    int rank = pos_str.to_int()!! + 1; // 1-based index from x-sort

    models::tier_images::move(tierlist_id, image_id, tier_id, rank)!;
  });

  r.delete("/tierlists/:id/images/:image_id", fn (Response* w, Request* r)
  {
    String tierlist_id = r.@param("id")!;
    String image_id    = r.@param("image_id")!;

    models::tier_images::@remove(tierlist_id, image_id)!;
  });

  r.get("/images", fn (Response* w, Request* r)
  {
    int per_page = 15;
    int page     = r.@query("page", int) ?? 1;
    int offset   = (page - 1) * per_page;

    long total      = models::images::count_all()!;
    int total_pages = (int)(total + per_page - 1) / per_page;
    Image[] images  = models::images::get_all(per_page, offset)!;

    templates::@render(w, "images.html", images, page, total_pages)!;
  });

  r.post("/images", fn (Response* w, Request* r)
  {
    FileUpload upload = r.files["image"]!;

    String out_path = string::tformat("data/images/%s", upload.file_name);
    if (libc::rename(upload.path.zstr_tcopy(), out_path.zstr_tcopy()) != 0)
    {
      io::eprintfn("Unable to rename file %s, errno = %d", upload.path, libc::errno());
      return w.error(500);
    }

    long id     = models::images::create(out_path, upload.file_name)!;
    Image image = models::images::@get_by_id(id)!;

    w.status_code = 201;
    if (try r.headers["HX-Request"])
    {
      templates::@render_kv(w, "partials/image.html",
                             "image",     image,
                             "draggable", true
      )!;
    }
  });

  r.handle_static("web/assets", "/assets", $feature(EMBED_ASSETS));
  r.handle_static("data/images", "/uploads/images");

  router::microhttpd2::listen_and_serve(8080, &r)!!;
}
