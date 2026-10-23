-- Test 02: functions (util, customer, staff, auth).
--   psql -f db/tests/02_functions.sql

\echo
\echo '################################################################'
\echo '##  TEST 02 - FUNCTIONS'
\echo '################################################################'

\echo
\echo '=== T2.1  util.ist_now() before the clock is pinned: real IST time, no time zone  (EXPECT: matches now() in Asia/Kolkata) ==='
SELECT util.ist_now() AS ist_now,
       now() AT TIME ZONE 'Asia/Kolkata' AS now_in_kolkata,
       pg_typeof(util.ist_now()) AS type;

\ir _setup.sql

\echo
\echo '=== T2.2  util.allowed_capacities(party): normal table first, at most one size up, halls 11+  (EXPECT: matches README table) ==='
SELECT p AS party_size, util.allowed_capacities(p) AS allowed_capacities
FROM unnest(ARRAY[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 20, 21]) AS p;

\echo
\echo '=== T2.3  customer.available_tables: Spice Route, 12 Nov 13:00, party 2, empty day  (EXPECT: 2-seaters 1-4, then 4-seaters 5-8) ==='
SELECT * FROM customer.available_tables(:spice, '2026-11-12 13:00', 2);

\echo
\echo '=== T2.4  Fill all four 2-seaters at 13:00, ask again  (EXPECT: only 4-seaters 5-8, the one-size-up upgrade) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
SELECT :rohan, pg_temp.tid('Spice Route', n), 2, '[2026-11-12 13:00, 2026-11-12 15:00)'
FROM generate_series(1, 4) AS n;
SELECT * FROM customer.available_tables(:spice, '2026-11-12 13:00', 2);

\echo
\echo '=== T2.5  Fill the 4-seaters too  (EXPECT: 0 rows, a 6-seater is two sizes up so never offered) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
SELECT :rohan, pg_temp.tid('Spice Route', n), 2, '[2026-11-12 13:00, 2026-11-12 15:00)'
FROM generate_series(5, 8) AS n;
SELECT * FROM customer.available_tables(:spice, '2026-11-12 13:00', 2);

\echo
\echo '=== T2.6  Party 9 only fits the 10-seater (table 13). Book it 18:00-20:00, ask for 20:00 and 20:30  (EXPECT: 20:00 none, buffer; 20:30 table 13) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:priya, pg_temp.tid('Spice Route', 13), 9, '[2026-11-12 18:00, 2026-11-12 20:00)');
SELECT '20:00' AS asked_for, * FROM customer.available_tables(:spice, '2026-11-12 20:00', 9);
SELECT '20:30' AS asked_for, * FROM customer.available_tables(:spice, '2026-11-12 20:30', 9);

\echo
\echo '=== T2.7  customer.available_slots: Spice Route, 12 Nov, party 9  (EXPECT: 07:00-15:30, gap 16:00-20:00, then 20:30 and 21:00) ==='
SELECT * FROM customer.available_slots(:spice, '2026-11-12', 9);

\echo
\echo '=== T2.8  available_slots for "today" (10 Nov, now 19:20), party 2  (EXPECT: only 19:30, 20:00, 20:30, 21:00; past slots hidden) ==='
SELECT * FROM customer.available_slots(:spice, '2026-11-10', 2);

\echo
\echo '=== T2.9  customer.can_cancel (now 19:20)  (EXPECT: 20:00 own = t; 19:30 own (10 min away) = f; someone else''s = f; cancelled = f) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:aarav, pg_temp.tid('Spice Route', 1), 2, '[2026-11-10 20:00, 2026-11-10 22:00)')
RETURNING reservation_id AS r_2000 \gset
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:aarav, pg_temp.tid('Spice Route', 2), 2, '[2026-11-10 19:30, 2026-11-10 21:30)')
RETURNING reservation_id AS r_1930 \gset
SELECT reservation_id AS r_cancelled FROM reservation WHERE status = 'cancelled' LIMIT 1 \gset
SELECT case_name, customer.can_cancel(res, usr) AS can_cancel
FROM (VALUES
    ('own booking at 20:00',          :r_2000::bigint,      :aarav::bigint),
    ('own booking at 19:30',          :r_1930::bigint,      :aarav::bigint),
    ('Priya asks about Aarav''s 20:00', :r_2000::bigint,    :priya::bigint),
    ('own cancelled booking',         :r_cancelled::bigint, :aarav::bigint),
    ('reservation that does not exist', 999999::bigint,     :aarav::bigint)
) AS v(case_name, res, usr);

