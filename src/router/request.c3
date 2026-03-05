module router;

import std::collections::map;

faultdef PARAM_NOT_FOUND;

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

macro Request.@param(&self, #key)
{
  if (try param = self.params[#key]) return param;
  return PARAM_NOT_FOUND~;
}
