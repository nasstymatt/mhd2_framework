module templates::gen;

import std::io::path;
import std::io::file;
import std::collections::map;
import std::thread;
import std::io::os;
import libc;

String basePath = "build/templates/";

struct TemplateEntry
{
  String path;
  char[] contents;
  long timestamp;
}

HashMap{String, TemplateEntry} tplSrcCache @local;
Mutex tplSrcMtx @local;

fn void initTplSrcCache() @local @init
{
  tplSrcCache.init(mem);
  tplSrcMtx.init()!!;
}

fn void freeTplSrcCache() @local @finalizer
{
  tplSrcMtx.lock();
  tplSrcCache.@each(; key, value)
  {
    if (value.contents.len > 0) free(value.contents);
  };
  tplSrcCache.free();
  tplSrcMtx.unlock();
  tplSrcMtx.destroy();
}

fn TemplateEntry? findTemplate(String name)
{
  tplSrcMtx.lock();
  TemplateEntry? cached = tplSrcCache[name];
  tplSrcMtx.unlock();

  Path p = path::temp(basePath)!!
    .tappend(name.treplace(".html", ".lua"))!!;

  Stat stat;
  os::native_stat(&stat, p.str_view())!!;

  if (catch err = cached)
  {
    switch (err)
    {
      case NOT_FOUND:
        char[] buf = readTplFile(p);
        tplSrcMtx.lock();
        TemplateEntry te = { p.str_view(), buf, stat.st_mtime };
        tplSrcCache[name] = te;
        tplSrcMtx.unlock();
        return te;
      default:
        return err~;
    }
  }

  if (cached.timestamp < stat.st_mtime)
  {
    char[] buf = readTplFile(p);
    tplSrcMtx.lock();
    free(cached.contents);
    TemplateEntry te = { p.str_view(), buf, stat.st_mtime };
    tplSrcCache[name] = te;
    tplSrcMtx.unlock();
    return te;
  }

  return cached;
}

fn char[] readTplFile(Path p) @local
{
    char[] buffer = mem::new_array(char, path::file_size(p))!!;
    File file = file::open_path(p, "r")!!;

    defer (void)file.close();

    file.read(buffer)!!;
    return buffer;
}
