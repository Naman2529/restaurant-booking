-- Shared setup, included by every test file with \ir _setup.sql.
-- Opens the transaction that the test file rolls back at the end.

\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on
\set VERBOSITY default
\set SHOW_CONTEXT never
\pset footer off
\set QUIET on

BEGIN;

-- Pinned clock. Every rule that depends on "now" calls util.ist_now(), so
-- replacing it here makes every test give the same answer whenever it runs.
-- It is rolled back with everything else, so the real function comes back.
CREATE OR REPLACE FUNCTION util.ist_now()
RETURNS timestamp
LANGUAGE sql
STABLE
AS $$
    SELECT timestamp '2026-11-10 19:20';
$$;

-- table_id is not table_number, so tests name tables by restaurant + number.
CREATE FUNCTION pg_temp.tid(p_restaurant text, p_table_number int)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
    SELECT t.table_id
    FROM dining_table t
    JOIN restaurant r USING (restaurant_id)
    WHERE r.name = p_restaurant AND t.table_number = p_table_number;
$$;

SELECT user_id AS aarav FROM app_user WHERE email = 'aarav@example.com' \gset
SELECT user_id AS priya FROM app_user WHERE email = 'priya@example.com' \gset
SELECT user_id AS rohan FROM app_user WHERE email = 'rohan@example.com' \gset
SELECT user_id AS meera FROM app_user WHERE email = 'meera@example.com' \gset

SELECT restaurant_id AS spice   FROM restaurant WHERE name = 'Spice Route' \gset
SELECT restaurant_id AS coastal FROM restaurant WHERE name = 'Coastal Kitchen' \gset

SELECT staff_id AS spice_rec   FROM restaurant_staff WHERE email = 'reception@spiceroute.example.com' \gset
SELECT staff_id AS spice_wait  FROM restaurant_staff WHERE email = 'waiter@spiceroute.example.com' \gset
SELECT staff_id AS coastal_rec FROM restaurant_staff WHERE email = 'reception@coastalkitchen.example.com' \gset

\set QUIET off
\echo '(clock pinned: util.ist_now() = 2026-11-10 19:20 IST for this file; everything below is rolled back)'
