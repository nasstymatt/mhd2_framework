CREATE TABLE IF NOT EXISTS tierlists (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS tiers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    color TEXT NOT NULL DEFAULT '#CCCCCC',
    tierlist_id INTEGER NOT NULL,
    position    REAL NOT NULL,
    FOREIGN KEY (tierlist_id) REFERENCES tierlists(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS tier_images (
    image_id  INTEGER NOT NULL,
    tier_id   INTEGER NOT NULL,
    position  REAL NOT NULL,
    PRIMARY KEY (image_id, tier_id),
    FOREIGN KEY (tier_id) REFERENCES tiers(id) ON DELETE CASCADE
    FOREIGN KEY (image_id) REFERENCES images(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS images (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    image_path TEXT UNIQUE NOT NULL,
    original_filename TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT (datetime('now'))
);

