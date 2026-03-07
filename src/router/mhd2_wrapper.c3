module router::mhd2;

import mhd2;
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
  io::eprintfn("MHD2 panic: %s:%u (%s): %s\n", file, line, func, message);
  abort();
}

fn void? listenAndServe(ushort port, Router *r)
{
  mhd2::libSetPanicFunc(&panicHandler, null);

  mhd2::Daemon *d = mhd2::daemonCreate(&handleRequest, r);

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

  if (mhd2::daemonSetOptions(d, opts.ptr, opts.len) != 0) return DAEMON_OPTIONS_FAILED~;
  if (mhd2::daemonStart(d) != mhd2::StatusCode.OK) return DAEMON_START_FAILED~;

  libc::getchar();

  mhd2::daemonDestroy(d);
}

fn mhd2::Action* handleRequest(void *cls, mhd2::Request *mreq, mhd2::String *path, mhd2::HttpMethod method, ulong uploadSize) @local
{
  if (cls == null) unreachable("No router passed into handleRequest");

  Router *r = (Router*)cls;
  ReqState *rs = reqstate::new();

  rs.r = r;
  rs.req.method = (router::HttpMethod)method;
  rs.req.path = path.cstr.str_view();
  rs.res.statusCode = 200;

  mem::@scoped(&rs.mem)
  {
    populateRequestHeaders(mreq, &rs.req);
  };

  // PUT/POST
  if (uploadSize > 0 && (method == POST || method == PUT))
  {
    return mhd2::actionParsePost(mreq, MAX_NON_STREAM_SIZE, 0,
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
    return mhd2::actionFromResponse(mreq, routerResponseToMHDResponse(&rs.res));
  };
}

fn mhd2::UploadAction* postDataReader(mhd2::Request *mreq,
                                      void *cls,
                                      mhd2::String *name,
                                      mhd2::StringNullable *filename,
                                      mhd2::StringNullable *contentType,
                                      mhd2::StringNullable *encoding,
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
    return mhd2::uploadActionContinue(mreq);
  }

  // File upload
  if (off == 0)
  {
    char[*] mkpath = "data/tmp/file-XXXXXX\0";
    Fd fd = mkstemp(&mkpath[0]);
    if (fd == -1) return mhd2::uploadActionContinue(mreq);

    String path = ((ZString)&mkpath).copy(&rs.mem);

    rs.filesUpload[fieldName] = (FileUploadState) { fd, path };
  }

  FileUploadState*? upload = rs.filesUpload.get_ref(fieldName);
  if (catch upload) return mhd2::uploadActionContinue(mreq);

  // NOTE: we need this for now to avoid mhd2 upload offset regression bug
  if (size > 1 * 1024 * 1024) return mhd2::uploadActionContinue(mreq);

  if (upload.fd == -1 || write_all(upload.fd, data, size) == -1) return mhd2::uploadActionContinue(mreq);

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

  return mhd2::uploadActionContinue(mreq);
}

fn mhd2::UploadAction* postDataFinished(mhd2::Request *mreq, void *cls, PostParseResult parsingResult) @local
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

    mhd2::Response* mres = routerResponseToMHDResponse(ctx.res);
    return mhd2::uploadActionFromResponse(mreq, mres);
  };
}

fn mhd2::Response* routerResponseToMHDResponse(router::Response *res) @local
{
  mhd2::Response *mres;
  switch (res.bodyKind)
  {
    case FILEFD:
      mres = mhd2::responseFromFd((mhd2::HttpStatusCode)res.statusCode, res.file.fd, res.file.offset, res.file.size);
    case BUFFER_STATIC:
      mres = mhd2::responseFromBufferStatic((mhd2::HttpStatusCode)res.statusCode, res.bodyStatic.len, res.bodyStatic);
    case BUFFER:
    default:
      mres = mhd2::responseFromBufferCopy((mhd2::HttpStatusCode)res.statusCode, res.body.len, res.body);
  }
  foreach (&header : res.headers)
  {
    mhd2::responseAddHeader(mres, header.name.zstr_tcopy(), header.value.zstr_tcopy());
  }

  return mres;
}



macro populateRequestHeaders(mhd2::Request *mreq, router::Request *req) @local
{
  mhd2::requestGetValuesCb(mreq,
                           mhd2::ValueKind.HEADER,
                           fn bool (void *cls, mhd2::ValueKind kind, mhd2::NameAndValue *nv)
                           {
                             router::Request *req = (router::Request*)cls;
                             req.headers[nv.name.cstr.str_view().copy(mem)] = nv.value.str_view().copy(mem);
                             return true;
                           },
                           req);
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
