module router;

import std::collections::map;

faultdef PARAM_NOT_FOUND;

struct FileUpload
{
  String file_name;
  String content_type;
  String path;
  // usz size;
}

struct Request
{
  HttpMethod method;
  String path;
  HashMap{String, String} headers;
  HashMap{String, String} params;
  HashMap{String, String} form_data;
  HashMap{String, String} query;
  HashMap{String, FileUpload} files;
}

macro Request.@param(&self, #key)
{
  if (try param = self.params[#key]) return param;
  return PARAM_NOT_FOUND~;
}

macro Request.@query(&self, #key, $Type = String)
{
  $switch ($Type):
    $case int:
      return self.query[#key]!.to_int();
    $case String:
      return self.query[#key];
    $default:
      $error("Type " +++ $Type.nameof +++ " is not handled");
  $endswitch
}
