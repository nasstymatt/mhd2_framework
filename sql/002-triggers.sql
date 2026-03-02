CREATE TRIGGER IF NOT EXISTS create_tierlist_defaults
AFTER INSERT ON tierlists
FOR EACH ROW
BEGIN
    INSERT INTO tiers (title, color, tierlist_id, position) VALUES ('S', '#FF7F7F', NEW.id, 1000.0);
    INSERT INTO tiers (title, color, tierlist_id, position) VALUES ('A', '#FFBF7F', NEW.id, 2000.0);
    INSERT INTO tiers (title, color, tierlist_id, position) VALUES ('B', '#FFDF7F', NEW.id, 3000.0);
    INSERT INTO tiers (title, color, tierlist_id, position) VALUES ('C', '#FFFF7F', NEW.id, 4000.0);
    INSERT INTO tiers (title, color, tierlist_id, position) VALUES ('D', '#7FBF7F', NEW.id, 5000.0);
END;
