-- DEMO ONLY, for screenshots of the staff panel. NOT part of reset.sql.
-- Pins the database clock to 19:20 today (IST) and adds bookings at Spice
-- Route in every seat-map colour, so the dashboard looks like a busy evening
-- at any hour. Undo everything with:  psql -f db/reset.sql
--
--   psql -f db/demo/staff_demo.sql
--   log in at /login?as=business as reception@spiceroute.example.com / password123

CREATE OR REPLACE FUNCTION util.ist_now()
RETURNS timestamp
LANGUAGE sql
STABLE
AS $$
    SELECT (now() AT TIME ZONE 'Asia/Kolkata')::date + time '19:20';
$$;

INSERT INTO reservation (user_id, table_id, party_size, period, status, seated_at)
SELECT u.user_id, t.table_id, v.party,
       tsrange(d.today + v.starts, d.today + v.ends),
       v.status,
       CASE WHEN v.status IN ('seated', 'completed') THEN now() END
FROM (VALUES
    ('aarav@example.com',  2,  2, time '19:30', time '21:30', 'booked'),     -- transparent: arriving soon
    ('priya@example.com',  5,  3, time '19:00', time '21:00', 'booked'),     -- gray: late
    ('rohan@example.com',  9,  5, time '18:30', time '20:30', 'seated'),     -- red: eating
    ('priya@example.com', 11,  7, time '17:00', time '19:00', 'seated'),     -- orange: over time
    ('aarav@example.com',  6,  4, time '20:30', time '22:30', 'booked'),     -- later tonight
    ('rohan@example.com', 14, 14, time '21:00', time '23:00', 'booked'),     -- hall, later
    ('aarav@example.com',  3,  2, time '13:00', time '15:00', 'completed')   -- done at lunch
) AS v(email, table_number, party, starts, ends, status)
CROSS JOIN (SELECT (now() AT TIME ZONE 'Asia/Kolkata')::date AS today) d
JOIN app_user u ON u.email = v.email
JOIN restaurant r ON r.name = 'Spice Route'
JOIN dining_table t ON t.restaurant_id = r.restaurant_id AND t.table_number = v.table_number;

\echo 'Demo loaded: the DB clock reads 19:20 today. Run psql -f db/reset.sql when you are done.'
