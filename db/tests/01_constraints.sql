-- Test 01: table constraints (CHECK, UNIQUE, FK, exclusion).
-- Run from the project root as postgres, after loading .env:
--   psql -f db/tests/01_constraints.sql
-- Raw INSERTs on purpose: this proves the tables reject bad rows on their own,
-- even when nobody goes through the procedures.

\echo
\echo '################################################################'
\echo '##  TEST 01 - TABLE CONSTRAINTS'
\echo '################################################################'
\ir _setup.sql

\echo
\echo '=== T1.1  Base booking: Spice Route table 1, 5 Nov 09:00-11:00  (EXPECT: inserted) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:aarav, pg_temp.tid('Spice Route', 1), 2, '[2026-11-05 09:00, 2026-11-05 11:00)')
RETURNING reservation_id, status, period;

\echo
\echo '=== T1.2  Same table, overlapping 10:00-12:00  (EXPECT: ERROR no_double_booking) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:priya, pg_temp.tid('Spice Route', 1), 2, '[2026-11-05 10:00, 2026-11-05 12:00)');

\echo
\echo '=== T1.3  Same table, 11:00 start = inside the 30-min buffer  (EXPECT: ERROR no_double_booking) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:priya, pg_temp.tid('Spice Route', 1), 2, '[2026-11-05 11:00, 2026-11-05 13:00)');

\echo
\echo '=== T1.4  Same table, 11:30 start = exactly at the buffer boundary  (EXPECT: inserted) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:priya, pg_temp.tid('Spice Route', 1), 2, '[2026-11-05 11:30, 2026-11-05 13:30)')
RETURNING reservation_id, status, period;

\echo
\echo '=== T1.5  Cancelled rows hold no table: seed has table 5 on 30 Oct booked 19:00 AND cancelled 19:30  (EXPECT: 2 rows) ==='
SELECT r.reservation_id, t.table_number, r.period, r.status
FROM reservation r JOIN dining_table t USING (table_id)
WHERE r.table_id = pg_temp.tid('Spice Route', 5) AND lower(r.period)::date = '2026-10-30'
ORDER BY lower(r.period);

\echo
\echo '=== T1.6  Start at 21:30 (last slot is 21:00)  (EXPECT: ERROR start_on_slot) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:aarav, pg_temp.tid('Spice Route', 1), 2, '[2026-11-06 21:30, 2026-11-06 22:30)');

\echo
\echo '=== T1.7  Start at 19:15 (not a :00 / :30 slot)  (EXPECT: ERROR start_on_slot) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:aarav, pg_temp.tid('Spice Route', 1), 2, '[2026-11-06 19:15, 2026-11-06 21:15)');

\echo
\echo '=== T1.8  Start at 06:30 (opens at 07:00)  (EXPECT: ERROR start_on_slot) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:aarav, pg_temp.tid('Spice Route', 1), 2, '[2026-11-06 06:30, 2026-11-06 08:30)');

\echo
\echo '=== T1.9  21:00 start ending 23:30 (close is 23:00)  (EXPECT: ERROR end_by_2300) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:aarav, pg_temp.tid('Spice Route', 1), 2, '[2026-11-06 21:00, 2026-11-06 23:30)');

\echo
\echo '=== T1.10 Period with an inclusive end "[ ]"  (EXPECT: ERROR period_shape) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:aarav, pg_temp.tid('Spice Route', 1), 2, '[2026-11-06 12:00, 2026-11-06 14:00]');

\echo
\echo '=== T1.11 Party size 21, party_fits_table trigger switched off  (EXPECT: ERROR reservation_party_size_check) ==='
-- The BEFORE trigger would reject this first (see 05_triggers.sql). Turning it off
-- for one statement shows the CHECK is a second, independent layer.
ALTER TABLE reservation DISABLE TRIGGER party_fits_table;
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:aarav, pg_temp.tid('Spice Route', 1), 21, '[2026-11-06 12:00, 2026-11-06 14:00)');
ALTER TABLE reservation ENABLE TRIGGER party_fits_table;

\echo
\echo '=== T1.12 Unknown status "pending"  (EXPECT: ERROR reservation_status_check) ==='
INSERT INTO reservation (user_id, table_id, party_size, period, status)
VALUES (:aarav, pg_temp.tid('Spice Route', 1), 2, '[2026-11-06 12:00, 2026-11-06 14:00)', 'pending');

\echo
\echo '=== T1.13 Booking for a user that does not exist  (EXPECT: ERROR foreign key reservation_user_id_fkey) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (999999, pg_temp.tid('Spice Route', 1), 2, '[2026-11-06 12:00, 2026-11-06 14:00)');

\echo
\echo '=== T1.14 Table with capacity 3 (sizes are 2/4/6/8/10/20)  (EXPECT: ERROR dining_table_capacity_check) ==='
INSERT INTO dining_table (restaurant_id, table_number, capacity) VALUES (:spice, 99, 3);

\echo
\echo '=== T1.15 Second "table 1" in the same restaurant  (EXPECT: ERROR unique dining_table_restaurant_id_table_number_key) ==='
INSERT INTO dining_table (restaurant_id, table_number, capacity) VALUES (:spice, 1, 2);

\echo
\echo '=== T1.16 Email that differs only in case: AARAV@EXAMPLE.COM  (EXPECT: ERROR unique app_user_email_key, citext) ==='
INSERT INTO app_user (email, full_name, password_hash)
VALUES ('AARAV@EXAMPLE.COM', 'Copy Cat', 'x');

\echo
\echo '=== T1.17 Verify token without an expiry  (EXPECT: ERROR verify_token_pair) ==='
INSERT INTO app_user (email, full_name, password_hash, verify_token_hash)
VALUES ('new@example.com', 'New User', 'x', 'somehash');

\echo
\echo '=== T1.18 Floor feature of an unknown kind "toilet"  (EXPECT: ERROR floor_feature_kind_check) ==='
INSERT INTO floor_feature (restaurant_id, kind, label, x, y, width, height)
VALUES (:spice, 'toilet', 'Toilet', 10, 10, 50, 50);

\echo
\echo '=== T1.19 Floor feature running off the 1000 x 640 plan  (EXPECT: ERROR feature_inside_plan) ==='
INSERT INTO floor_feature (restaurant_id, kind, label, x, y, width, height)
VALUES (:spice, 'bar', 'Long bar', 900, 10, 200, 50);

\echo
\echo '=== T1.20 Table placed outside the plan (x = 1200)  (EXPECT: ERROR dining_table_pos_x_check) ==='
INSERT INTO dining_table (restaurant_id, table_number, capacity, pos_x, pos_y) VALUES (:spice, 98, 2, 1200, 100);

ROLLBACK;
\echo '(rolled back: database unchanged)'
