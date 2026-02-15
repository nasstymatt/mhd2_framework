module mhd2::router;

import std::collections::map;

struct Request
{
  HttpMethod method;
  String path;
  HashMap{String, String} formData;
}