\echo
\echo '=== T2.10 customer.my_reservations(Aarav): newest first, table numbers, can_cancel per row  (EXPECT: 20:00 and 19:30 today, 2 seed rows on 30 Oct) ==='
SELECT reservation_id, restaurant_name, table_number, party_size, starts_at, status, can_cancel
FROM customer.my_reservations(:aarav);

\echo
\echo '=== T2.11 customer.restaurants()  (EXPECT: 6 rows by name, with cuisine and tagline) ==='
SELECT restaurant_id, name, cuisine, tagline FROM customer.restaurants();

\echo
\echo '=== T2.12 Seat map setup at Spice Route for today (now 19:20) ==='
\echo '    table 3  booked 21:00-23:00   -> green        (more than 30 min away)'
\echo '    table 1  booked 20:00-22:00   -> green        (40 min away)'
\echo '    table 2  booked 19:30-21:30   -> transparent  (arrives within 30 min)'
\echo '    table 5  booked 19:00-21:00   -> gray         (started, guests not here)'
\echo '    table 9  seated 18:30-20:30   -> red          (seated, inside the sitting)'
\echo '    table 11 seated 17:00-19:00   -> orange       (sitting is over)'
INSERT INTO reservation (user_id, table_id, party_size, period, status, seated_at) VALUES
    (:rohan, pg_temp.tid('Spice Route', 3),  2, '[2026-11-10 21:00, 2026-11-10 23:00)', 'booked', NULL),
    (:priya, pg_temp.tid('Spice Route', 5),  3, '[2026-11-10 19:00, 2026-11-10 21:00)', 'booked', NULL),
    (:rohan, pg_temp.tid('Spice Route', 9),  5, '[2026-11-10 18:30, 2026-11-10 20:30)', 'seated', now()),
    (:priya, pg_temp.tid('Spice Route', 11), 7, '[2026-11-10 17:00, 2026-11-10 19:00)', 'seated', now());

\echo
\echo '=== T2.13 staff.seat_map(Spice Route)  (EXPECT: colours as listed above, every other table green) ==='
SELECT table_number, capacity, colour, reservation_id, period FROM staff.seat_map(:spice);

\echo
\echo '=== T2.14 staff.day_reservations(Spice Route, 10 Nov): staff list with name + phone, table numbers only  (EXPECT: 6 rows by start time) ==='
SELECT * FROM staff.day_reservations(:spice, '2026-11-10');

\echo
\echo '=== T2.15 staff.day_reservations for Coastal Kitchen, same day  (EXPECT: 0 rows, staff only see their own restaurant) ==='
SELECT * FROM staff.day_reservations(:coastal, '2026-11-10');

\echo
\echo '=== T2.16 customer.login_info: exact, different case, unknown  (EXPECT: Aarav twice, verified; unknown = 0 rows; Meera unverified) ==='
SELECT 'aarav@example.com' AS asked, user_id, full_name, email_verified, left(password_hash, 7) || '...' AS hash_prefix
FROM customer.login_info('aarav@example.com');
SELECT 'AARAV@Example.COM' AS asked, user_id, full_name, email_verified, left(password_hash, 7) || '...' AS hash_prefix
FROM customer.login_info('AARAV@Example.COM');
SELECT 'nobody@example.com' AS asked, user_id, full_name FROM customer.login_info('nobody@example.com');
SELECT 'meera@example.com' AS asked, user_id, full_name, email_verified FROM customer.login_info('meera@example.com');

