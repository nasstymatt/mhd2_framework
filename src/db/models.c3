module db::models;

struct List
{
  long id;
  String title;
  String created_at;
}

struct Card
{
  long id;
  String image_path;
  String original_filename;
  String created_at;
}
