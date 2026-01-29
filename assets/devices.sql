-- Create categories table
CREATE TABLE categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL
);

-- Create devices table
CREATE TABLE devices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category_id INTEGER,
    manufacturer TEXT NOT NULL,
    model TEXT NOT NULL,
    power_consumption REAL NOT NULL,
    is_user_added INTEGER DEFAULT 0,
    user_id TEXT,
    usage_hours_per_day REAL DEFAULT 0,
    FOREIGN KEY (category_id) REFERENCES categories(id)
);

-- Insert sample categories
INSERT INTO categories (id, name) VALUES
(1, 'Electronics'),
(2, 'Appliances'),
(3, 'Lighting');

-- Insert sample preset devices
INSERT INTO devices (category_id, manufacturer, model, power_consumption, is_user_added, usage_hours_per_day) VALUES
(1, 'Samsung', 'TV-55', 0.2, 0, 5),
(2, 'LG', 'Refrigerator', 0.5, 0, 24),
(3, 'Philips', 'LED Bulb', 0.01, 0, 6);