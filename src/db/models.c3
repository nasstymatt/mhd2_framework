module db::models;

struct TierList
{
  long id;
  String title;
  String created_at;
}

fn Tier[]? TierList.get_tiers(&self)
{
  return models::tiers::@get_tiers_for_tierlist(self.id);
}

fn TierImageWithPath[]? TierList.get_tier_images(&self)
{
  return models::tier_images::@get_for_tierlist(self.id);
}

fn TierWithImages[]? TierList.get_tiers_with_images(&self)
{
  Tier[] tiers             = self.get_tiers()!;
  TierImageWithPath[] flat = self.get_tier_images()!;
  TierWithImages[] result  = mem::temp_array(TierWithImages, tiers.len);

  foreach (i, tier : tiers)
  {
    result[i].tier = tier;

    usz count = 0;
    foreach (ti : flat) if (ti.tier_id == tier.id) count++;

    TierImageWithPath[] images = mem::temp_array(TierImageWithPath, count);
    usz j = 0;
    foreach (ti : flat) if (ti.tier_id == tier.id) images[j++] = ti;
    result[i].images = images;
  }
  return result;
}

macro Image[]? TierList.get_available_images(&self, usz limit, usz offset)
{
  return models::images::get_not_in_tierlist(self.id, limit, offset);
}

fn long? TierList.count_available_images(&self)
{
  return models::images::count_not_in_tierlist(self.id);
}

struct Tier
{
  long id;
  String title;
  String color;
  long tierlist_id;
  double position;
}

struct Image
{
  long id;
  String image_path;
  String original_filename;
  String created_at;
}

struct TierImage
{
  long tierlist_id;
  long tier_id;
  long image_id;
  float position;
}

struct TierImageWithPath {
  inline TierImage ti;
  String image_path;
}

struct TierWithImages {
  inline Tier tier;
  TierImageWithPath[] images;
}
