module router::steps;

import router::reqstate;

import std::collections::map;
import std::io::path;
import std::io::file;
import libc;

extern fn Fd open(ZString path, int flags) @cname("open") @local;

alias HandlerFn = fn void? (Response* w, Request* r);
alias MiddlewareFn = fn void? (Context* ctx);

struct EmbedAsset @local @if($feature(EMBED_ASSETS))
{
  String path;
  char[] bytes;
}

// NOTE: const EmbedAsset[*] EMBEDDED_ASSETS = {...}
$exec("lua", { "scripts/embed_assets.lua" }) @if($feature(EMBED_ASSETS));

interface Step
{
  fn void init();
  fn void? handle(Context* ctx);
  fn void free();
}

struct MiddlewareStep (Step)
{
  MiddlewareFn handler;
}

fn void? MiddlewareStep.handle(&self, Context* ctx) @dynamic
{
  self.handler(ctx)!;
}

fn void MiddlewareStep.init(&self) @dynamic
{
}

fn void MiddlewareStep.free(&self) @dynamic
{
}

struct RouteStep (Step)
{
  HttpMethod method;
  String path;
  HandlerFn handler;
  String[] path_segments;
}

fn void RouteStep.init(&self) @dynamic
{
  self.path_segments = self.path.split(mem, "/");
}

fn void? RouteStep.handle(&self, Context* ctx) @dynamic
{

  if (ctx.req.method != self.method) return ctx.next();

  String[] req_path_segments = ctx.req.path.tsplit("/");
  if (req_path_segments.len != self.path_segments.len) return ctx.next();

  // Validate params
  for (usz i = 0; i < req_path_segments.len; i++)
  {
    if (self.path_segments[i].starts_with(":"))
    {
      ctx.req.params[self.path_segments[i][1..]] = req_path_segments[i];
      continue;
    }
    if (self.path_segments[i] != req_path_segments[i]) return ctx.next();
  }

  self.handler(&ctx.res, &ctx.req)!;
}

fn void RouteStep.free(&self) @dynamic
{
  free(self.path_segments);
}


struct MountStaticFolderStep (Step)
{
  String src_path;
  String mount_at;
  bool embed;
}

fn void? MountStaticFolderStep.handle(&self, Context* ctx) @dynamic
{
  // TODO: Introduce HEAD method, cache, mime for static files
  if (ctx.req.method == GET && ctx.req.path.starts_with(self.mount_at))
  {
    // TODO: Investigate backslashes (on windows) and static root escaping e.g. assets/../templates
    Path p = path::temp(
      self.src_path.tconcat(
        ctx.req.path[self.mount_at.len..].trim_right("/"))
    )!!;

    ctx.res.headers.push({ "Cache-Control", "public, max-age=31536000, immutable" });

    if (self.embed)
    {
      $if $feature(EMBED_ASSETS):
        foreach (&embed_asset : EMBEDDED_ASSETS)
        {
          if (embed_asset.path == p.str_view())
          {
            ctx.res.body_kind = BUFFER_STATIC;
            ctx.res.body_static = embed_asset.bytes;
            return;
          }
        }
      $endif
    }
    else {
      if (path::is_file(p))
      {
        Fd fd = open(p.str_view().zstr_tcopy(), 0);
        if (fd == -1) { ctx.res.status_code = 404; return; }

        ctx.res.file.fd = fd;
        ctx.res.body_kind = FILEFD;
        ctx.res.file.offset = 0;
        ctx.res.file.size = path::file_size(p)!;
        return;
      }
    }
  }
  ctx.next()!;
}

fn void MountStaticFolderStep.init(&self) @dynamic
{
}

fn void MountStaticFolderStep.free(&self) @dynamic
{
}
