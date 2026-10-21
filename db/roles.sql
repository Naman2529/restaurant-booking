-- The Go app logs in as booking_app, not postgres.
-- It can call the routines in customer, staff and auth and read tables,
-- but it cannot INSERT, UPDATE or DELETE anything directly.
-- Every write goes through a procedure, so every rule is enforced.
--
-- Needs APP_DB_PASSWORD in the environment (load .env first).
-- Safe to re-run: reset.sql drops the schemas, so the grants are redone each time.

\getenv app_password APP_DB_PASSWORD
\if :{?app_password}
\else
    DO $$ BEGIN RAISE EXCEPTION 'APP_DB_PASSWORD is not set. Load .env first.'; END $$;
\endif

SELECT NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'booking_app') AS need_role \gset
\if :need_role
    CREATE ROLE booking_app LOGIN;
\endif
ALTER ROLE booking_app PASSWORD :'app_password';

-- Routines in customer, staff and auth run as their owner (postgres), so
-- they can write to the tables even though booking_app can't.
-- search_path is pinned so a caller can't swap in a fake table or function.
DO $$
DECLARE
    r regprocedure;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname IN ('customer', 'staff', 'auth')
    LOOP
        EXECUTE format('ALTER ROUTINE %s SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp', r);
    END LOOP;
END
$$;

-- By default every role can execute every function. Take that away,
-- then give it back to booking_app only.
REVOKE ALL ON ALL ROUTINES IN SCHEMA customer, staff, auth, util FROM PUBLIC;

GRANT USAGE   ON SCHEMA customer, staff, auth TO booking_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA customer, staff, auth TO booking_app;

-- Reads only. Needed for login and for listing restaurants / reservations.
GRANT SELECT ON ALL TABLES IN SCHEMA public TO booking_app;
