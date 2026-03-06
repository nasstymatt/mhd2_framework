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
  int statusCode;
  List{Header} headers;

  ResponseBodyKind bodyKind;
  union
  {
    String body;
    char[] bodyStatic;
    ResponseFileFD file;
  }
}

macro Response.@add_header(&self, #key, #value)
{
  self.headers.push({ #key, #value });
}
