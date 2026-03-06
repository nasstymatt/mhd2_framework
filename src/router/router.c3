module router;

import router::steps;

import std::collections::list;
import std::io;

alias HandlerFn = fn void? (Context *ctx);

constdef HttpMethod
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

struct Router
{
  List{Step} steps;
}

fn void Router.free(&self)
{
  foreach (step : self.steps)
  {
    step.free();
    free(step);
  }
  self.steps.free();
}

fn void Router.handleRequest(&self, Context *ctx)
{
  if (catch err = ctx.next())
  {
    switch (err)
    {
      case router::PARAM_NOT_FOUND:
        ctx.@not_found();
      default:
        io::eprintfn("Unhandler router error: %s", err);
        ctx.@error();
    }
  }
}

macro void Router.@push_step(&self, #step) @local
{
  self.steps.push(@clone(#step));
  self.steps.last()!!.init();
}

fn void Router.use(&self, HandlerFn f)
{
  self.@push_step((MiddlewareStep) { f });
}

fn void Router.handleStatic(&self, String srcPath, String mountAt, bool embed = false)
{
  self.@push_step((MountStaticFolderStep) { srcPath, mountAt, embed });
}

fn void Router.get(&self, String path, HandlerFn handlerFn)
{
  self.route(path, GET, handlerFn);
}

fn void Router.post(&self, String path, HandlerFn handlerFn)
{
  self.route(path, POST, handlerFn);
}

fn void Router.put(&self, String path, HandlerFn handlerFn)
{
  self.route(path, PUT, handlerFn);
}

fn void Router.delete(&self, String path, HandlerFn handlerFn)
{
  self.route(path, DELETE, handlerFn);
}

fn void Router.route(&self, String path, HttpMethod method, HandlerFn handlerFn)
{
  self.@push_step((RouteStep) {
    .method = method,
    .path = path,
    .handler = handlerFn
  });
}
