module router::steps;

import std::collections::map;
import std::io::path;
import std::io::file;
import libc;

extern fn Fd open(ZString path, int flags) @cname("open") @local;

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
  fn void? handle(Context *ctx);
  fn void free();
}

struct MiddlewareStep (Step)
{
  HandlerFn handler;
}

fn void? MiddlewareStep.handle(&self, Context *ctx) @dynamic
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
  String[] pathSegments;
}

fn void RouteStep.init(&self) @dynamic
{
  self.pathSegments = self.path.split(mem, "/");
}

fn void? RouteStep.handle(&self, Context *ctx) @dynamic
{
  if (ctx.req.method != self.method) return ctx.next();

  String[] reqPathSegments = ctx.req.path.tsplit("/");
  if (reqPathSegments.len != self.pathSegments.len) return ctx.next();

  // Validate params
  for (usz i = 0; i < reqPathSegments.len; i++)
  {
    if (self.pathSegments[i].starts_with(":"))
    {
      ctx.req.params[self.pathSegments[i][1..]] = reqPathSegments[i];
      continue;
    }
    if (self.pathSegments[i] != reqPathSegments[i]) return ctx.next();
  }

  self.handler(ctx)!;
}

fn void RouteStep.free(&self) @dynamic
{
  free(self.pathSegments);
}


struct MountStaticFolderStep (Step)
{
  String srcPath;
  String mountAt;
  bool embed;
}

fn void? MountStaticFolderStep.handle(&self, Context *ctx) @dynamic
{

  // TODO: Introduce HEAD method, cache, mime for static files
  if (ctx.req.method == GET && ctx.req.path.starts_with(self.mountAt))
  {
    // TODO: Investigate backslashes (on windows) and static root escaping e.g. assets/../templates
    Path p = path::temp(
      self.srcPath.tconcat(
        ctx.req.path[self.mountAt.len..].trim_right("/"))
    )!!;

    if (self.embed)
    {
      $if $feature(EMBED_ASSETS):
        foreach (&embedAsset : EMBEDDED_ASSETS)
        {
          if (embedAsset.path == p.str_view())
          {
            ctx.res.bodyKind = BUFFER_STATIC;
            ctx.res.bodyStatic = embedAsset.bytes;
            return;
          }
        }
      $endif
    }
    else {
      if (path::is_file(p))
      {
        Fd fd = open(p.str_view().zstr_tcopy(), 0);
        if (fd == -1) return ctx.@not_found();

        ctx.res.file.fd = fd;
        ctx.res.bodyKind = FILEFD;
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
