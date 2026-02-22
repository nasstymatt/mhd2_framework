module router;

import std::collections::map;

struct Request
{
  HttpMethod method;
  String path;
  HashMap{String, String} formData;
  HashMap{String, String} params;
}
