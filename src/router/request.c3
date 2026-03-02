module router;

import std::collections::map;

struct FileUpload
{
  String fileName;
  String contentType;
  String path;
  // usz size;
}

struct Request
{
  HttpMethod method;
  String path;
  HashMap{String, String} headers;
  HashMap{String, String} params;
  HashMap{String, String} formData;
  HashMap{String, FileUpload} files;
}

macro Request.@header(&self, #key)
{
  return self.headers[#key];
}
