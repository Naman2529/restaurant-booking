CREATE EXTENSION IF NOT EXISTS pgcrypto;

TRUNCATE reservation, floor_feature, restaurant_staff, app_user, dining_table, restaurant RESTART IDENTITY CASCADE;

-- Spice Route and Coastal Kitchen stay first (ids 1 and 2): the tests use them.
INSERT INTO restaurant (name, cuisine, tagline, photo, address, phone) VALUES
    ('Spice Route',            'North Indian',            'Slow-cooked curries by a lily pond',          '/photos/spice-route.webp',     '12 Connaught Place, New Delhi',       '+91 11 4000 1234'),
    ('Coastal Kitchen',        'Seafood',                 'Catch of the day, with the sea at your table', '/photos/coastal-kitchen.webp', '45 Marine Drive, Mumbai',             '+91 22 4000 5678'),
    ('Café Lumière',           'French café & bakery',    'Croissants, coffee and a sunny street terrace', '/photos/cafe-lumiere.jpg',    '8 Rue Romain Rolland, Puducherry',    '+91 413 400 2468'),
    ('Nonna''s Table',         'Italian trattoria',       'Wood-fired pizza and pasta made every morning', '/photos/nonnas-table.jpg',    '21 Church Street, Bengaluru',         '+91 80 4000 1357'),
    ('The Hillside Tea Room',  'Tea room & bakes',        'Darjeeling first flush with a mountain view',  '/photos/hillside-tea-room.jpg', '3 Mall Road, Darjeeling',            '+91 354 400 9753'),
    ('Lotus Pond',             'Kerala',                  'Appam, stew and a courtyard full of lotuses',  '/photos/lotus-pond.jpg',      '17 Princess Street, Fort Kochi',      '+91 484 400 8642');

-- pos_x / pos_y = centre of the table on a 1000 x 640 plan.
INSERT INTO dining_table (restaurant_id, table_number, capacity, pos_x, pos_y)
SELECT r.restaurant_id, v.table_number, v.capacity, v.pos_x, v.pos_y
FROM (VALUES
    ('Spice Route',             1,  2, 170,  80),
    ('Spice Route',             2,  2, 170, 170),
    ('Spice Route',             3,  2, 170, 260),
    ('Spice Route',             4,  2, 170, 350),
    ('Spice Route',             5,  4, 330, 230),
    ('Spice Route',             6,  4, 670, 230),
    ('Spice Route',             7,  4, 330, 420),
    ('Spice Route',             8,  4, 670, 420),
    ('Spice Route',             9,  6, 330, 560),
    ('Spice Route',            10,  6, 620, 560),
    ('Spice Route',            11,  8, 500, 140),
    ('Spice Route',            12,  8, 500, 450),
    ('Spice Route',            13, 10, 170, 480),
    ('Spice Route',            14, 20, 850, 110),
    ('Spice Route',            15, 20, 850, 270),
    ('Coastal Kitchen',         1,  2, 150, 180),
    ('Coastal Kitchen',         2,  2, 260, 180),
    ('Coastal Kitchen',         3,  4, 420, 190),
    ('Coastal Kitchen',         4,  4, 560, 190),
    ('Coastal Kitchen',         5,  6, 720, 190),
    ('Coastal Kitchen',         6,  8, 300, 360),
    ('Coastal Kitchen',         7, 10, 560, 360),
    ('Coastal Kitchen',         8, 20, 700, 500),
    ('Café Lumière',            1,  2, 120, 570),
    ('Café Lumière',            2,  2, 240, 570),
    ('Café Lumière',            3,  2, 360, 570),
    ('Café Lumière',            4,  2, 480, 570),
    ('Café Lumière',            5,  4, 180, 260),
    ('Café Lumière',            6,  4, 330, 260),
    ('Café Lumière',            7,  4, 480, 260),
    ('Café Lumière',            8,  6, 330, 410),
    ('Café Lumière',            9,  8, 560, 410),
    ('Café Lumière',           10, 20, 720, 200),
    ('Nonna''s Table',          1,  2, 170, 150),
    ('Nonna''s Table',          2,  2, 170, 250),
    ('Nonna''s Table',          3,  4, 320, 170),
    ('Nonna''s Table',          4,  4, 470, 170),
    ('Nonna''s Table',          5,  4, 620, 170),
    ('Nonna''s Table',          6,  6, 300, 330),
    ('Nonna''s Table',          7,  6, 480, 330),
    ('Nonna''s Table',          8,  8, 680, 330),
    ('Nonna''s Table',          9, 10, 300, 480),
    ('Nonna''s Table',         10, 20, 640, 500),
    ('The Hillside Tea Room',   1,  2, 300, 120),
    ('The Hillside Tea Room',   2,  2, 500, 120),
    ('The Hillside Tea Room',   3,  2, 700, 120),
    ('The Hillside Tea Room',   4,  4, 200, 300),
    ('The Hillside Tea Room',   5,  4, 420, 300),
    ('The Hillside Tea Room',   6,  6, 640, 300),
    ('The Hillside Tea Room',   7,  8, 420, 470),
    ('Lotus Pond',              1,  2, 310, 230),
    ('Lotus Pond',              2,  2, 690, 230),
    ('Lotus Pond',              3,  4, 300, 360),
    ('Lotus Pond',              4,  4, 700, 360),
    ('Lotus Pond',              5,  6, 500, 140),
    ('Lotus Pond',              6,  6, 500, 450),
    ('Lotus Pond',              7,  8, 220, 520),
    ('Lotus Pond',              8, 10, 220, 110),
    ('Lotus Pond',              9, 20, 700, 530)
) AS v(restaurant, table_number, capacity, pos_x, pos_y)
JOIN restaurant r ON r.name = v.restaurant;

