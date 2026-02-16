module router;

import std::collections::list;
import std::io;
import std::io::path;
import std::io::file;
import libc;

alias MiddlewareFn = fn void (Context *ctx, args...);
alias HandlerFn = fn void (Context *ctx);

enum HttpMethod : const inline int
{
  OTHER = 255,

  /* Main HTTP methods. */
  GET = 1,
  HEAD = 2,
  POST = 3,
  PUT = 4,
  DELETE = 5,
  OPTIONS = 7,
}


struct Step @private
{
  MiddlewareFn handler;
  any[] args;
}

struct Router
{
  List {Step} steps;
}

fn Router new()
{
  return (Router) {};
}

fn void Router.free(&self)
{
  foreach (&s : self.steps)
  {
    foreach (&a : s.args)
    {
      free(a.ptr);
    }
    free(s.args);
  }
  self.steps.free();
}

fn void Router.handleRequest(&self, Context *ctx)
{
  ctx.r = self;
  ctx.next();
}

fn Router *Router.use(&self, MiddlewareFn handlerFn, args...)
{
  any[] owned = @clone_slice(args);
  foreach (&a : owned)
  {
    void* p = malloc(a.type.sizeof);
    mem::copy(p, a.ptr, a.type.sizeof);
    *a = any_make(p, a.type);
  }
  self.steps.push({handlerFn, owned});
  return self;
}

fn Router *Router.handleStatic(&self, String src, String mountAt)
{
  self.use(
    fn (Context *ctx, args...)
    {
      // TODO: Introduce HEAD method, cache, mime for static files
      if (args.len == 2 && ctx.req.method == HttpMethod.GET)
      {
        String src = *anycast(args[0], String)!!;
        String mountAt = *anycast(args[1], String)!!;

        if (ctx.req.path.starts_with(mountAt))
        {
          // TODO: Investigate backslashes (on windows) and static root escaping e.g. assets/../templates
          Path p = path::temp(
            src.tconcat(
              ctx.req.path[mountAt.len..].trim_right("/"))
          )!!;

          if (path::is_file(p))
          {
            Fd fd = file::open_path(p, "r")!!.fd();
            assert(fd != -1, "Unable to open file");

            ctx.res.file.fd = fd;
            ctx.res.bodyKind = FILEFD;
            ctx.res.file.size = path::file_size(p)!!;
            return;
          }
        }
      }
      ctx.next();
    },
    src, mountAt);

  return self;
}

fn Router *Router.get(&self, String path, HandlerFn handlerFn)
{
  self.use(
    fn (Context *ctx, args...)
    {
      if (args.len == 2) {
        String path = *anycast(args[0], String)!!;
        HandlerFn handlerFn = *anycast(args[1], HandlerFn)!!;

        if (ctx.req.method == HttpMethod.GET && ctx.req.path == path)
        {
          handlerFn(ctx);
          return;
        }
      }
      ctx.next();
    },
    path, handlerFn);
  return self;
}

fn Router *Router.post(&self, String path, HandlerFn handlerFn)
{
  self.use(
    fn (Context *ctx, args...)
    {
      if (args.len == 2) {
        String path = *anycast(args[0], String)!!;
        HandlerFn handlerFn = *anycast(args[1], HandlerFn)!!;

        if (ctx.req.method == HttpMethod.POST && ctx.req.path == path)
        {
          handlerFn(ctx);
          return;
        }
      }
      ctx.next();
    },
    path, handlerFn);
  return self;
}
