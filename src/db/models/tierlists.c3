module db::models::tierlists;

import db::models;
import db::sqlite3;

fn TierList[]? get_all()
{
  return sqlite3::@query_all{TierList}(sqlite3::db, "SELECT * FROM tierlists")!;
}

macro TierList? @get_one(#id)
{
  return sqlite3::@query_one{TierList}(sqlite3::db, "SELECT * FROM tierlists WHERE id = ?1", #id)!;
}

fn long? create(String title)
{
  return sqlite3::@insert(sqlite3::db, "INSERT INTO tierlists(title) VALUES(?1)", title)!;
}

fn void? update(String id, String title)
{
  sqlite3::@update(sqlite3::db, "UPDATE tierlists SET title = ?1 WHERE id = ?2", title, id)!;
}

fn void? delete(String id)
{
  sqlite3::@delete(sqlite3::db, "DELETE FROM tierlists WHERE id = ?1", id)!;
}
