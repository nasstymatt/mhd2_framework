module db::models::tier_images;

import db::models;
import sqlite3;

macro TierImageWithPath[]? @get_for_tierlist(#tierlist_id)
{
  return sqlite3::@query_all{TierImageWithPath}(db::instance,
    "SELECT * FROM tier_images "
    "LEFT JOIN images "
    "ON tier_images.image_id = images.id "
    "WHERE tierlist_id = ?1 "
    "ORDER BY tier_id, position",
    #tierlist_id)!;
}

// NOTE: Reranking uses midpoint insertion. When the gap between neighbours
// shrinks below 1.0 the entire tier is rebalanced to integer multiples of 1000.
fn void? move(String tierlist_id, String image_id, String tier_id, int rank)
{
  double[] positions = sqlite3::@query_all{double}(db::instance,
    "SELECT position FROM tier_images "
    "WHERE tierlist_id=?1 AND tier_id=?2 AND image_id!=?3 "
    "ORDER BY position",
    tierlist_id, tier_id, image_id)!;

  double prev    = rank >= 2 ? positions[rank - 2] : 0.0;
  double next    = (rank - 1) < positions.len ? positions[rank - 1] : prev + 2000.0;
  double new_pos = (prev + next) / 2.0;
  double gap     = next - prev;

  if (gap < 1.0)
  {
    long[] image_ids = sqlite3::@query_all{long}(db::instance,
      "SELECT image_id FROM tier_images "
      "WHERE tierlist_id=?1 AND tier_id=?2 "
      "ORDER BY position",
      tierlist_id, tier_id)!;

    sqlite3::@transaction(db::instance)
    {
      foreach (i, img_id : image_ids)
      {
        sqlite3::@update(db::instance,
          "UPDATE tier_images SET position=?1 WHERE image_id=?2 AND tierlist_id=?3",
          (double)(i + 1) * 1000.0, img_id, tierlist_id)!;
      }
    }!;
  }
  else
  {
    sqlite3::@insert(db::instance,
      "INSERT OR REPLACE INTO tier_images(image_id, tier_id, tierlist_id, position) "
      "VALUES(?1, ?2, ?3, ?4)",
      image_id, tier_id, tierlist_id, new_pos)!;
  }
}

macro @remove(#tierlist_id, #image_id)
{
  sqlite3::@delete(db::instance,
    "DELETE FROM tier_images WHERE tierlist_id = ?1 AND image_id = ?2",
    #tierlist_id, #image_id)!;
}
