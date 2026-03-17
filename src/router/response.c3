module router;

import std::collections::list;

enum ResponseBodyKind
{
  BUFFER,
  BUFFER_STATIC,
  FILEFD,
}

struct ResponseFileFD
{
  int fd;
  ulong offset;
  ulong size;
}

struct Response
{
  int status_code;
  List{Header} headers;

  ResponseBodyKind body_kind;
  union
  {
    String body;
    char[] body_static;
    ResponseFileFD file;
  }
}

fn void Response.html(&self, String html)
{
  self.body_kind = BUFFER;
  self.headers.push({ "Content-Type", "text/html" });
  self.body = html;
}

fn void Response.text(&self, String text)
{
  self.body_kind = BUFFER;
  self.headers.push({ "Content-Type", "text/plain" });
  self.body = text;
}

macro Response.@redirect(&self, String location, ..., int sc = 303)
{
  String[] path_segments = location.tsplit("/");

  usz param_count = 0;
  foreach (&seg : path_segments)
  {
    if (seg.len > 0 && (*seg)[0] == ':')
    {
      param_count++;
      $for var $i = 0; $i < $vacount; $i++:
        if (param_count - 1 == $i)
        {
          *seg = string::tformat("%s", $vaarg[$i]);
        }
      $endfor
    }
  }

  assert(param_count == $vacount, "redirect path has %d param(s) but %d argument(s) were provided", param_count, $vacount);

  self.status_code = sc;
  self.headers.push({ "Location", string::join(tmem, path_segments, "/") });
}

macro Response.error(&self, int sc = 500, String message = "")
{
  self.status_code = sc;
  self.body_kind = BUFFER;
  self.body = message;
}
