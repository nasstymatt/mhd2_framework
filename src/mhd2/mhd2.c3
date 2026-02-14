module mhd2 @private;

import mhd2::router;

alias MHDRequest = void;
alias MHDResponse = void;
alias MHDDaemon = void;
alias MHDAction = void;

enum MHDAddressFamily : const CInt
{
  AF_NONE,
  AF_AUTO,
}

enum MHDHttpStatusCode : const CInt
{
  OK = 200,
  NOT_FOUND = 404,
}

enum MHDStatusCode : const CInt
{
  OK = 0,
}

enum MHDDaemonOption : const CInt
{
  WORK_MODE = 40,
  BIND_PORT = 80,
}

enum MHDWorkMode : const CInt
{
  WORKER_THREADS = 24
}

struct MHDString
{
  usz len;
  ZString cstr;
}

struct MHDWorkModeWithParam
{
  MHDWorkMode mode;
  MHDWorkModeParam params;
}

struct MHDDaemonOptionValueBind
{
  MHDAddressFamily af;
  CUShort port;
}

// sizeof = 16
union MHDWorkModeParam
{
  ulong[2] _abi;
  uint numWorkerThreads;
}

// sizeof = 24
union MHDDaemonOptionValue
{
  ulong[3] _abi;
  MHDWorkModeWithParam workMode;
  MHDDaemonOptionValueBind bindPort;
}


struct MHDDaemonOptionAndValue
{
  MHDDaemonOption opt;
  MHDDaemonOptionValue val;
}

alias MHDHandlerFn = fn MHDAction* (void *cls, MHDRequest *mreq, MHDString *path, HttpMethod method, ulong uploadSize);

alias MHDFreeCallback = fn void (void *cls);

extern fn MHDDaemon *mhdDaemonCreate(MHDHandlerFn handlerFn, void *cls) @cname("MHD_daemon_create");

extern fn MHDStatusCode mhdDaemonStart(MHDDaemon *d) @cname("MHD_daemon_start");

extern fn void mhdDaemonDestroy(MHDDaemon *d) @cname("MHD_daemon_destroy");

extern fn MHDAction *mhdActionAbortRequest(MHDRequest *mreq) @cname("MHD_action_abort_request");

extern fn MHDStatusCode mhdDaemonSetOptions(MHDDaemon* d, MHDDaemonOptionAndValue* options, usz optionsMaxNum)
  @cname("MHD_daemon_set_options");

extern fn MHDAction *mhdActionFromResponse(MHDRequest *mreq, MHDResponse *mres) @cname("MHD_action_from_response");

extern fn MHDResponse *mhdResponseFromBuffer(MHDHttpStatusCode sc, usz bufSize, char *buf, MHDFreeCallback freeCb, void *freeCbCls)
  @cname("MHD_response_from_buffer");

extern fn MHDResponse *mhdResponseFromBufferCopy(MHDHttpStatusCode sc, usz bufSize, char *buf)
  @cname("MHD_response_from_buffer_copy");

extern fn MHDResponse *mhdResponseFromEmpty() @cname("MHD_response_from_empty");

// extern fn MHDResponse *mhdResponseFromBufferCopy(MHDHttpStatusCode sc, usz bufSize, char *buf)
//   @cname("MHD_response_from_buffer_copy");

extern fn MHDString *mhdHttpMethodToString(HttpMethod sc) @cname("MHD_http_method_to_string");

extern fn MHDStatusCode mhdResponseAddHeader(MHDResponse *mres, ZString name, ZString value) @cname("MHD_response_add_header");

extern fn MHDResponse *mhdResponseFromFd(MHDHttpStatusCode sc, int fd, ulong offset, ulong size) @cname("MHD_response_from_fd");

macro MHDResponse *mhdResponseFromBufferStatic(MHDHttpStatusCode sc, usz bufLen, char *buf)
{
  return mhdResponseFromBuffer(sc, bufLen, buf, null, null);
}
