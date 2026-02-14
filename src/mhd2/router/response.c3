module mhd2::router;

import std::collections::list;

enum ResponseBodyKind
{
  BUFFER,
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
    ResponseFileFD file;
  }
}
