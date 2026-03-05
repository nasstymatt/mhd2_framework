module router;

import templates;

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

fn void? Context.next(&self)
{
  while (self.routeIdx < self.r.steps.len())
  {
    Step *s = &self.r.steps[self.routeIdx++];
    s.handle(self)!;
    return;
  }

  self.@not_found();
}

macro Context.@text(&self, String #text)
{
  self.res.bodyKind = BUFFER;
  self.res.@add_header("Content-Type", "text/plain");
  self.res.body = #text;
}

macro Context.@html(&self, String #html)
{
  self.res.bodyKind = BUFFER;
  self.res.@add_header("Content-Type", "text/html");
  self.res.body = #html;
}

macro void Context.@not_found(&self)
{
  self.@status(404);
}

macro Context.@redirect(&self, String location, ..., int sc = 303)
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
        }
      $endfor
    }
  }

  assert(paramCount == $vacount, "redirect path has %d param(s) but %d argument(s) were provided", paramCount, $vacount);

  self.@status(sc);
  self.res.headers.push({"Location", string::join(tmem, pathSegments, "/")});
}

<*
 @require sc >= 100 && sc < 600 : "Not a http status code"
*>
macro Context.@status(&self, int sc = 200)
{
  self.res.statusCode = sc;
}

<*
 @require sc >= 400 && sc < 600 : "Not a http error status code"
*>
macro Context.@error(&self, int sc = 500, String text = "")
{
  self.@text(text);
  self.@status(sc);
}

macro Context.@render(&self, String path, ...)
{
  self.@html(templates::@render(path, $vasplat)!);
}
