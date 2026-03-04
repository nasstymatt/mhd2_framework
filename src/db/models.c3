module db::models;

struct TierList
{
  long id;
  String title;
  String created_at;
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
