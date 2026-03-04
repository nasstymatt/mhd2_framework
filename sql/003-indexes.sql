CREATE INDEX IF NOT EXISTS idx_tiers_position       ON tiers(tierlist_id, position);
CREATE INDEX IF NOT EXISTS idx_tier_images_position ON tier_images(tierlist_id, tier_id, position);
