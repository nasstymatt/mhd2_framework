module mhd2;

import libc;
import std::io;

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

fn MHDAction *handleRequest(void *cls, MHDRequest *mreq, MHDString *path, HttpMethod method, ulong uploadSize) @local
{
    @pool_init(mem, 64 * 1024)
    {
      assert(cls != null, "No router passed into handleRequest");

      Router *r = (Router*)cls;
      Request req = {
        method,
        path.cstr.str_view(),
      };
      Response res = {
        .statusCode = 200,
      };

      Context ctx = {
        r, &req, &res, 0
      };
      r.handleRequest(&ctx);

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

      return mhdActionFromResponse(mreq, mres);
    };
}