-- x / y = top-left corner on the same 1000 x 640 plan.
INSERT INTO floor_feature (restaurant_id, kind, label, x, y, width, height)
SELECT r.restaurant_id, v.kind, v.label, v.x, v.y, v.width, v.height
FROM (VALUES
    ('Spice Route',           'kitchen',   'Kitchen pass',            380,  20, 240,  60),
    ('Spice Route',           'bar',       'Bar',                      40,  40,  70, 300),
    ('Spice Route',           'pond',      'Lily pond',               420, 260, 160, 110),
    ('Spice Route',           'garden',    'Courtyard garden',        730, 400, 230, 180),
    ('Spice Route',           'entrance',  'Entrance',                440, 600, 120,  40),
    ('Coastal Kitchen',       'deck',      'Sea-view deck',            40,  20, 920,  90),
    ('Coastal Kitchen',       'bar',       'Bar',                     880, 160,  80, 260),
    ('Coastal Kitchen',       'kitchen',   'Kitchen',                  40, 520, 220, 100),
    ('Coastal Kitchen',       'entrance',  'Entrance',                600, 600, 120,  40),
    ('Café Lumière',          'counter',   'Pastry counter',           40,  30, 300,  60),
    ('Café Lumière',          'bar',       'Espresso bar',            880,  60,  80, 280),
    ('Café Lumière',          'fireplace', 'Fireplace',                40, 200,  40, 120),
    ('Café Lumière',          'terrace',   'Street terrace',           40, 520, 640, 100),
    ('Café Lumière',          'garden',    'Flower stall',            720, 500, 120, 100),
    ('Café Lumière',          'entrance',  'Entrance',                860, 600, 100,  40),
    ('Nonna''s Table',        'kitchen',   'Wood-fired oven',         420,  20, 160,  70),
    ('Nonna''s Table',        'bar',       'Wine bar',                 40, 120,  70, 280),
    ('Nonna''s Table',        'garden',    'Herb garden',             860, 120, 100, 400),
    ('Nonna''s Table',        'entrance',  'Entrance',                440, 600, 120,  40),
    ('The Hillside Tea Room', 'window',    'Bay window, mountain view', 200, 20, 600,  50),
    ('The Hillside Tea Room', 'counter',   'Tea counter',             860, 140, 100, 260),
    ('The Hillside Tea Room', 'fireplace', 'Fireplace',                40, 220,  40, 160),
    ('The Hillside Tea Room', 'shelf',     'Bookshelf',                40, 560, 260,  40),
    ('The Hillside Tea Room', 'entrance',  'Entrance',                760, 600, 120,  40),
    ('Lotus Pond',            'pond',      'Lotus pond',              380, 220, 240, 160),
    ('Lotus Pond',            'kitchen',   'Kitchen',                 760,  20, 200,  70),
    ('Lotus Pond',            'bar',       'Coconut bar',              40,  40,  70, 240),
    ('Lotus Pond',            'garden',    'Banana grove',            820, 460, 140, 140),
    ('Lotus Pond',            'entrance',  'Entrance',                440, 600, 120,  40)
) AS v(restaurant, kind, label, x, y, width, height)
JOIN restaurant r ON r.name = v.restaurant;

