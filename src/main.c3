module tierlister;

import std::io;
import mhd2, mhd2::router;
import templates;
import std::collections::map;

fn void main()
{
  Router r = router::new();

  r.get("/", fn (Context *ctx) {
    ctx.html(templates::render("index.html"));
  });

  r.get("/list/create", fn (Context *ctx) {
    ctx.html(templates::render("list/create.html"));
  });

  r.post("/list/create", fn (Context *ctx) {
    io::printn(ctx.req.formData);
    ctx.html(templates::render("list/create.html"));
  });

  r.handleStatic("assets", "/assets");

  mhd2::listenAndServe(8080, &r);
  r.free();
}
