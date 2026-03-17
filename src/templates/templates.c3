module templates;

import router;
import lua;

import std::collections::map;
import std::io::path;
import std::io::file;
import std::io::os;
import std::thread;
import libc;

alias PthreadKey = uint;
alias PthreadDestructor = fn void (void* cls);

extern fn int pthread_key_create(PthreadKey* key, PthreadDestructor destructor) @cname("pthread_key_create") @local;
extern fn int pthread_key_delete(PthreadKey key) @cname("pthread_key_delete") @local;
extern fn int pthread_set_specific(PthreadKey key, void* value) @cname("pthread_setspecific") @local;

PthreadKey lua_state_key @local;

String base_path @if(!$feature(EMBED_TEMPLATES)) = "build/web/views";

struct TemplateEntry
{
  String path;
  char[] contents;
  long timestamp;
}

// NOTE: const TemplateEntry[*] EMBEDDED_TEMPLATES = {...};
$exec("lua", { "scripts/tpl_transpile.lua", "--embed" }) @if($feature(EMBED_TEMPLATES));

HashMap{String, TemplateEntry} tpl_src_cache @local @if(!$feature(EMBED_TEMPLATES));
Mutex tpl_src_mtx @local @if(!$feature(EMBED_TEMPLATES));

fn void close_lua_state(void *ptr) @local
{
  if (ptr != null) lua::close((lua::State*)ptr);
}

fn void create_pthread_lua_key() @local @init
{
  pthread_key_create(&lua_state_key, &close_lua_state);
}

fn void delete_pthread_lua_key() @local @finalizer
{
  pthread_key_delete(lua_state_key);
}

fn void init_tpl_src_cache() @local @init @if(!$feature(EMBED_TEMPLATES))
{
  tpl_src_cache.init(mem);
  tpl_src_mtx.init()!!;
}

fn void free_tpl_src_cache() @local @finalizer @if(!$feature(EMBED_TEMPLATES))
{
  tpl_src_mtx.lock();
  tpl_src_cache.@each(; key, value)
  {
    if (value.contents.len > 0) free(value.contents);
  };
  tpl_src_cache.free();
  tpl_src_mtx.unlock();
  tpl_src_mtx.destroy();
}

fn TemplateEntry? find_template(String name) @if($feature(EMBED_TEMPLATES))
{
  foreach (&te : EMBEDDED_TEMPLATES)
  {
    if (te.path == name) return *te;
  }

  return NOT_FOUND~;
}

fn TemplateEntry? find_template(String name) @if(!$feature(EMBED_TEMPLATES))
{
  tpl_src_mtx.lock();
  TemplateEntry? cached = tpl_src_cache[name];
  tpl_src_mtx.unlock();

  Path p = path::temp(base_path)!!
    .tappend(name.treplace(".html", ".lua"))!!;

  Stat stat;
  os::native_stat(&stat, p.str_view())!!;

  if (catch err = cached)
  {
    switch (err)
    {
      case NOT_FOUND:
        char[] buf = read_tpl_file(p);
        tpl_src_mtx.lock();
        TemplateEntry te = { p.str_view(), buf, stat.st_mtime };
        tpl_src_cache[name] = te;
        tpl_src_mtx.unlock();
        return te;
      default:
        return err~;
    }
  }

  if (cached.timestamp < stat.st_mtime)
  {
    char[] buf = read_tpl_file(p);
    tpl_src_mtx.lock();
    free(cached.contents);
    TemplateEntry te = { p.str_view(), buf, stat.st_mtime };
    tpl_src_cache[name] = te;
    tpl_src_mtx.unlock();
    return te;
  }

  return cached;
}

fn char[] read_tpl_file(Path p) @local @if(!$feature(EMBED_TEMPLATES))
{
    char[] buffer = mem::new_array(char, path::file_size(p))!!;
    File file = file::open_path(p, "r")!!;

    defer (void)file.close();

    file.read(buffer)!!;
    return buffer;
}

const String TPL_CACHE_KEY = "TPL_CACHE";

fn State*? get_lua() @private
{
  tlocal State* l = null;
  if (l != null) return l;

  l = lua::new_state();
  if (l == null) return lua::LUA_ERROR~;

  // pthread_set_specific is not used for access (tlocal handles that),
  // but to trigger close_lua_state when a worker thread exits,
  // since tlocal variables have no destructor of their own.
  pthread_set_specific(lua_state_key, l);

  lua::require_f(l, "_G", &lua::open_base, 1);
  lua::pop(l, 1);

  lua::require_f(l, "table", &lua::open_table, 1);
  lua::pop(l, 1);

  lua::require_f(l, "string", &lua::open_string, 1);
  lua::pop(l, 1);

  lua::require_f(l, "math", &lua::open_math, 1);
  lua::pop(l, 1);

  lua::push_closure(l, &l_load_template, 0);
  lua::set_global(l, "load_template");

  // registry[TPL_CACHE_KEY] = {}
  lua::push_l_string(l, TPL_CACHE_KEY, TPL_CACHE_KEY.len);
  lua::create_table(l, 0, 0);
  lua::set_table(l, lua::LUA_REGISTRYINDEX);

  return l;
}

