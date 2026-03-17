module router;

import router::steps;
import router::reqstate;

import std::collections::list;
import std::io;
import std::core::dstring;

struct Header
{
  String name;
  String value;
}

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
  List{String} current_prefix;
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

fn void Router.handle_request(&self, Context* ctx)
{
  if (catch err = ctx.next())
  {
    switch (err)
    {
      case router::PARAM_NOT_FOUND:
        ctx.res.status_code = 404;
      default:
        io::eprintfn("Unhandler router error: %s", err);
        ctx.res.status_code = 500;
    }
  }
}

macro void Router.@push_step(&self, #step) @local
{
  self.steps.push(@clone(#step));
  self.steps.last()!!.init();
}

fn void Router.use(&self, MiddlewareFn f)
{
  self.@push_step((MiddlewareStep) { f });
}

fn void Router.handle_static(&self, String src_path, String mount_at, bool embed = false)
{
  self.@push_step((MountStaticFolderStep) { src_path, mount_at, embed });
}

fn void Router.get(&self, String path, HandlerFn handler_fn)
{
  self.route(path, GET, handler_fn);
}

fn void Router.post(&self, String path, HandlerFn handler_fn)
{
  self.route(path, POST, handler_fn);
}

fn void Router.put(&self, String path, HandlerFn handler_fn)
{
  self.route(path, PUT, handler_fn);
}

fn void Router.delete(&self, String path, HandlerFn handler_fn)
{
  self.route(path, DELETE, handler_fn);
}

fn void Router.route(&self, String path, HttpMethod method, HandlerFn handler_fn)
{
  self.@push_step((RouteStep) {
    .method = method,
    .path = self.prefix_path(path),
    .handler = handler_fn
  });
}

fn String Router.prefix_path(&self, String path)
{
  if (self.current_prefix.len() == 0) return path;

  DString s = dstring::temp_with_capacity(64);
  foreach (seg : self.current_prefix) s.append(seg);
  if (path != "/") s.append(path);

  return s.str_view();
}

macro Router.@group(&self, String prefix; @body())
{
  self.current_prefix.push(prefix);
  defer self.current_prefix.remove_last();

  @body();
}
