module router;

import router::steps;

import std::collections::list;

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

struct Router
{
  List{Step} steps;
}

macro Router new()
{
  return (Router) {};
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
  ctx.r = self;
  ctx.next();
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

fn void Router.handleStatic(&self, String srcPath, String mountAt)
{
  self.@push_step((MountStaticFolderStep) { srcPath, mountAt });
}

fn void Router.get(&self, String path, HandlerFn handlerFn)
{
  self.@push_step((RouteStep) {
    .method = GET,
    .path = path,
    .handler = handlerFn
  });
}

fn void Router.post(&self, String path, HandlerFn handlerFn)
{
  self.@push_step((RouteStep) {
    .method = POST,
    .path = path,
    .handler = handlerFn
  });
}

fn void Router.put(&self, String path, HandlerFn handlerFn)
{
  self.@push_step((RouteStep) {
    .method = PUT,
    .path = path,
    .handler = handlerFn
  });
}

fn void Router.delete(&self, String path, HandlerFn handlerFn)
{
  self.@push_step((RouteStep) {
    .method = DELETE,
    .path = path,
    .handler = handlerFn
  });
}
