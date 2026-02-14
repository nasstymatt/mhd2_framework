module templates;

import std::collections::map;
import templates::gen;
import std::thread;
import std::io;

const String TPL_CACHE_KEY = "TPL_CACHE";

fn LuaState* getLua() @private
{
  tlocal LuaState* l = null;
  if (l != null) return l;

  l = luaLNewState();
  assert(l != null, "Unable to create Lua state");

  luaLRequireF(l, "_G", &luaOpenBase, 1);
  luaPop(l, 1);

  luaLRequireF(l, "table", &luaOpenTable, 1);
  luaPop(l, 1);

  luaLRequireF(l, "string", &luaOpenString, 1);
  luaPop(l, 1);

  luaLRequireF(l, "math", &luaOpenMath, 1);
  luaPop(l, 1);

  lua_pushcclosure(l, &lLoadTemplate, 0);
  lua_setglobal(l, "load_template");

  // registry[TPL_CACHE_KEY] = {}
  luaPushLString(l, TPL_CACHE_KEY, TPL_CACHE_KEY.len);
  luaCreateTable(l, 0, 0);
  luaSetTable(l, LUA_REGISTRYINDEX);

  return l;
}

<*
 @require args.len % 2 == 0 : "Args should be even to match key, value constraint"
*>
fn String render(String path, args...)
{
  LuaState* l = getLua();
  TemplateEntry te = gen::findTemplate(path)!!;

  luaSetTop(l, 0);

  assert(pushTemplateFnCached(l, path, te), "Lua template load error: %s", luaPopError(l));

  luaPushAll(l, ...args); // push vars table
  luaPushNil(l); // No yields allowed in child template, push nil as a second argument

  assert(luaPcall(l, 2, 1, 0) == LuaThreadStatus.OK, "Lua render error: %s", luaPopError(l));

  String result = luaToString(l, -1).str_view();
  luaPop(l, 1);

  return result;
}

fn int lLoadTemplate(LuaState* l) @local
{
  ZString name = luaLCheckLString(l, 1, null);

  TemplateEntry? te = gen::findTemplate(name.str_view());
  if (catch err = te) return luaL_error(l, "template not found: %s", name);

  if (!pushTemplateFnCached(l, name.str_view(), te)) return lua_error(l);

  return 1;
}

fn bool pushTemplateFnCached(LuaState* l, String name, TemplateEntry te) @private
{
  // cache = registry["TPL_CACHE"]
  luaPushLString(l, TPL_CACHE_KEY, TPL_CACHE_KEY.len);
  luaGetTable(l, LUA_REGISTRYINDEX);                 // stack: cache

  // entry = cache[name]
  luaPushLString(l, name.ptr, name.len);
  luaGetTable(l, -2);                                // stack: cache, entry|nil

  bool need_recompile = true;

  if (luaIsTable(l, -1))
  {
    // entry.ts
    luaGetField(l, -1, "ts");                        // stack: cache, entry, ts
    ulong cached_ts = 0;
    if (luaIsInteger(l, -1)) cached_ts = luaToIntegerX(l, -1, &&1);
    luaPop(l, 1);                                    // pop ts

    if (cached_ts == te.timestamp)
    {
      // entry.fn
      luaGetField(l, -1, "fn");                      // stack: cache, entry, fn
      if (luaIsFunction(l, -1))
      {
        luaRemove(l, -2);                            // drop entry, keep fn
        luaRemove(l, -2);                            // drop cache, keep fn
        return true;
      }
      luaPop(l, 1);                                  // pop non-fn
    }
  }

  luaPop(l, 1);                                      // pop entry|nil

  // Compile: loadbuffer(te.contents) -> chunk
  if (luaLLoadBufferX(l, te.contents, te.contents.len, name.zstr_tcopy(), "t") != LuaThreadStatus.OK)
  {
    luaRemove(l, -2);                                // drop cache, leave error
    return false;
  }

  // Run chunk: chunk() -> render_fn
  if (luaPcall(l, 0, 1, 0) != LuaThreadStatus.OK)
  {
    luaRemove(l, -2);                                // drop cache, leave error
    return false;
  }
  // stack: cache, render_fn

  // entry = { ts = te.timestamp, fn = render_fn }
  luaCreateTable(l, 0, 2);                           // stack: cache, render_fn, entry

  luaPushInt(l, te.timestamp);
  luaSetField(l, -2, "ts");

  luaPushValue(l, -2);                               // push render_fn
  luaSetField(l, -2, "fn");

  // cache[name] = entry
  luaPushLString(l, name.ptr, name.len);             // key
  luaPushValue(l, -2);                               // entry
  luaSetTable(l, -5);

  luaPop(l, 1);                                      // pop entry
  luaRemove(l, -2);                                  // drop cache, keep render_fn
  return true;
}