\echo
\echo '=== T2.17 staff.login_info: restaurant and role go into the staff token  (EXPECT: Kavya Rao, Spice Route, receptionist) ==='
SELECT staff_id, restaurant_id, full_name, role, left(password_hash, 7) || '...' AS hash_prefix
FROM staff.login_info('reception@spiceroute.example.com');

\echo
\echo '=== T2.18 util.check_staff: Spice receptionist, Spice restaurant, receptionist-only action  (EXPECT: passes, empty result) ==='
SELECT util.check_staff(:spice_rec, :spice, ARRAY['receptionist']);

\echo
\echo '=== T2.19 util.check_staff: Spice waiter on a receptionist-only action  (EXPECT: ERROR only a receptionist can do this) ==='
SELECT util.check_staff(:spice_wait, :spice, ARRAY['receptionist']);

\echo
\echo '=== T2.20 util.check_staff: Coastal receptionist on a Spice Route reservation  (EXPECT: ERROR reservation not found, same as missing) ==='
SELECT util.check_staff(:coastal_rec, :spice, ARRAY['receptionist']);

\echo
\echo '=== T2.21 util.check_staff: staff id that does not exist  (EXPECT: ERROR staff account not found) ==='
SELECT util.check_staff(999999, :spice, ARRAY['receptionist', 'waiter']);

\echo
\echo '=== T2.22 auth.is_revoked for a token id never revoked  (EXPECT: f; revoke_token is tested in 03) ==='
SELECT auth.is_revoked('never-logged-out') AS is_revoked;

\echo
\echo '=== T2.23 util.table_free on 12 Nov 13:00: table 1 (booked in T2.4) vs table 13 (booked 18:00)  (EXPECT: f, t) ==='
SELECT util.table_free(pg_temp.tid('Spice Route', 1), '2026-11-12 13:00')  AS table_1_free,
       util.table_free(pg_temp.tid('Spice Route', 13), '2026-11-12 13:00') AS table_13_free;

\echo
\echo '=== T2.24 customer.table_availability: Spice Route, 12 Nov 13:00, party 2  (EXPECT: 1-8 fit but taken; 9-15 free but wrong size; nothing bookable) ==='
SELECT *, fits_party AND is_free AS bookable
FROM customer.table_availability(:spice, '2026-11-12 13:00', 2);

\echo
\echo '=== T2.25 Same at 16:00, party 4  (EXPECT: 4-seaters 5-8 and 6-seaters 9-10 bookable, the rest not) ==='
SELECT table_number, capacity, fits_party, is_free, fits_party AND is_free AS bookable
FROM customer.table_availability(:spice, '2026-11-12 16:00', 4);

\echo
\echo '=== T2.26 A start that has passed (today 19:00, now 19:20)  (EXPECT: is_free = f for every table) ==='
SELECT count(*) AS tables, count(*) FILTER (WHERE is_free) AS free
FROM customer.table_availability(:spice, '2026-11-10 19:00', 2);

\echo
\echo '=== T2.27 customer.floor_plan(Spice Route)  (EXPECT: 5 features, 15 tables with positions) ==='
SELECT fp ->> 'name' AS name,
       jsonb_array_length(fp -> 'features') AS features,
       jsonb_array_length(fp -> 'tables') AS tables,
       fp -> 'features' -> 2 AS third_feature,
       fp -> 'tables' -> 0 AS first_table
FROM customer.floor_plan(:spice) AS fp;

\echo
\echo '=== T2.28 customer.floor_plan for a restaurant that does not exist  (EXPECT: NULL) ==='
SELECT customer.floor_plan(999999) IS NULL AS is_null;

\echo
\echo '=== T2.29 customer.profile and staff.profile (who is logged in)  (EXPECT: Meera unverified; Kavya, receptionist, Spice Route) ==='
SELECT user_id, full_name, email, email_verified FROM customer.profile(:meera);
SELECT staff_id, full_name, role, restaurant_name FROM staff.profile(:spice_rec);

ROLLBACK;
\echo '(rolled back: database unchanged)'