INSERT INTO app_user (email, full_name, phone, password_hash, email_verified_at) VALUES
    ('aarav@example.com', 'Aarav Sharma', '+91 98100 00001', crypt('password123', gen_salt('bf')), now()),
    ('priya@example.com', 'Priya Iyer',   '+91 98100 00002', crypt('password123', gen_salt('bf')), now()),
    ('rohan@example.com', 'Rohan Mehta',  '+91 98100 00003', crypt('password123', gen_salt('bf')), now()),
    ('meera@example.com', 'Meera Nair',   '+91 98100 00004', crypt('password123', gen_salt('bf')), NULL);

-- Staff ids 1-4 are the original two restaurants (the tests use them by email).
INSERT INTO restaurant_staff (restaurant_id, email, full_name, password_hash, role)
SELECT r.restaurant_id, v.email, v.full_name, crypt('password123', gen_salt('bf')), v.role
FROM (VALUES
    ('Spice Route',           'reception@spiceroute.example.com',     'Kavya Rao',       'receptionist'),
    ('Spice Route',           'waiter@spiceroute.example.com',        'Arjun Singh',     'waiter'),
    ('Coastal Kitchen',       'reception@coastalkitchen.example.com', 'Neha Pillai',     'receptionist'),
    ('Coastal Kitchen',       'waiter@coastalkitchen.example.com',    'Vikram Das',      'waiter'),
    ('Café Lumière',          'reception@cafelumiere.example.com',    'Ananya Bose',     'receptionist'),
    ('Café Lumière',          'waiter@cafelumiere.example.com',       'Karan Malhotra',  'waiter'),
    ('Nonna''s Table',        'reception@nonnastable.example.com',    'Riya Kapoor',     'receptionist'),
    ('Nonna''s Table',        'waiter@nonnastable.example.com',       'Dev Patel',       'waiter'),
    ('The Hillside Tea Room', 'reception@hillsidetea.example.com',    'Tenzin Lama',     'receptionist'),
    ('The Hillside Tea Room', 'waiter@hillsidetea.example.com',       'Asha Gurung',     'waiter'),
    ('Lotus Pond',            'reception@lotuspond.example.com',      'Lakshmi Menon',   'receptionist'),
    ('Lotus Pond',            'waiter@lotuspond.example.com',         'Joseph Mathew',   'waiter')
) AS v(restaurant, email, full_name, role)
JOIN restaurant r ON r.name = v.restaurant
ORDER BY CASE v.restaurant WHEN 'Spice Route' THEN 1 WHEN 'Coastal Kitchen' THEN 2 ELSE 3 END,
         v.restaurant, v.role DESC;  -- waiter before receptionist: keeps the old ids (1 = Spice waiter, 2 = Spice receptionist)

INSERT INTO reservation (user_id, table_id, party_size, period, status, seated_at, cancelled_at)
SELECT u.user_id, t.table_id, v.party_size, v.period::tsrange, v.status,
       v.seated_at::timestamptz, v.cancelled_at::timestamptz
FROM (VALUES
    ('aarav@example.com', 'Spice Route',      5,  3, '[2026-10-30 19:00, 2026-10-30 21:00)', 'booked',    NULL,                NULL),
    ('aarav@example.com', 'Spice Route',      5,  3, '[2026-10-30 19:30, 2026-10-30 21:30)', 'cancelled', NULL,                '2026-10-14 18:00'),
    ('priya@example.com', 'Spice Route',     13,  9, '[2026-10-30 20:00, 2026-10-30 22:00)', 'booked',    NULL,                NULL),
    ('rohan@example.com', 'Spice Route',     14, 15, '[2026-10-31 12:00, 2026-10-31 14:00)', 'booked',    NULL,                NULL),
    ('priya@example.com', 'Coastal Kitchen',  6,  7, '[2026-10-31 21:00, 2026-10-31 23:00)', 'booked',    NULL,                NULL),
    ('priya@example.com', 'Coastal Kitchen',  3,  4, '[2026-10-10 13:00, 2026-10-10 15:00)', 'completed', '2026-10-10 13:05', NULL),
    ('rohan@example.com', 'Coastal Kitchen',  1,  2, '[2026-10-10 08:00, 2026-10-10 10:00)', 'no_show',   NULL,                NULL)
) AS v(email, restaurant, table_number, party_size, period, status, seated_at, cancelled_at)
JOIN app_user u ON u.email = v.email
JOIN restaurant r ON r.name = v.restaurant
JOIN dining_table t ON t.restaurant_id = r.restaurant_id AND t.table_number = v.table_number;
