module mhd2;

import libc;
import std::io;

struct ReqState
{
  Router *r;
  Request req;
  Response res;
}

const MAX_NON_STREAM_SIZE = 16 * 1024;

fn void listenAndServe(ushort port, Router *r)
{
  MHDDaemon *d = mhdDaemonCreate(&handleRequest, r);

  assert(d != null, "Unable to create mhd daemon");

  MHDDaemonOptionAndValue[] opts = {
    {
      .opt = MHDDaemonOption.BIND_PORT,
      .val = (MHDDaemonOptionValue) {
        .bindPort = (MHDDaemonOptionValueBind) {
          .af = MHDAddressFamily.AF_AUTO,
          .port = port
        }}
    },
    {
      .opt = MHDDaemonOption.WORK_MODE,
      .val = (MHDDaemonOptionValue) {
        .workMode = (MHDWorkModeWithParam) {
          .mode = MHDWorkMode.WORKER_THREADS,
          .params = (MHDWorkModeParam) {
            .numWorkerThreads = 8
          }
        }
      }
  }};

  assert(mhdDaemonSetOptions(d, &opts[0], 2) == 0, "Unable to set options");
  assert(mhdDaemonStart(d) == MHDStatusCode.OK, "Unable to start daemon");

  libc::getchar();

  mhdDaemonDestroy(d);
}

fn MHDAction* handleRequest(void *cls, MHDRequest *mreq, MHDString *path, HttpMethod method, ulong uploadSize) @local
{
  @pool_init(mem, 64 * 1024)
  {
    assert(cls != null, "No router passed into handleRequest");

    ReqState* rs = mem::new(ReqState);
    Router *r = (Router*)cls;
    Request req = {
      .method = method,
      .path = path.cstr.str_view(),
    };
    Response res = {
      .statusCode = 200,
    };

    rs.r = r;
    rs.req = req;
    rs.res = res;

    if (uploadSize > 0 && method == POST)
    {
      if (uploadSize > MAX_NON_STREAM_SIZE) return mhdActionAbortRequest(mreq);
      return mhdActionParsePost(mreq, MAX_NON_STREAM_SIZE, MAX_NON_STREAM_SIZE, OTHER, null, null, &mhdPostDataFinished, rs);
    }
    defer { free(rs); }
    Context ctx = {
      r, &rs.req, &rs.res, 0
    };
    r.handleRequest(&ctx);

    MHDResponse *mres = makeMhdResponseFromRouterRes(&rs.res);
    return mhdActionFromResponse(mreq, mres);
  };
}

fn MHDUploadAction* mhdPostDataFinished(MHDRequest *mreq, void *cls, MHDPostParseResult parsingResult)
{
  @pool_init(mem, MAX_NON_STREAM_SIZE)
  {
    ReqState *rs = (ReqState*)cls;
    defer { free(rs); }

    mhdRequestGetPostDataCb(mreq, fn bool (void *cls, MHDPostField *data)
    {
      ReqState *rs = (ReqState*)cls;
      rs.req.formData[data.name.cstr.str_view()] = data.value.cstr.str_view();
      return true;
    }, rs);

    Context ctx = { rs.r, &rs.req, &rs.res, 0 };
    rs.r.handleRequest(&ctx);

    MHDResponse* mres = makeMhdResponseFromRouterRes(&rs.res);
    return mhdUploadActionFromResponse(mreq, mres);
  };
}

fn MHDResponse* makeMhdResponseFromRouterRes(Response *res) @local
{
  MHDResponse *mres;
  switch (res.bodyKind)
  {
    case FILEFD:
      mres = mhdResponseFromFd((MHDHttpStatusCode)res.statusCode, res.file.fd, res.file.offset, res.file.size);
      break;
    case BUFFER:
    default:
      mres = mhdResponseFromBufferCopy((MHDHttpStatusCode)res.statusCode, res.body.len, res.body);
  }
  foreach (&header : res.headers)
  {
    mhdResponseAddHeader(mres, header.name.zstr_tcopy(), header.value.zstr_tcopy());
  }

  return mres;
}
