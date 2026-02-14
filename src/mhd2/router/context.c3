module mhd2::router;

import std::io;

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
    s.handler(self, ...s.args);
    return;
  }

  self.res.statusCode = 404;
}

fn void Context.text(&self, String text)
{
  self.res.bodyKind = BUFFER;
  self.res.headers.push({"Content-Type", "text/plain"});
  self.res.body = text;
}


fn void Context.html(&self, String html)
{
  self.res.bodyKind = BUFFER;
  self.res.headers.push({"Content-Type", "text/html"});
  self.res.body = html;
}
