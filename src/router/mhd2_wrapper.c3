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

fn void panic_handler(void *cls, ZString file, ZString func, CUInt line, ZString message) @local
{
  io::eprintfn("MICROHTTPD2 panic: %s:%u (%s): %s\n", file, line, func, message);
  abort();
}

fn void? listen_and_serve(ushort port, Router *r)
{
  microhttpd2::lib_set_panic_func(&panic_handler, null);

  microhttpd2::Daemon *d = microhttpd2::daemon_create(&handle_request, r);

  if (d == null) return DAEMON_CREATE_FAILED~;

  DaemonOptionAndValue[] opts = {
    {
      .opt = DaemonOption.BIND_PORT,
      .val = (DaemonOptionValue) {
        .bind_port = (DaemonOptionValueBind) {
          .af = AddressFamily.AF_AUTO,
          .port = port
        }}
    },
    {
      .opt = DaemonOption.WORK_MODE,
      .val = (DaemonOptionValue) {
        .work_mode = (WorkModeWithParam) {
          .mode = WorkMode.WORKER_THREADS,
          .params = (WorkModeParam) {
            .num_worker_threads = 4
          }
        }
      },
  }};

  if (microhttpd2::daemon_set_options(d, opts.ptr, opts.len) != 0) return DAEMON_OPTIONS_FAILED~;
  if (microhttpd2::daemon_start(d) != microhttpd2::StatusCode.OK) return DAEMON_START_FAILED~;

  libc::getchar();

  microhttpd2::daemon_destroy(d);
}

fn microhttpd2::Action* handle_request(void *cls, microhttpd2::Request *mreq,
                                       microhttpd2::String *path,
                                       microhttpd2::HttpMethod method,
                                       ulong upload_size) @local
{
  if (cls == null) unreachable("No router passed into handle_request");

  Router *r = (Router*)cls;
  ReqState *rs = reqstate::new();

  rs.r = r;
  rs.req.method = (router::HttpMethod)method;
  rs.req.path = path.cstr.str_view();
  rs.res.status_code = 200;

  // Parse headers
  microhttpd2::request_get_values_cb(mreq, ValueKind.HEADER,
                           fn bool (void* cls, ValueKind kind, NameAndValue* nv)
                           {
                             ReqState* rs = (ReqState*)cls;
                             rs.req.headers[nv.name.cstr.str_view()] = nv.value.str_view().copy(&rs.mem);
                             return true;
                           },
                           rs);

  // Parse query params
  microhttpd2::request_get_values_cb(mreq, ValueKind.URI_QUERY_PARAM,
                           fn bool (void *cls, ValueKind kind, NameAndValue *nv)
                           {
                             ReqState* rs = (ReqState*)cls;
                             rs.req.query[nv.name.cstr.str_view()] = nv.value.str_view().copy(&rs.mem);
                             return true;
                           },
                           rs);

  // PUT/POST
  if (upload_size > 0 && (method == POST || method == PUT))
  {
    return microhttpd2::action_parse_post(mreq, MAX_NON_STREAM_SIZE, 0,
                                 PostEncoding.OTHER, &post_data_reader, rs, &post_data_finished, rs);
  }

  // GET
  defer
  {
    rs.free();
    free(rs);
  }
  @pool_init(&rs.mem, ROUTER_HANDLER_POOL_SIZE)
  {
    r.handle_request(rs);
    return microhttpd2::action_from_response(mreq, router_response_to_mhd_response(&rs.res));
  };
}

fn microhttpd2::UploadAction* post_data_reader(microhttpd2::Request *mreq,
                                       void *cls,
                                       microhttpd2::String *name,
                                       StringNullable *filename,
                                       StringNullable *content_type,
                                       StringNullable *encoding,
                                       usz size,
                                       void *data,
                                       ulong off,
                                       CInt final_data) @local
{
  ReqState *rs = (ReqState*)cls;
  String field_name = name.cstr.str_view(); // no copy needed, hashmap making its own copy of the key

  // Simple Field Upload
  if (filename.len == 0)
  {
    mem::@scoped(&rs.mem)
    {
      char[] raw_value = ((char*)data)[:size];
      String field_value = (String)@clone_slice(raw_value);

      if (off == 0)
      {
        rs.req.form_data[field_name] = field_value;
      }
      else if (field_value.len > 0)
      {
        rs.req.form_data[field_name]!!.concat(mem, field_value);
      }
    };
    return microhttpd2::upload_action_continue(mreq);
  }

  // File upload
  if (off == 0)
  {
    char[*] mkpath = "data/tmp/file-XXXXXX\0";
    Fd fd = mkstemp(&mkpath[0]);
    if (fd == -1) return microhttpd2::upload_action_continue(mreq);

    String path = ((ZString)&mkpath).copy(&rs.mem);

    rs.files_upload[field_name] = (FileUploadState) { fd, path };
  }

  FileUploadState*? upload = rs.files_upload.get_ref(field_name);
  if (catch upload) return microhttpd2::upload_action_continue(mreq);

  // NOTE: we need this for now to avoid microhttpd2 upload offset regression bug
  if (size > 1 * 1024 * 1024) return microhttpd2::upload_action_continue(mreq);

  if (upload.fd == -1 || write_all(upload.fd, data, size) == -1) return microhttpd2::upload_action_continue(mreq);

  if (final_data)
  {
    libc::close(upload.fd);
    upload.fd = -1;
    rs.req.files[field_name] = (FileUpload) {
      filename.str_view().copy(&rs.mem),
      content_type.str_view().copy(&rs.mem),
      upload.path,
    };
  }

  return microhttpd2::upload_action_continue(mreq);
}

fn microhttpd2::UploadAction* post_data_finished(microhttpd2::Request *mreq, void *cls, PostParseResult parsing_result) @local
{
  ReqState *rs = (ReqState*)cls;

  defer
  {
    rs.files_upload.@each(; k, v)
    {
      if (v.fd != -1) libc::close(v.fd);
      unlink(v.path.zstr_copy(&rs.mem));
    };
    rs.free();
    free(rs);
  }

  @pool_init(&rs.mem, ROUTER_HANDLER_POOL_SIZE)
  {
    if (parsing_result != OK) { rs.res.status_code = 400; }
    else { rs.r.handle_request(rs); }

    microhttpd2::Response* mres = router_response_to_mhd_response(&rs.res);
    return microhttpd2::upload_action_from_response(mreq, mres);
  };
}

fn microhttpd2::Response* router_response_to_mhd_response(router::Response *res) @local
{
  microhttpd2::Response *mres;
  switch (res.body_kind)
  {
    case FILEFD:
      mres = microhttpd2::response_from_fd((microhttpd2::HttpStatusCode)res.status_code, res.file.fd, res.file.offset, res.file.size);
    case BUFFER_STATIC:
      mres = microhttpd2::response_from_buffer_static((microhttpd2::HttpStatusCode)res.status_code, res.body_static.len, res.body_static);
    case BUFFER:
    default:
      mres = microhttpd2::response_from_buffer_copy((microhttpd2::HttpStatusCode)res.status_code, res.body.len, res.body);
  }
  foreach (&header : res.headers)
  {
    microhttpd2::response_add_header(mres, header.name.zstr_tcopy(), header.value.zstr_tcopy());
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
