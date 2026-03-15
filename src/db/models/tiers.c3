module db::models::tiers;

import sqlite3;

macro Tier[]? @get_tiers_for_tierlist(#tierlist_id)
{
  return sqlite3::@query_all{Tier}(db::instance, "SELECT * FROM tiers WHERE tierlist_id = ?1", #tierlist_id)!;
}
