module db;

import sqlite3;

SQlite3* instance;

fn void init_db() @local @init
{
  if (sqlite3::open_v2("./data/app.db",
                       &instance,
                       OpenFlags.CREATE | OpenFlags.READWRITE | OpenFlags.FULLMUTEX,
                       null
  ) != 0)
  {
    unreachable("instance error: unable to open database: %s", sqlite3::errmsg(instance));
  }

  sqlite3::busy_timeout(instance, 5000);
  sqlite3::@exec_ok(instance,
                "PRAGMA journal_mode=WAL;"
                "PRAGMA synchronous=NORMAL;"
                "PRAGMA foreign_keys=ON;"
                "PRAGMA temp_store=MEMORY;");

  sqlite3::@transaction(instance)
  {
    sqlite3::@exec(instance, $embed("../../sql/001-schema.sql"))!!;
    sqlite3::@exec(instance, $embed("../../sql/002-triggers.sql"))!!;
    sqlite3::@exec(instance, $embed("../../sql/003-indexes.sql"))!!;
  }!!;
}

fn void close_db() @local @finalizer
{
  if (instance == null) return;
  sqlite3::close(instance);
  sqlite3::free(null);
}
