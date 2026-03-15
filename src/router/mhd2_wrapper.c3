module router::microhttpd2;

import microhttpd2;
import router::reqstate;

import std::collections::map;
import std::io;
import libc;

faultdef DAEMON_CREATE_FAILED, DAEMON_OPTIONS_FAILED, DAEMON_START_FAILED;

const MAX_NON_STREAM_SIZE = 64 * 1024;
const ROUTER_HANDLER_POOL_SIZE = 64 * 1024;

extern fn Fd mkstemp(char *template) @cname("mkstemp") @local;
extern fn int unlink(ZString path) @cname("unlink") @local;

fn void panicHandler(void *cls, ZString file, ZString func, CUInt line, ZString message) @local
{
  io::eprintfn("MICROHTTPD2 panic: %s:%u (%s): %s\n", file, line, func, message);
  abort();
}

fn void? listenAndServe(ushort port, Router *r)
{
  microhttpd2::libSetPanicFunc(&panicHandler, null);

  microhttpd2::Daemon *d = microhttpd2::daemonCreate(&handleRequest, r);

  if (d == null) return DAEMON_CREATE_FAILED~;

  DaemonOptionAndValue[] opts = {
    {
      .opt = DaemonOption.BIND_PORT,
      .val = (DaemonOptionValue) {
        .bindPort = (DaemonOptionValueBind) {
          .af = AddressFamily.AF_AUTO,
          .port = port
        }}
    },
    {
      .opt = DaemonOption.WORK_MODE,
      .val = (DaemonOptionValue) {
        .workMode = (WorkModeWithParam) {
          .mode = WorkMode.WORKER_THREADS,
          .params = (WorkModeParam) {
            .numWorkerThreads = 4
          }
        }
      },
  }};

  if (microhttpd2::daemonSetOptions(d, opts.ptr, opts.len) != 0) return DAEMON_OPTIONS_FAILED~;
  if (microhttpd2::daemonStart(d) != microhttpd2::StatusCode.OK) return DAEMON_START_FAILED~;

  libc::getchar();

  microhttpd2::daemonDestroy(d);
}

fn microhttpd2::Action* handleRequest(void *cls, microhttpd2::Request *mreq, microhttpd2::String *path, microhttpd2::HttpMethod method, ulong uploadSize) @local
{
  if (cls == null) unreachable("No router passed into handleRequest");

  Router *r = (Router*)cls;
  ReqState *rs = reqstate::new();

  rs.r = r;
  rs.req.method = (router::HttpMethod)method;
  rs.req.path = path.cstr.str_view();
  rs.res.statusCode = 200;

  // Parse headers
  microhttpd2::requestGetValuesCb(mreq, microhttpd2::ValueKind.HEADER,
                           fn bool (void* cls, microhttpd2::ValueKind kind, microhttpd2::NameAndValue *nv)
                           {
                             ReqState* rs = (ReqState*)cls;
                             rs.req.headers[nv.name.cstr.str_view()] = nv.value.str_view().copy(&rs.mem);
                             return true;
                           },
                           rs);

  // Parse query params
  microhttpd2::requestGetValuesCb(mreq, microhttpd2::ValueKind.URI_QUERY_PARAM,
                           fn bool (void *cls, microhttpd2::ValueKind kind, microhttpd2::NameAndValue *nv)
                           {
                             ReqState* rs = (ReqState*)cls;
                             rs.req.query[nv.name.cstr.str_view()] = nv.value.str_view().copy(&rs.mem);
                             return true;
                           },
                           rs);

  // PUT/POST
  if (uploadSize > 0 && (method == POST || method == PUT))
  {
    return microhttpd2::actionParsePost(mreq, MAX_NON_STREAM_SIZE, 0,
                                 PostEncoding.OTHER, &postDataReader, rs, &postDataFinished, rs);
  }

  // GET
  defer
  {
    rs.free();
    free(rs);
  }
  @pool_init(&rs.mem, ROUTER_HANDLER_POOL_SIZE)
  {
    Context ctx = { r, &rs.req, &rs.res, 0 };
    r.handleRequest(&ctx);
    return microhttpd2::actionFromResponse(mreq, routerResponseToMHDResponse(&rs.res));
  };
}

