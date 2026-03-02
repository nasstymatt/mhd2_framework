module router::reqstate;

import std::collections::map;
import libc;

const REQUEST_ARENA_SIZE = 128 * 1024;

struct FileUploadState
{
  Fd fd;
  String path;
}

struct ReqState
{
  Router* r;
  router::Request req;
  router::Response res;
  HashMap{String, FileUploadState} filesUpload;
  ArenaAllocator mem;
  char[REQUEST_ARENA_SIZE] buf;
}

fn void ReqState.init(&self)
{
  self.mem.init(&self.buf);
  self.filesUpload.init(&self.mem);
  self.req.headers.init(&self.mem);
  self.req.formData.init(&self.mem);
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
