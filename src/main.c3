module tierlister;

import router;
import templates;

fn void main()
{
  Router r = router::new();
  defer { r.free(); }

  r.get("/", fn (Context *ctx) {
    ctx.html(templates::render("index.html"));
  });

  r.get("/list/create", fn (Context *ctx) {
    ctx.html(templates::render("list/create.html"));
  });

  r.post("/list/create", fn (Context *ctx) {
    ctx.html(templates::render("list/create.html"));
  });

  r.handleStatic("web/assets", "/assets");

  router::mhd2::listenAndServe(8080, &r);
}
