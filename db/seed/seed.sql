CREATE EXTENSION IF NOT EXISTS pgcrypto;

TRUNCATE reservation, restaurant_staff, app_user, dining_table, restaurant RESTART IDENTITY CASCADE;

INSERT INTO restaurant (name, address, phone) VALUES
    ('Spice Route',     '12 Connaught Place, New Delhi', '+91 11 4000 1234'),
    ('Coastal Kitchen', '45 Marine Drive, Mumbai',       '+91 22 4000 5678');

INSERT INTO dining_table (restaurant_id, table_number, capacity)
SELECT r.restaurant_id, v.table_number, v.capacity
FROM (VALUES
    ('Spice Route',      1,  2),
    ('Spice Route',      2,  2),
    ('Spice Route',      3,  2),
    ('Spice Route',      4,  2),
    ('Spice Route',      5,  4),
    ('Spice Route',      6,  4),
    ('Spice Route',      7,  4),
    ('Spice Route',      8,  4),
    ('Spice Route',      9,  6),
    ('Spice Route',     10,  6),
    ('Spice Route',     11,  8),
    ('Spice Route',     12,  8),
    ('Spice Route',     13, 10),
    ('Spice Route',     14, 20),
    ('Spice Route',     15, 20),
    ('Coastal Kitchen',  1,  2),
    ('Coastal Kitchen',  2,  2),
    ('Coastal Kitchen',  3,  4),
    ('Coastal Kitchen',  4,  4),
    ('Coastal Kitchen',  5,  6),
    ('Coastal Kitchen',  6,  8),
    ('Coastal Kitchen',  7, 10),
    ('Coastal Kitchen',  8, 20)
) AS v(restaurant, table_number, capacity)
JOIN restaurant r ON r.name = v.restaurant;

INSERT INTO app_user (email, full_name, phone, password_hash, email_verified_at) VALUES
    ('aarav@example.com', 'Aarav Sharma', '+91 98100 00001', crypt('password123', gen_salt('bf')), now()),
    ('priya@example.com', 'Priya Iyer',   '+91 98100 00002', crypt('password123', gen_salt('bf')), now()),
    ('rohan@example.com', 'Rohan Mehta',  '+91 98100 00003', crypt('password123', gen_salt('bf')), now()),
    ('meera@example.com', 'Meera Nair',   '+91 98100 00004', crypt('password123', gen_salt('bf')), NULL);

INSERT INTO restaurant_staff (restaurant_id, email, full_name, password_hash, role)
SELECT r.restaurant_id, v.email, v.full_name, crypt('password123', gen_salt('bf')), v.role
FROM (VALUES
    ('Spice Route',     'reception@spiceroute.example.com',    'Kavya Rao',    'receptionist'),
    ('Spice Route',     'waiter@spiceroute.example.com',       'Arjun Singh',  'waiter'),
    ('Coastal Kitchen', 'reception@coastalkitchen.example.com', 'Neha Pillai', 'receptionist'),
    ('Coastal Kitchen', 'waiter@coastalkitchen.example.com',    'Vikram Das',  'waiter')
) AS v(restaurant, email, full_name, role)
JOIN restaurant r ON r.name = v.restaurant;

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
