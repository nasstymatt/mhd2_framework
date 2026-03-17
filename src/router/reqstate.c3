module router::reqstate;

import router::steps;

import std::collections::map;
import libc;

const REQUEST_ARENA_SIZE = 128 * 1024;

struct FileUploadState
{
  Fd fd;
  String path;
}

struct Context
{
  Router* r;
  router::Request req;
  router::Response res;
  usz route_idx;
}

struct ReqState
{
  inline Context ctx;
  HashMap{String, FileUploadState} files_upload;
  ArenaAllocator mem;
  char[REQUEST_ARENA_SIZE] buf;
}

fn void ReqState.init(&self)
{
  self.mem.init(&self.buf);
  self.files_upload.init(&self.mem);
  self.req.headers.init(&self.mem);
  self.req.form_data.init(&self.mem);
  self.req.query.init(&self.mem);
  self.req.files.init(&self.mem);
  self.req.params.init(&self.mem);
}

fn void ReqState.free(&self)
{
  self.mem.clear();
}

fn ReqState* new()
{
  ReqState* rs = mem::new(ReqState);
  rs.init();
  return rs;
}

fn void? Context.next(&self)
{
  while (self.route_idx < self.r.steps.len())
  {
    Step *s = &self.r.steps[self.route_idx++];
    return s.handle(self)!;
  }
  self.res.status_code = 404;
}
