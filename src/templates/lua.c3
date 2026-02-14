module templates;

import std::io;

alias LuaState = void;
alias LuaCFunction = fn int (LuaState *l);

const bool LUAI_IS32INT = (uint.max >> 30) >= 3;
const int LUAI_MAXSTACK = LUAI_IS32INT ? 1000000 : 15000;
const int LUA_REGISTRYINDEX = (-LUAI_MAXSTACK - 1000);

enum LuaThreadStatus : const inline int
{
  OK = 0
}

enum LuaType : const inline int
{
  NUMBER = 3,
  STRING = 4,
  TABLE = 5,
  FUNCTION = 6,
}

extern fn LuaState *luaLNewState() @cname("luaL_newstate");
extern fn void *luaLOpenlibs(LuaState *l) @cname("luaL_openlibs");
extern fn LuaThreadStatus luaLLoadBufferX(LuaState *l, char *bytecode, usz size, char *name, char *mode) @cname("luaL_loadbufferx");
extern fn LuaThreadStatus luaPcallK(LuaState *l, int nargs, int nresults, int errfunc, int ctx, void *k) @cname("lua_pcallk");
extern fn LuaType luaType(LuaState *l, int idx) @cname("lua_type");
extern fn void luaClose(LuaState *l) @cname("lua_close");
extern fn ZString luaToLString(LuaState *l, int idx, usz *len) @cname("lua_tolstring");
extern fn void luaSetTop(LuaState *l, int idx) @cname("lua_settop");
extern fn void luaLRequireF(LuaState *l, ZString modname, void *openf, int glb) @cname("luaL_requiref");
extern fn void luaOpenBase(LuaState *l) @cname("luaopen_base");
extern fn void luaOpenTable(LuaState *l) @cname("luaopen_table");
extern fn void luaOpenString(LuaState *l) @cname("luaopen_string");
extern fn void luaOpenMath(LuaState *l) @cname("luaopen_math");
extern fn void luaOpenUtf8(LuaState *l) @cname("luaopen_utf8");
extern fn void luaPushLString(LuaState *l, char* buf, usz len) @cname("lua_pushlstring");
extern fn void luaPushBool(LuaState *l, bool b) @cname("lua_pushboolean");
extern fn void luaPushInt(LuaState *l, long b) @cname("lua_pushinteger");
extern fn void luaPushNil(LuaState *l) @cname("lua_pushnil");
extern fn void luaPushValue(LuaState *l, int idx) @cname("lua_pushvalue");
extern fn void luaCreateTable(LuaState *l, int narr, int nrec) @cname("lua_createtable");
extern fn void luaSetTable(LuaState *l, int idx) @cname("lua_settable");
extern fn int luaGetTable(LuaState *l, int idx) @cname("lua_gettable");
extern fn void luaSetField(LuaState* l, int idx, ZString name) @cname("lua_setfield");
extern fn long luaToIntegerX(LuaState* l, int idx, int* isNum) @cname("lua_tointegerx");
extern fn int luaGetField(LuaState* l, int idx, ZString name) @cname("lua_getfield");
extern fn void luaRotate(LuaState *l, int idx, int n) @cname("lua_rotate");
extern fn ZString luaLCheckLString(LuaState *l, int idx, usz *len) @cname("luaL_checklstring");
extern fn int luaL_error(LuaState *l, ZString format, ZString name);
extern fn int lua_error(LuaState *l);
extern fn void lua_pushcclosure(LuaState *l, LuaCFunction f, int idx);
extern fn void lua_setglobal(LuaState *l, ZString name);

macro luaRemove(LuaState* l, int idx)
{
  luaRotate(l, idx, -1);
  luaPop(l, 1);
}

macro LuaThreadStatus luaPcall(LuaState *l, int nargs, int nresults, int errfunc)
{
  return luaPcallK(l, nargs, nresults, errfunc, 0, null);
}

macro bool luaIsInteger(LuaState *l, int idx)
{
  return luaType(l, idx) == LuaType.NUMBER;
}

macro bool luaIsString(LuaState *l, int idx)
{
  return luaType(l, idx) == LuaType.STRING;
}

macro bool luaIsFunction(LuaState* l, int idx)
{
  return luaType(l, idx) == LuaType.FUNCTION;
}

macro bool luaIsTable(LuaState* l, int idx)
{
  return luaType(l, idx) == LuaType.TABLE;
}


macro ZString luaToString(LuaState *l, int idx)
{
  return luaToLString(l, idx, &&0);
}

macro void luaPop(LuaState *l, int n)
{
  return luaSetTop(l, -n - 1);
}

macro void luaPushAny(LuaState *l, any v)
{
  switch(v.type)
  {
    case String.typeid:
      String *str = anycast(v, String)!!;
      luaPushLString(l, str.ptr, str.len);
      break;
    case bool.typeid:
      bool* b = anycast(v, bool)!!;
      luaPushBool(l, *b);
      break;
    default:
      unreachable("Type is not handled");
  }
}

macro void luaPushAll(LuaState *l, args...)
{
  luaCreateTable(l, 0, args.len / 2);
  for (usz i = 0; i < args.len; i += 2)
  {
    any k = args[i];
    any v = args[i + 1];

    assert(k.type == String.typeid, "Template key must be string");

    luaPushAny(l, k);
    luaPushAny(l, v);

    luaSetTable(l, -3);
  }
}

fn String luaPopError(LuaState* l)
{
  if (!luaIsString(l, -1)) {
    luaPop(l, 1);
    return "unknown lua error";
  }

  String msg = luaToString(l, -1).str_view();
  luaPop(l, 1);
  return msg;
}
