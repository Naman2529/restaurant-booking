-- Test 04: staff procedures (seat, complete, no-show, extend, reassign) and role checks.
--   psql -f db/tests/04_staff_procedures.sql
-- Errors show their code (RBxxx). The last three digits are the HTTP status the API returns.

\echo
\echo '################################################################'
\echo '##  TEST 04 - STAFF PROCEDURES'
\echo '################################################################'
\ir _setup.sql
\set VERBOSITY verbose

\echo
\echo '=== Setup: Spice Route, today 10 Nov, now 19:20 ==='
\echo '    A  table 1   booked 19:30-21:30  party 2  (arrives in 10 min: can be seated)'
\echo '    B  table 2   booked 21:00-23:00  party 2  (100 min away: too early to seat)'
\echo '    C  table 5   booked 19:00-21:00  party 3  (started, nobody here: no-show)'
\echo '    D  table 6   seated 17:00-19:00  party 4  (sitting over: extend or free)'
\echo '    H  table 6   booked 20:00-22:00  party 4  (next booking on D''s table)'
\echo '    E  table 9   seated 18:30-20:30  party 5  (eating: will be completed)'
\echo '    I  table 10  seated 19:00-21:00  party 5  (for the 23:00 extend limit)'
\echo '    F  table 3   booked 20:00-22:00  party 2  (to be reassigned)'
\echo '    G  table 7   booked 17:00-19:00  party 3  (already ended, never seated)'
\set QUIET on
INSERT INTO reservation (user_id, table_id, party_size, period) VALUES
    (:aarav, pg_temp.tid('Spice Route', 1), 2, '[2026-11-10 19:30, 2026-11-10 21:30)') RETURNING reservation_id AS a \gset
INSERT INTO reservation (user_id, table_id, party_size, period) VALUES
    (:priya, pg_temp.tid('Spice Route', 2), 2, '[2026-11-10 21:00, 2026-11-10 23:00)') RETURNING reservation_id AS b \gset
INSERT INTO reservation (user_id, table_id, party_size, period) VALUES
    (:rohan, pg_temp.tid('Spice Route', 5), 3, '[2026-11-10 19:00, 2026-11-10 21:00)') RETURNING reservation_id AS c \gset
INSERT INTO reservation (user_id, table_id, party_size, period, status, seated_at) VALUES
    (:priya, pg_temp.tid('Spice Route', 6), 4, '[2026-11-10 17:00, 2026-11-10 19:00)', 'seated', now()) RETURNING reservation_id AS d \gset
INSERT INTO reservation (user_id, table_id, party_size, period) VALUES
    (:aarav, pg_temp.tid('Spice Route', 6), 4, '[2026-11-10 20:00, 2026-11-10 22:00)') RETURNING reservation_id AS h \gset
INSERT INTO reservation (user_id, table_id, party_size, period, status, seated_at) VALUES
    (:rohan, pg_temp.tid('Spice Route', 9), 5, '[2026-11-10 18:30, 2026-11-10 20:30)', 'seated', now()) RETURNING reservation_id AS e \gset
INSERT INTO reservation (user_id, table_id, party_size, period, status, seated_at) VALUES
    (:aarav, pg_temp.tid('Spice Route', 10), 5, '[2026-11-10 19:00, 2026-11-10 21:00)', 'seated', now()) RETURNING reservation_id AS i \gset
INSERT INTO reservation (user_id, table_id, party_size, period) VALUES
    (:aarav, pg_temp.tid('Spice Route', 3), 2, '[2026-11-10 20:00, 2026-11-10 22:00)') RETURNING reservation_id AS f \gset
INSERT INTO reservation (user_id, table_id, party_size, period) VALUES
    (:priya, pg_temp.tid('Spice Route', 7), 3, '[2026-11-10 17:00, 2026-11-10 19:00)') RETURNING reservation_id AS g \gset
\set QUIET off
SELECT reservation_id, table_number, party_size, starts_at, ends_at, status
FROM staff.day_reservations(:spice, '2026-11-10');

\echo
\echo '---------------- seat_reservation (receptionist only) ----------------'

\echo
\echo '=== T4.1  Waiter seats A  (EXPECT: RB403 only a receptionist can do this) ==='
CALL staff.seat_reservation(:a, :spice_wait);

\echo
\echo '=== T4.2  Receptionist seats B, 100 min early  (EXPECT: RB409 ... too early to seat) ==='
CALL staff.seat_reservation(:b, :spice_rec);

\echo
\echo '=== T4.3  Receptionist seats G, whose sitting already ended  (EXPECT: RB409 ... has already ended) ==='
CALL staff.seat_reservation(:g, :spice_rec);

\echo
\echo '=== T4.4  Coastal Kitchen receptionist seats A (a Spice Route booking)  (EXPECT: RB404 reservation not found) ==='
CALL staff.seat_reservation(:a, :coastal_rec);

\echo
\echo '=== T4.5  Reservation id that does not exist  (EXPECT: RB404 reservation not found) ==='
CALL staff.seat_reservation(999999, :spice_rec);

\echo
\echo '=== T4.6  Receptionist seats A, 10 min early  (EXPECT: status seated, seated_at set) ==='
CALL staff.seat_reservation(:a, :spice_rec);
SELECT reservation_id, status, seated_at IS NOT NULL AS seated_at_set FROM reservation WHERE reservation_id = :a;

\echo
\echo '=== T4.7  Seat A again  (EXPECT: RB409 ... is seated and cannot be seated) ==='
CALL staff.seat_reservation(:a, :spice_rec);

\echo
\echo '---------------- complete_reservation (both roles) ----------------'

