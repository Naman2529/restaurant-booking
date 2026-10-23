-- Test 07: the booking_app role (what the Go server logs in as).
--   psql -f db/tests/07_roles.sql
-- SET ROLE switches this session to booking_app, so no app password is needed.
-- booking_app may call routines in customer / staff / auth and read tables,
-- but every direct write is refused: every rule has to go through a procedure.

\echo
\echo '################################################################'
\echo '##  TEST 07 - ROLES AND PERMISSIONS (booking_app)'
\echo '################################################################'
\ir _setup.sql

\echo
\echo '=== T7.1  Packages (schemas) and their routines  (EXPECT: customer / staff / auth are SECURITY DEFINER with a pinned search_path; util is not exposed) ==='
SELECT n.nspname AS schema,
       count(*) AS routines,
       bool_and(p.prosecdef) AS all_security_definer,
       min(array_to_string(p.proconfig, ',')) AS pinned_setting,
       has_schema_privilege('booking_app', n.nspname, 'USAGE') AS app_can_use_schema
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('util', 'customer', 'staff', 'auth')
GROUP BY n.nspname
ORDER BY n.nspname;

\echo
\echo '=== T7.2  Table privileges for booking_app  (EXPECT: SELECT only on every table, no INSERT / UPDATE / DELETE) ==='
SELECT c.relname AS table_name,
       has_table_privilege('booking_app', c.oid, 'SELECT') AS can_select,
       has_table_privilege('booking_app', c.oid, 'INSERT') AS can_insert,
       has_table_privilege('booking_app', c.oid, 'UPDATE') AS can_update,
       has_table_privilege('booking_app', c.oid, 'DELETE') AS can_delete
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
ORDER BY c.relname;

\echo
\echo '=== Switching to booking_app ==='
SET ROLE booking_app;
SELECT current_user;
\set VERBOSITY verbose

\echo
\echo '=== T7.3  Book through the procedure  (EXPECT: works, the procedure runs as its owner) ==='
CALL customer.book_table(:aarav, :spice, '2026-11-12 19:00', 2, NULL) \gset
SELECT reservation_id, party_size, period, status FROM reservation WHERE reservation_id = :p_reservation_id;

\echo
\echo '=== T7.4  Read through a function  (EXPECT: works) ==='
SELECT * FROM customer.restaurants();

\echo
\echo '=== T7.5  Direct INSERT into reservation, skipping book_table  (EXPECT: 42501 permission denied for table reservation) ==='
INSERT INTO reservation (user_id, table_id, party_size, period)
VALUES (:aarav, pg_temp.tid('Spice Route', 2), 2, '[2026-11-12 19:00, 2026-11-12 21:00)');

\echo
\echo '=== T7.6  Direct UPDATE to "complete" a booking without staff  (EXPECT: 42501 permission denied for table reservation) ==='
UPDATE reservation SET status = 'completed' WHERE reservation_id = :p_reservation_id;

\echo
\echo '=== T7.7  Direct DELETE from the logout list (un-revoke a token)  (EXPECT: 42501 permission denied for table revoked_token) ==='
DELETE FROM revoked_token;

\echo
\echo '=== T7.8  Make yourself verified without the email link  (EXPECT: 42501 permission denied for table app_user) ==='
UPDATE app_user SET email_verified_at = now() WHERE email = 'meera@example.com';

\echo
\echo '=== T7.9  Call an internal helper in util directly  (EXPECT: 42501 permission denied for schema util) ==='
SELECT util.allowed_capacities(2);

\echo
\echo '=== T7.10 Create a table in public  (EXPECT: 42501 permission denied for schema public) ==='
CREATE TABLE public.sneaky (id int);

\echo
\echo '=== T7.11 search_path hijack: a temp table called "reservation" shadows the real one  (EXPECT: plain SELECT sees the fake row; my_reservations still reads the real table, its search_path is pinned) ==='
CREATE TEMP TABLE reservation (reservation_id bigint, status text);
INSERT INTO reservation VALUES (-1, 'FAKE');
SELECT 'plain SELECT' AS via, reservation_id, status FROM reservation;
SELECT 'customer.my_reservations' AS via, reservation_id, status FROM customer.my_reservations(:aarav) LIMIT 3;

\echo
\echo '=== Back to postgres ==='
RESET ROLE;
SELECT current_user;

ROLLBACK;
\echo '(rolled back: database unchanged)'
