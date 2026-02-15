module mhd2 @private;

import mhd2::router;

alias MHDRequest = void;
alias MHDResponse = void;
alias MHDDaemon = void;
alias MHDAction = void;

enum MHDPostEndocing : const int
{
  OTHER,
  FORM_URLENCODED,
  MULTIPART_FORM_DATA,
  TEXT_PLAIN,
}

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

enum MHDPostParseResult : const int
{
  OK = 0,
  REQUEST_EMPTY = 1,
  OK_BAD_TERMINATION = 2,
  PARTIAL_INVALID_POST_FORMAT = 3,
  FAILED_NO_POOL_MEM = 60,
  FAILED_NO_LARGE_BUF_MEM = 61,
  FAILED_UNKNOWN_CNTN_TYPE = 80,
  FAILED_NO_CNTN_TYPE = 81,
  FAILED_HEADER_NO_BOUNDARY = 82,
  FAILED_HEADER_MISFORMED = 83,
  FAILED_HEADER_NOT_MPART = 84,
  FAILED_INVALID_POST_FORMAT = 90,
}

enum MHDUploadActionType : const inline CInt
{
  NO_ACTION = 0,
  CONTINUE,
  RESPONSE,
  SUSPEND,
  // Only if MHD compiled with HTTP Upgrade support
  UPGRADE,
  ABORT,
}

union MHDUploadActionData
{
  MHDResponse *response;
  ulong[2] _abi;
}

struct MHDUploadAction
{
  MHDUploadActionType act;
  MHDUploadActionData data;
}

struct MHDString
{
  usz len;
  ZString cstr;
}

struct MHDStringNullable
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

alias MHDUpgradedHandle = void;

alias MHDHandlerFn = fn MHDAction* (void *cls, MHDRequest *mreq, MHDString *path, HttpMethod method, ulong uploadSize);

alias MHDFreeCallback = fn void (void *cls);

alias MHDPostDataReader = fn MHDUploadAction* (void *cls,
                                               MHDRequest *req,
                       MHDString *name,
                       MHDString *filename,
                       MHDStringNullable *contentType,
                       MHDStringNullable *encoding,
                       usz size,
                       void *data,
                       ulong off,
                       bool finalData);

alias MHDPostDataFinished = fn MHDUploadAction* (MHDRequest *mreq, void *cls, MHDPostParseResult parsingResult);

alias MHDUpgradeHandler = fn void (void *cls, MHDRequest *req, MHDUploadActionData *urh);

extern fn MHDDaemon *mhdDaemonCreate(MHDHandlerFn handlerFn, void *cls) @cname("MHD_daemon_create");

extern fn MHDStatusCode mhdDaemonStart(MHDDaemon *d) @cname("MHD_daemon_start");

extern fn void mhdDaemonDestroy(MHDDaemon *d) @cname("MHD_daemon_destroy");


extern fn MHDStatusCode mhdDaemonSetOptions(MHDDaemon* d, MHDDaemonOptionAndValue* options, usz optionsMaxNum)
  @cname("MHD_daemon_set_options");

extern fn MHDAction *mhdActionFromResponse(MHDRequest *mreq, MHDResponse *mres) @cname("MHD_action_from_response");

extern fn MHDResponse *mhdResponseFromBuffer(MHDHttpStatusCode sc, usz bufSize, char *buf, MHDFreeCallback freeCb, void *freeCbCls)
  @cname("MHD_response_from_buffer");

extern fn MHDResponse *mhdResponseFromBufferCopy(MHDHttpStatusCode sc, usz bufSize, char *buf)
  @cname("MHD_response_from_buffer_copy");

extern fn MHDResponse* mhdResponseFromEmpty() @cname("MHD_response_from_empty");

extern fn MHDString *mhdHttpMethodToString(HttpMethod sc) @cname("MHD_http_method_to_string");

extern fn MHDStatusCode mhdResponseAddHeader(MHDResponse *mres, ZString name, ZString value) @cname("MHD_response_add_header");

extern fn MHDResponse *mhdResponseFromFd(MHDHttpStatusCode sc, int fd, ulong offset, ulong size) @cname("MHD_response_from_fd");

extern fn MHDAction* mhdActionParsePost(MHDRequest *mreq, usz bufferSize, usz maxNonStreamSize,
                                        MHDPostEndocing enc, MHDPostDataReader streamReader,
                                        void* readerCls, MHDPostDataFinished doneCb,
                                        void* doneCbCls) @cname("MHD_action_parse_post");

extern fn MHDUploadAction* mhdUploadActionContinue(MHDRequest *mreq) @cname("MHD_upload_action_continue");

extern fn MHDUploadAction* mhdUploadActionFromResponse(
    MHDRequest* mreq,
    MHDResponse* response
) @cname("MHD_upload_action_from_response");

struct MHDPostField
{
  MHDString name;
  MHDStringNullable value;
  MHDStringNullable filename;
  MHDStringNullable contentType;
  MHDStringNullable transferEncoding;
}

alias MHDPostDataIterator = fn bool (void *cls, MHDPostField *data);

extern fn usz mhdRequestGetPostDataCb(MHDRequest *mreq, MHDPostDataIterator iterator, void *iteratorCls) @cname("MHD_request_get_post_data_cb");

macro MHDResponse *mhdResponseFromBufferStatic(MHDHttpStatusCode sc, usz bufLen, char *buf)
{
  return mhdResponseFromBuffer(sc, bufLen, buf, null, null);
}

macro MHDAction* mhdActionAbortRequest(MHDRequest *mreq)
{
  return null;
}