\echo
\echo '=== T4.8  Waiter completes E (frees table 9)  (EXPECT: status completed) ==='
CALL staff.complete_reservation(:e, :spice_wait);
SELECT reservation_id, status FROM reservation WHERE reservation_id = :e;

\echo
\echo '=== T4.9  Complete B, which was never seated  (EXPECT: RB409 ... is booked and cannot be completed) ==='
CALL staff.complete_reservation(:b, :spice_wait);

\echo
\echo '=== T4.10 Coastal Kitchen receptionist completes D  (EXPECT: RB404 reservation not found) ==='
CALL staff.complete_reservation(:d, :coastal_rec);

\echo
\echo '---------------- mark_no_show (both roles) ----------------'

\echo
\echo '=== T4.11 Waiter marks B no-show before it starts  (EXPECT: RB409 ... too early to mark no-show) ==='
CALL staff.mark_no_show(:b, :spice_wait);

\echo
\echo '=== T4.12 Waiter marks C no-show (started 19:00, nobody came)  (EXPECT: status no_show) ==='
CALL staff.mark_no_show(:c, :spice_wait);
SELECT reservation_id, status FROM reservation WHERE reservation_id = :c;

\echo
\echo '=== T4.13 Mark C again  (EXPECT: RB409 ... is no_show and cannot be marked no-show) ==='
CALL staff.mark_no_show(:c, :spice_wait);

\echo
\echo '=== T4.14 Mark A no-show, but A is seated  (EXPECT: RB409 ... is seated and cannot be marked no-show) ==='
CALL staff.mark_no_show(:a, :spice_wait);

\echo
\echo '---------------- extend_reservation (both roles) ----------------'

\echo
\echo '=== T4.15 Waiter extends D by 30 min  (EXPECT: D now 17:00-19:30) ==='
CALL staff.extend_reservation(:d, :spice_wait, interval '30 minutes');
SELECT reservation_id, period FROM reservation WHERE reservation_id = :d;

\echo
\echo '=== T4.16 Extend D by 30 more: 20:00 + buffer hits H at 20:00 on the same table  (EXPECT: RB409 ... the next booking on this table conflicts) ==='
CALL staff.extend_reservation(:d, :spice_wait, interval '30 minutes');

\echo
\echo '=== T4.17 Extend by 0 and by -30 min  (EXPECT: RB422 extension must be positive, twice) ==='
CALL staff.extend_reservation(:d, :spice_wait, interval '0');
CALL staff.extend_reservation(:d, :spice_wait, interval '-30 minutes');

\echo
\echo '=== T4.18 Extend B, which is not seated  (EXPECT: RB409 ... is booked and cannot be extended) ==='
CALL staff.extend_reservation(:b, :spice_wait, interval '30 minutes');

\echo
\echo '=== T4.19 Extend I (ends 21:00) by 2 h 30 min  (EXPECT: RB422 ... it would end after 23:00) ==='
CALL staff.extend_reservation(:i, :spice_wait, interval '150 minutes');

\echo
\echo '=== T4.20 Extend I by exactly 2 h  (EXPECT: I now 19:00-23:00, closing time is allowed) ==='
CALL staff.extend_reservation(:i, :spice_wait, interval '120 minutes');
SELECT reservation_id, period FROM reservation WHERE reservation_id = :i;

\echo
\echo '=== T4.21 Coastal Kitchen receptionist extends D  (EXPECT: RB404 reservation not found) ==='
CALL staff.extend_reservation(:d, :coastal_rec, interval '30 minutes');

\echo
\echo '---------------- reassign_table (receptionist only, by table NUMBER) ----------------'

\echo
\echo '=== T4.22 Waiter moves F to table 4  (EXPECT: RB403 only a receptionist can do this) ==='
CALL staff.reassign_table(:f, :spice_wait, 4);

\echo
\echo '=== T4.23 Receptionist moves F from table 3 to table 4  (EXPECT: F now on table 4) ==='
CALL staff.reassign_table(:f, :spice_rec, 4);
SELECT r.reservation_id, t.table_number FROM reservation r JOIN dining_table t USING (table_id) WHERE r.reservation_id = :f;

\echo
\echo '=== T4.24 Move F to table 4 again  (EXPECT: RB422 ... is already on table 4) ==='
CALL staff.reassign_table(:f, :spice_rec, 4);

\echo
\echo '=== T4.25 Move F (party 2) to table 9, a 6-seater  (EXPECT: RB422 table 9 (capacity 6) is not allowed for a party of 2) ==='
CALL staff.reassign_table(:f, :spice_rec, 9);

\echo
\echo '=== T4.26 Move F to table 1, where A is seated until 21:30  (EXPECT: RB409 ... table 1 is booked at that time) ==='
CALL staff.reassign_table(:f, :spice_rec, 1);

\echo
\echo '=== T4.27 Move F to table 99  (EXPECT: RB404 table 99 not found) ==='
CALL staff.reassign_table(:f, :spice_rec, 99);

\echo
\echo '=== T4.28 Move A, who is already seated  (EXPECT: RB409 ... is seated and cannot be reassigned) ==='
CALL staff.reassign_table(:a, :spice_rec, 4);

\echo
\echo '=== T4.29 Coastal Kitchen receptionist moves F  (EXPECT: RB404 reservation not found) ==='
CALL staff.reassign_table(:f, :coastal_rec, 2);

\echo
\echo '=== T4.30 Seat map after all of the above  (EXPECT: red 1 (A), 6 (D, extended), 10 (I); everything else green) ==='
SELECT table_number, capacity, colour, reservation_id, period FROM staff.seat_map(:spice);

ROLLBACK;
\echo '(rolled back: database unchanged)'
