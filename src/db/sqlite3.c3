module db::sqlite3;

SQlite3* db;

fn void init_db() @local @init
{
  if (sqlite3::open_v2("./data/app.db",
                       &db,
                       OpenFlags.CREATE | OpenFlags.READWRITE | OpenFlags.FULLMUTEX,
                       null
  ) != 0)
  {
    unreachable("DB error: unable to open database: %s", sqlite3::errmsg(db));
  }

  sqlite3::busy_timeout(db, 5000);
  sqlite3::@exec_ok(db,
                "PRAGMA journal_mode=WAL;"
                "PRAGMA synchronous=NORMAL;"
                "PRAGMA foreign_keys=ON;"
                "PRAGMA temp_store=MEMORY;");

  sqlite3::@transaction(db)
  {
    sqlite3::@exec(db, $embed("../../sql/001-schema.sql"))!!;
    sqlite3::@exec(db, $embed("../../sql/002-triggers.sql"))!!;
    sqlite3::@exec(db, $embed("../../sql/003-indexes.sql"))!!;
  }!!;
}

fn void close_db() @local @finalizer
{
  if (db == null) return;
  sqlite3::close(db);
  sqlite3::free(null);
}
