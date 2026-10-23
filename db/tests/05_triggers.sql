-- Test 05: triggers (party_fits_table, status_transition, status_timestamps).
--   psql -f db/tests/05_triggers.sql
-- Raw INSERT / UPDATE on purpose, skipping the procedures: the triggers are the
-- backstop that still holds when someone writes to the table directly.

\echo
\echo '################################################################'
\echo '##  TEST 05 - TRIGGERS'
\echo '################################################################'
\ir _setup.sql
\set VERBOSITY verbose

\echo
\echo '=== T5.0  Triggers on reservation  (EXPECT: 3 BEFORE ROW triggers, all enabled) ==='
SELECT tgname AS trigger, tgenabled = 'O' AS enabled, pg_get_triggerdef(oid) AS definition
FROM pg_trigger
WHERE tgrelid = 'reservation'::regclass AND NOT tgisinternal
ORDER BY tgname;

\echo
\echo '---------------- party_fits_table (BEFORE INSERT OR UPDATE OF party_size, table_id) ----------------'

\echo
\echo '=== T5.1  Party of 2 on the 10-seater (table 13)  (EXPECT: RB422 table 13 (capacity 10) is not allowed for a party of 2) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:aarav, pg_temp.tid('Spice Route', 13), 2, '[2026-11-12 13:00, 2026-11-12 15:00)');

\echo
\echo '=== T5.2  Party of 10 in a hall (table 14, halls are 11+ only)  (EXPECT: RB422 table 14 (capacity 20) is not allowed for a party of 10) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:aarav, pg_temp.tid('Spice Route', 14), 10, '[2026-11-12 13:00, 2026-11-12 15:00)');

\echo
\echo '=== T5.3  Party of 12 in a hall  (EXPECT: inserted) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:aarav, pg_temp.tid('Spice Route', 14), 12, '[2026-11-12 13:00, 2026-11-12 15:00)')
RETURNING reservation_id, party_size;

\echo
\echo '=== T5.4  Party of 3 on a 4-seater (table 5), then grows to 4  (EXPECT: both fine) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:priya, pg_temp.tid('Spice Route', 5), 3, '[2026-11-12 13:00, 2026-11-12 15:00)')
RETURNING reservation_id AS p5 \gset
UPDATE reservation SET party_size = 4 WHERE reservation_id = :p5;

\echo
\echo '=== T5.5  Same party grows to 7 by a raw UPDATE  (EXPECT: RB422 table 5 (capacity 4) is not allowed for a party of 7) ==='
UPDATE reservation SET party_size = 7 WHERE reservation_id = :p5;

\echo
\echo '=== T5.6  Raw UPDATE moves the party of 4 to a 2-seater (table 1)  (EXPECT: RB422 table 1 (capacity 2) is not allowed for a party of 4) ==='
UPDATE reservation SET table_id = pg_temp.tid('Spice Route', 1) WHERE reservation_id = :p5;

\echo
\echo '---------------- status_transition (BEFORE UPDATE OF status) ----------------'
\echo '    allowed: booked -> seated | cancelled | no_show,  seated -> completed'

\set QUIET on
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:aarav, pg_temp.tid('Spice Route', 2), 2, '[2026-11-12 19:00, 2026-11-12 21:00)')
RETURNING reservation_id AS booked \gset
INSERT INTO reservation (user_id, table_id, party_size, period, status, seated_at)
VALUES (:priya, pg_temp.tid('Spice Route', 3), 2, '[2026-11-10 19:00, 2026-11-10 21:00)', 'seated', now())
RETURNING reservation_id AS seated \gset
SELECT reservation_id AS completed FROM reservation WHERE status = 'completed' LIMIT 1 \gset
SELECT reservation_id AS cancelled FROM reservation WHERE status = 'cancelled' LIMIT 1 \gset
SELECT reservation_id AS no_show   FROM reservation WHERE status = 'no_show'   LIMIT 1 \gset
\set QUIET off

\echo
\echo '=== T5.7  booked -> completed (skips seated)  (EXPECT: RB409 reservation ... cannot go from booked to completed) ==='
UPDATE reservation SET status = 'completed' WHERE reservation_id = :booked;

\echo
\echo '=== T5.8  seated -> booked (going backwards)  (EXPECT: RB409 ... cannot go from seated to booked) ==='
UPDATE reservation SET status = 'booked' WHERE reservation_id = :seated;

\echo
\echo '=== T5.9  completed -> seated (completed is final)  (EXPECT: RB409 ... cannot go from completed to seated) ==='
UPDATE reservation SET status = 'seated' WHERE reservation_id = :completed;

\echo
\echo '=== T5.10 cancelled -> booked (no un-cancelling)  (EXPECT: RB409 ... cannot go from cancelled to booked) ==='
UPDATE reservation SET status = 'booked' WHERE reservation_id = :cancelled;

\echo
\echo '=== T5.11 no_show -> seated (late arrival)  (EXPECT: RB409 ... cannot go from no_show to seated) ==='
UPDATE reservation SET status = 'seated' WHERE reservation_id = :no_show;

\echo
\echo '=== T5.12 seated -> seated (same status)  (EXPECT: UPDATE 1, a no-op is allowed) ==='
UPDATE reservation SET status = 'seated' WHERE reservation_id = :seated;

\echo
\echo '=== T5.13 seated -> completed  (EXPECT: UPDATE 1) ==='
UPDATE reservation SET status = 'completed' WHERE reservation_id = :seated;

\echo
\echo '---------------- status_timestamps (BEFORE UPDATE OF status) ----------------'

\echo
\echo '=== T5.14 booked -> seated with a fake back-dated seated_at  (EXPECT: seated_at overwritten with now(), not 2020) ==='
UPDATE reservation SET status = 'seated', seated_at = '2020-01-01 12:00+05:30'
WHERE reservation_id = :booked
RETURNING reservation_id, status, seated_at, seated_at = now() AS is_now;

\echo
\echo '=== T5.15 booked -> cancelled with no cancelled_at given  (EXPECT: cancelled_at filled in with now()) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:aarav, pg_temp.tid('Spice Route', 4), 2, '[2026-11-12 19:00, 2026-11-12 21:00)')
RETURNING reservation_id AS to_cancel \gset
UPDATE reservation SET status = 'cancelled' WHERE reservation_id = :to_cancel
RETURNING reservation_id, status, cancelled_at = now() AS cancelled_at_is_now;

\echo
\echo '=== T5.16 INSERT is not checked on purpose: a seed / admin can insert history  (EXPECT: inserted as completed) ==='
INSERT INTO reservation (user_id, table_id, party_size, period, status, seated_at)
VALUES (:rohan, pg_temp.tid('Spice Route', 6), 4, '[2026-10-01 13:00, 2026-10-01 15:00)', 'completed', '2026-10-01 13:05+05:30')
RETURNING reservation_id, status, period;

ROLLBACK;
\echo '(rolled back: database unchanged)'