macro @render(Response* w, String path, ...)
{
  w.html(@execute(path, true, $vasplat)!);
}

macro @render_kv(Response* w, String path, ...)
{
  w.html(@execute(path, false, $vasplat)!);
}

macro @execute(String path, bool $packed, ...) @local
{
  $if !($vacount % 2 == 0 || $packed):
    $error("Args should be even to match \"key\", value constraint");
  $endif

  State* l = get_lua()!;
  TemplateEntry te = find_template(path)!;

  lua::set_top(l, 0);

  if (!push_template_fn_cached(l, path, te))
  {
    ZString err = lua::to_l_string(l, -1, null);
    io::eprintfn("template load failed: %s", err);
    lua::pop(l, 1);
    return lua::LOAD_FAILED~;
  }

  lua::@push_all(l, $packed, $vasplat); // push vars table
  lua::push_nil(l); // No yields allowed in child template, push nil as a second argument

  if (lua::pcall(l, 2, 1, 0) != lua::ThreadStatus.OK)
  {
    lua::pop(l, 1); // pop error left on Lua stack
    return lua::CALL_FAILED~;
  }

  String result = lua::to_string(l, -1).str_view();
  lua::pop(l, 1);

  return result;
}

fn int l_load_template(State* l) @local
{
  ZString name = lua::check_l_string(l, 1, null);

  TemplateEntry? te = find_template(name.str_view());
  if (catch err = te) return lua::l_error(l, "template not found: %s", name);

  if (!push_template_fn_cached(l, name.str_view(), te)) return lua::error(l);

  return 1;
}

fn bool push_template_fn_cached(State* l, String name, TemplateEntry te) @local
{
  // cache = registry["TPL_CACHE"]
  lua::push_l_string(l, TPL_CACHE_KEY, TPL_CACHE_KEY.len);
  lua::get_table(l, lua::LUA_REGISTRYINDEX);                 // stack: cache

  // entry = cache[name]
  lua::push_l_string(l, name.ptr, name.len);
  lua::get_table(l, -2);                                // stack: cache, entry|nil

  if (lua::is_table(l, -1))
  {
    // entry.ts
    lua::get_field(l, -1, "ts");                        // stack: cache, entry, ts
    ulong cached_ts = 0;
    if (lua::is_integer(l, -1)) cached_ts = lua::to_integer_x(l, -1, &&1);
    lua::pop(l, 1);                                     // pop ts

    if (cached_ts == te.timestamp)
    {
      // entry.fn
      lua::get_field(l, -1, "fn");                      // stack: cache, entry, fn
      if (lua::is_function(l, -1))
      {
        lua::remove(l, -2);                             // drop entry, keep fn
        lua::remove(l, -2);                             // drop cache, keep fn
        return true;
      }
      lua::pop(l, 1);                                   // pop non-fn
    }
  }

  lua::pop(l, 1);                                       // pop entry|nil

  // Compile: load_buffer_x(te.contents) -> chunk
  if (lua::load_buffer_x(l, te.contents, te.contents.len, name.zstr_tcopy(), "bt") != lua::ThreadStatus.OK)
  {
    lua::remove(l, -2);                                 // drop cache, leave error
    return false;
  }

  // Run chunk: chunk() -> render_fn
  if (lua::pcall(l, 0, 1, 0) != lua::ThreadStatus.OK)
  {
    lua::remove(l, -2);                                 // drop cache, leave error
    return false;
  }
  // stack: cache, render_fn

  // entry = { ts = te.timestamp, fn = render_fn }
  lua::create_table(l, 0, 2);                           // stack: cache, render_fn, entry

  lua::push_int(l, te.timestamp);
  lua::set_field(l, -2, "ts");

  lua::push_value(l, -2);                               // push render_fn
  lua::set_field(l, -2, "fn");

  // cache[name] = entry
  lua::push_l_string(l, name.ptr, name.len);            // key
  lua::push_value(l, -2);                               // entry
  lua::set_table(l, -5);

  lua::pop(l, 1);                                       // pop entry
  lua::remove(l, -2);                                   // drop cache, keep render_fn
  return true;
}
