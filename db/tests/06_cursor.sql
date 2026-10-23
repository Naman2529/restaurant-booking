-- Test 06: cursor (staff.no_show_sweep).
--   psql -f db/tests/06_cursor.sql
-- The sweep walks overdue 'booked' rows with an explicit cursor and calls
-- mark_no_show on each inside its own BEGIN ... EXCEPTION block, so one bad row
-- is skipped and logged while the rest are still marked.

\echo
\echo '################################################################'
\echo '##  TEST 06 - CURSOR (no_show_sweep)'
\echo '################################################################'
\ir _setup.sql

\echo
\echo '=== Setup (now 10 Nov 19:20). Overdue = booked and start + 15 min <= now ==='
\echo '    P1  Spice table 1   booked 18:00  -> overdue'
\echo '    P2  Spice table 2   booked 19:00  -> overdue (19:15 <= 19:20)'
\echo '    P3  Spice table 3   booked 19:30  -> not started, left alone'
\echo '    P4  Spice table 4   seated 19:00  -> seated, left alone'
\echo '    P5  Coastal table 1 booked 18:00  -> other restaurant, left alone'
\echo '    + 3 seed Spice bookings on 30-31 Oct that nobody closed -> overdue'
\set QUIET on
INSERT INTO reservation (user_id, table_id, party_size, period) VALUES
    (:aarav, pg_temp.tid('Spice Route', 1), 2, '[2026-11-10 18:00, 2026-11-10 20:00)') RETURNING reservation_id AS p1 \gset
INSERT INTO reservation (user_id, table_id, party_size, period) VALUES
    (:priya, pg_temp.tid('Spice Route', 2), 2, '[2026-11-10 19:00, 2026-11-10 21:00)') RETURNING reservation_id AS p2 \gset
INSERT INTO reservation (user_id, table_id, party_size, period) VALUES
    (:rohan, pg_temp.tid('Spice Route', 3), 2, '[2026-11-10 19:30, 2026-11-10 21:30)') RETURNING reservation_id AS p3 \gset
INSERT INTO reservation (user_id, table_id, party_size, period, status, seated_at) VALUES
    (:aarav, pg_temp.tid('Spice Route', 4), 2, '[2026-11-10 19:00, 2026-11-10 21:00)', 'seated', now()) RETURNING reservation_id AS p4 \gset
INSERT INTO reservation (user_id, table_id, party_size, period) VALUES
    (:priya, pg_temp.tid('Coastal Kitchen', 1), 2, '[2026-11-10 18:00, 2026-11-10 20:00)') RETURNING reservation_id AS p5 \gset
\set QUIET off

\echo
\echo '=== T6.1  Coastal Kitchen receptionist sweeps Spice Route  (EXPECT: RB404, staff can only sweep their own restaurant) ==='
\set VERBOSITY verbose
CALL staff.no_show_sweep(:spice, :coastal_rec, 0, 0);

\echo
\echo '=== T6.2  Staff id that does not exist  (EXPECT: RB403 staff account not found) ==='
CALL staff.no_show_sweep(:spice, 999999, 0, 0);
\set VERBOSITY default

\echo
\echo '=== T6.3  What the cursor will walk (its own query)  (EXPECT: 3 seed rows + P1 + P2, oldest first) ==='
SELECT r.reservation_id, t.table_number, lower(r.period) AS starts_at, r.status
FROM reservation r
JOIN dining_table t ON t.table_id = r.table_id
WHERE t.restaurant_id = :spice
  AND r.status = 'booked'
  AND lower(r.period) + interval '15 minutes' <= util.ist_now()
ORDER BY lower(r.period);

\echo
\echo '=== T6.4  Sweep while P2 is made to fail (a test trigger stands in for a concurrent change)  (EXPECT: NOTICE per row, P2 skipped, marked 4, skipped 1) ==='
\set QUIET on
CREATE FUNCTION util.test_fail_one() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'simulated failure: row changed by another session';
END;
$$;
CREATE TRIGGER zz_test_fail BEFORE UPDATE ON reservation
FOR EACH ROW WHEN (OLD.reservation_id = :p2) EXECUTE FUNCTION util.test_fail_one();
\set QUIET off
CALL staff.no_show_sweep(:spice, :spice_wait, 0, 0);

\echo
\echo '=== T6.5  Test trigger removed, sweep again  (EXPECT: only P2 left, marked 1, skipped 0) ==='
\set QUIET on
DROP TRIGGER zz_test_fail ON reservation;
\set QUIET off
CALL staff.no_show_sweep(:spice, :spice_wait, 0, 0);

\echo
\echo '=== T6.6  Third sweep  (EXPECT: nothing left, marked 0, skipped 0) ==='
CALL staff.no_show_sweep(:spice, :spice_wait, 0, 0);

\echo
\echo '=== T6.7  Final statuses  (EXPECT: seed rows + P1 + P2 no_show; seed cancelled row untouched; P3 booked; P4 seated; P5 booked (Coastal)) ==='
SELECT r.reservation_id, rs.name AS restaurant, t.table_number, lower(r.period) AS starts_at, r.status
FROM reservation r
JOIN dining_table t ON t.table_id = r.table_id
JOIN restaurant rs ON rs.restaurant_id = t.restaurant_id
WHERE r.reservation_id IN (:p1, :p2, :p3, :p4, :p5)
   OR (rs.restaurant_id = :spice AND lower(r.period) BETWEEN '2026-10-30' AND '2026-11-01')
ORDER BY rs.name DESC, lower(r.period);

ROLLBACK;
\echo '(rolled back: database unchanged)'