fn microhttpd2::UploadAction* postDataReader(microhttpd2::Request *mreq,
                                      void *cls,
                                      microhttpd2::String *name,
                                      microhttpd2::StringNullable *filename,
                                      microhttpd2::StringNullable *contentType,
                                      microhttpd2::StringNullable *encoding,
                                      usz size,
                                      void *data,
                                      ulong off,
                                      CInt finalData) @local
{
  ReqState *rs = (ReqState*)cls;
  String fieldName = name.cstr.str_view(); // no copy needed, hashmap making its own copy of the key

  // Simple Field Upload
  if (filename.len == 0)
  {
    mem::@scoped(&rs.mem)
    {
      char[] rawValue = ((char*)data)[:size];
      String fieldValue = (String)@clone_slice(rawValue);

      if (off == 0)
      {
        rs.req.formData[fieldName] = fieldValue;
      }
      else if (fieldValue.len > 0)
      {
        rs.req.formData[fieldName]!!.concat(mem, fieldValue);
      }
    };
    return microhttpd2::uploadActionContinue(mreq);
  }

  // File upload
  if (off == 0)
  {
    char[*] mkpath = "data/tmp/file-XXXXXX\0";
    Fd fd = mkstemp(&mkpath[0]);
    if (fd == -1) return microhttpd2::uploadActionContinue(mreq);

    String path = ((ZString)&mkpath).copy(&rs.mem);

    rs.filesUpload[fieldName] = (FileUploadState) { fd, path };
  }

  FileUploadState*? upload = rs.filesUpload.get_ref(fieldName);
  if (catch upload) return microhttpd2::uploadActionContinue(mreq);

  // NOTE: we need this for now to avoid microhttpd2 upload offset regression bug
  if (size > 1 * 1024 * 1024) return microhttpd2::uploadActionContinue(mreq);

  if (upload.fd == -1 || write_all(upload.fd, data, size) == -1) return microhttpd2::uploadActionContinue(mreq);

  if (finalData)
  {
    libc::close(upload.fd);
    upload.fd = -1;
    rs.req.files[fieldName] = (FileUpload) {
      filename.str_view().copy(&rs.mem),
      contentType.str_view().copy(&rs.mem),
      upload.path,
    };
  }

  return microhttpd2::uploadActionContinue(mreq);
}

fn microhttpd2::UploadAction* postDataFinished(microhttpd2::Request *mreq, void *cls, PostParseResult parsingResult) @local
{
  ReqState *rs = (ReqState*)cls;

  defer
  {
    rs.filesUpload.@each(; k, v)
    {
      if (v.fd != -1) libc::close(v.fd);
      unlink(v.path.zstr_copy(&rs.mem));
    };
    rs.free();
    free(rs);
  }

  @pool_init(&rs.mem, ROUTER_HANDLER_POOL_SIZE)
  {
    Context ctx = { rs.r, &rs.req, &rs.res, 0 };

    if (parsingResult != OK) { ctx.@status(400); }
    else { ctx.r.handleRequest(&ctx); }

    microhttpd2::Response* mres = routerResponseToMHDResponse(ctx.res);
    return microhttpd2::uploadActionFromResponse(mreq, mres);
  };
}

fn microhttpd2::Response* routerResponseToMHDResponse(router::Response *res) @local
{
  microhttpd2::Response *mres;
  switch (res.bodyKind)
  {
    case FILEFD:
      mres = microhttpd2::responseFromFd((microhttpd2::HttpStatusCode)res.statusCode, res.file.fd, res.file.offset, res.file.size);
    case BUFFER_STATIC:
      mres = microhttpd2::responseFromBufferStatic((microhttpd2::HttpStatusCode)res.statusCode, res.bodyStatic.len, res.bodyStatic);
    case BUFFER:
    default:
      mres = microhttpd2::responseFromBufferCopy((microhttpd2::HttpStatusCode)res.statusCode, res.body.len, res.body);
  }
  foreach (&header : res.headers)
  {
    microhttpd2::responseAddHeader(mres, header.name.zstr_tcopy(), header.value.zstr_tcopy());
  }

  return mres;
}

macro isz write_all(Fd fd, void *buf, usz count) @local
{
  usz written = 0;
  while (written < count)
  {
    isz ret = libc::write(fd, (char*)buf + written, count - written);
    if (ret == -1)
    {
      if (libc::errno() == 4) continue;
      return -1;
    }
    written += ret;
  }
  return written;
}
