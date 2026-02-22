module router::mhd2;

import mhd2;
import libc;

struct ReqState @local
{
  Router *r;
  router::Request req;
  router::Response res;
}

const MAX_NON_STREAM_SIZE = 16 * 1024;

fn void listenAndServe(ushort port, Router *r)
{
  mhd2::Daemon *d = mhd2::daemonCreate(&handleRequest, r);

  assert(d != null, "Unable to create mhd daemon");

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
            .numWorkerThreads = 8
          }
        }
      }
  }};

  assert(mhd2::daemonSetOptions(d, &opts[0], 2) == 0, "Unable to set options");
  assert(mhd2::daemonStart(d) == mhd2::StatusCode.OK, "Unable to start daemon");

  libc::getchar();

  mhd2::daemonDestroy(d);
}

fn mhd2::Action* handleRequest(void *cls, mhd2::Request *mreq, mhd2::String *path, mhd2::HttpMethod method, ulong uploadSize) @local
{
  @pool_init(mem, 64 * 1024)
  {
    assert(cls != null, "No router passed into handleRequest");

    ReqState* rs = mem::new(ReqState);
    Router *r = (Router*)cls;
    router::Request req = {
      .method = (router::HttpMethod)method,
      .path = path.cstr.str_view(),
    };
    router::Response res = {
      .statusCode = 200,
    };

    rs.r = r;
    rs.req = req;
    rs.res = res;

    if (uploadSize > 0 && (method == POST || method == PUT))
    {
      if (uploadSize > MAX_NON_STREAM_SIZE) return mhd2::actionAbortRequest(mreq);
      return mhd2::actionParsePost(mreq, MAX_NON_STREAM_SIZE, MAX_NON_STREAM_SIZE, PostEncoding.OTHER, null, null, &postDataFinished, rs);
    }
    defer { free(rs); }
    Context ctx = {
      r, &rs.req, &rs.res, 0
    };
    r.handleRequest(&ctx);

    mhd2::Response *mres = routerResponseToMHDResponse(&rs.res);
    return mhd2::actionFromResponse(mreq, mres);
  };
}

fn mhd2::UploadAction* postDataFinished(mhd2::Request *mreq, void *cls, PostParseResult parsingResult) @local
{
  @pool_init(mem, MAX_NON_STREAM_SIZE)
  {
    ReqState *rs = (ReqState*)cls;
    defer { free(rs); }

    mhd2::requestGetPostDataCb(mreq, fn bool (void *cls, PostField *data)
    {
      ReqState *rs = (ReqState*)cls;
      rs.req.formData[data.name.cstr.str_view()] = data.value.cstr.str_view();
      return true;
    }, rs);

    Context ctx = { rs.r, &rs.req, &rs.res, 0 };
    rs.r.handleRequest(&ctx);

    mhd2::Response* mres = routerResponseToMHDResponse(&rs.res);
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
      break;
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
