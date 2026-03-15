module db::models::images;

import db::models;
import sqlite3;

macro Image[]? @get_not_in_tierlist(#tierlist_id, #limit, #offset)
{
  return sqlite3::@query_all{Image}(db::instance,
    `SELECT * FROM images i
     WHERE NOT EXISTS (
        SELECT 1 FROM tier_images ti
        WHERE ti.image_id = i.id AND ti.tierlist_id = ?1
     )
     ORDER BY created_at DESC
     LIMIT ?2 OFFSET ?3`,
    #tierlist_id, #limit, #offset)!;
}

macro long? @count_not_in_tierlist(#tierlist_id)
{
  return sqlite3::@query_one{long}(db::instance,
    "SELECT COUNT(*) FROM images i WHERE NOT EXISTS "
    "(SELECT 1 FROM tier_images ti WHERE ti.image_id = i.id AND ti.tierlist_id = ?1)",
    #tierlist_id)!;
}

macro Image[]? @get_all(#limit, #offset)
{
  return sqlite3::@query_all{Image}(db::instance,
    "SELECT * FROM images ORDER BY created_at DESC LIMIT ?1 OFFSET ?2",
    #limit, #offset)!;
}

fn long? count_all()
{
  return sqlite3::@query_one{long}(db::instance, "SELECT COUNT(*) FROM images")!;
}

fn long? create(String image_path, String original_filename)
{
  return sqlite3::@insert(db::instance,
    "INSERT INTO images(image_path, original_filename) VALUES(?1, ?2)",
    image_path, original_filename)!;
}

macro Image? @get_by_id(#id)
{
  return sqlite3::@query_one{Image}(db::instance, "SELECT * FROM images WHERE id = ?1", #id)!;
}
