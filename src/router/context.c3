module router;

import templates;

import std::io;
import std::core::string;

struct Header
{
  String name;
  String value;
}

struct Context
{
  Router *r;
  Request *req;
  Response *res;
  usz routeIdx;
}

fn void Context.next(&self)
{
  while (self.routeIdx < self.r.steps.len())
  {
    Step *s = &self.r.steps[self.routeIdx++];
    s.handle(self);
    return;
  }

  self.res.statusCode = 404;
}

macro void Context.@text(&self, String #text)
{
  self.res.bodyKind = BUFFER;
  self.res.headers.push({"Content-Type", "text/plain"});
  self.res.body = #text;
}

macro void Context.@html(&self, String #html)
{
  self.res.bodyKind = BUFFER;
  self.res.headers.push({"Content-Type", "text/html"});
  self.res.body = #html;
}

macro void Context.@not_found(&self)
{
  self.res.statusCode = 404;
}

macro void Context.@redirect(&self, String location, ..., int sc = 303)
{
  String[] pathSegments = location.tsplit("/");

  usz paramCount = 0;
  foreach (&seg : pathSegments)
  {
    if (seg.len > 0 && (*seg)[0] == ':')
    {
      paramCount++;
      $for var $i = 0; $i < $vacount; $i++:
        if (paramCount - 1 == $i)
        {
          *seg = string::tformat("%s", $vaarg[$i]);
          io::printn(*seg);
        }
      $endfor
    }
  }

  assert(paramCount == $vacount);

  self.res.statusCode = sc;
  self.res.headers.push({"Location", string::join(tmem, pathSegments, "/")});
}

macro Context.@error(&self, String text = "", int sc = 400)
{
  self.@text(text);
  self.res.statusCode = sc;
}

macro Context.@form(&self, String key, $DataType = String)
{
  // FIXME: Add a real conversion to desired type,
  // use this cast only as a fallback or throw
  // a compile-time error
  return self.req.formData[key];
}

macro void Context.@render(&self, String path, ...)
{
  self.@html(templates::@render(path, $vasplat));
}
