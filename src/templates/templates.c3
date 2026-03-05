module templates;

import lua;

import std::collections::map;
import std::io::path;
import std::io::file;
import std::io::os;
import std::thread;
import libc;

alias PthreadKey = uint;
alias PthreadDestructor = fn void (void* cls);

extern fn int pthreadKeyCreate(PthreadKey* key, PthreadDestructor destructor) @cname("pthread_key_create") @local;
extern fn int pthreadKeyDelete(PthreadKey key) @cname("pthread_key_delete") @local;
extern fn int pthreadSetSpecific(PthreadKey key, void* value) @cname("pthread_setspecific") @local;

PthreadKey luaStateKey @local;

fn void closeLuaState(void *ptr) @local
{
  if (ptr != null) lua::close((lua::State*)ptr);
}

String basePath = "build/web/views";

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
  pthreadKeyCreate(&luaStateKey, &closeLuaState);
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
  pthreadKeyDelete(luaStateKey);
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

const String TPL_CACHE_KEY = "TPL_CACHE";

fn State*? getLua() @private
{
  tlocal State* l = null;
  if (l != null) return l;

  l = lua::newState();
  if (l == null) return lua::LUA_ERROR~;
  pthreadSetSpecific(luaStateKey, l);

  lua::requireF(l, "_G", &lua::openBase, 1);
  lua::pop(l, 1);

  lua::requireF(l, "table", &lua::openTable, 1);
  lua::pop(l, 1);

  lua::requireF(l, "string", &lua::openString, 1);
  lua::pop(l, 1);

  lua::requireF(l, "math", &lua::openMath, 1);
  lua::pop(l, 1);

  lua::pushClosure(l, &lLoadTemplate, 0);
  lua::setGlobal(l, "load_template");

  // registry[TPL_CACHE_KEY] = {}
  lua::pushLString(l, TPL_CACHE_KEY, TPL_CACHE_KEY.len);
  lua::createTable(l, 0, 0);
  lua::setTable(l, lua::LUA_REGISTRYINDEX);

  return l;
}

<*
 @require $vacount % 2 == 0 : "Args should be even to match key, value constraint"
*>
macro @render(String path, ...)
{
  State* l = getLua()!;
  TemplateEntry te = findTemplate(path)!;

  lua::setTop(l, 0);

  if (!pushTemplateFnCached(l, path, te))
  {
    lua::pop(l, 1); // pop error left on Lua stack
    return lua::LOAD_FAILED~;
  }

  lua::@pushAll(l, $vasplat); // push vars table
  lua::pushNil(l); // No yields allowed in child template, push nil as a second argument

  if (lua::pcall(l, 2, 1, 0) != lua::ThreadStatus.OK)
  {
    lua::pop(l, 1); // pop error left on Lua stack
    return lua::CALL_FAILED~;
  }

  String result = lua::toString(l, -1).str_view();
  lua::pop(l, 1);

  return result;
}

fn int lLoadTemplate(State* l) @local
{
  ZString name = lua::checkLString(l, 1, null);

  TemplateEntry? te = findTemplate(name.str_view());
  if (catch err = te) return lua::lError(l, "template not found: %s", name);

  if (!pushTemplateFnCached(l, name.str_view(), te)) return lua::error(l);

  return 1;
}

fn bool pushTemplateFnCached(State* l, String name, TemplateEntry te) @local
{
  // cache = registry["TPL_CACHE"]
  lua::pushLString(l, TPL_CACHE_KEY, TPL_CACHE_KEY.len);
  lua::getTable(l, lua::LUA_REGISTRYINDEX);                 // stack: cache

  // entry = cache[name]
  lua::pushLString(l, name.ptr, name.len);
  lua::getTable(l, -2);                                // stack: cache, entry|nil

  bool need_recompile = true;

  if (lua::isTable(l, -1))
  {
    // entry.ts
    lua::getField(l, -1, "ts");                        // stack: cache, entry, ts
    ulong cached_ts = 0;
    if (lua::isInteger(l, -1)) cached_ts = lua::toIntegerX(l, -1, &&1);
    lua::pop(l, 1);                                    // pop ts

    if (cached_ts == te.timestamp)
    {
      // entry.fn
      lua::getField(l, -1, "fn");                      // stack: cache, entry, fn
      if (lua::isFunction(l, -1))
      {
        lua::remove(l, -2);                            // drop entry, keep fn
        lua::remove(l, -2);                            // drop cache, keep fn
        return true;
      }
      lua::pop(l, 1);                                  // pop non-fn
    }
  }

  lua::pop(l, 1);                                      // pop entry|nil

  // Compile: loadbuffer(te.contents) -> chunk
  if (lua::loadBufferX(l, te.contents, te.contents.len, name.zstr_tcopy(), "t") != lua::ThreadStatus.OK)
  {
    lua::remove(l, -2);                                // drop cache, leave error
    return false;
  }

  // Run chunk: chunk() -> render_fn
  if (lua::pcall(l, 0, 1, 0) != lua::ThreadStatus.OK)
  {
    lua::remove(l, -2);                                // drop cache, leave error
    return false;
  }
  // stack: cache, render_fn

  // entry = { ts = te.timestamp, fn = render_fn }
  lua::createTable(l, 0, 2);                           // stack: cache, render_fn, entry

  lua::pushInt(l, te.timestamp);
  lua::setField(l, -2, "ts");

  lua::pushValue(l, -2);                               // push render_fn
  lua::setField(l, -2, "fn");

  // cache[name] = entry
  lua::pushLString(l, name.ptr, name.len);             // key
  lua::pushValue(l, -2);                               // entry
  lua::setTable(l, -5);

  lua::pop(l, 1);                                      // pop entry
  lua::remove(l, -2);                                  // drop cache, keep render_fn
  return true;
}
