-- Runs every database test file in order. Each file rolls itself back,
-- so the database is unchanged afterwards.
--   psql -f db/tests/run_all.sql      (or .\run_tests.ps1 from the project root)

\echo '================================================================'
\echo '   RESTAURANT BOOKING - DATABASE TEST SUITE'
\echo '================================================================'
SELECT current_database() AS database, current_user AS run_as, version() AS server \gx

\ir 01_constraints.sql
\ir 02_functions.sql
\ir 03_customer_procedures.sql
\ir 04_staff_procedures.sql
\ir 05_triggers.sql
\ir 06_cursor.sql
\ir 07_roles.sql

\echo
\echo '================================================================'
\echo '   DATABASE TESTS FINISHED (all changes rolled back)'
\echo '================================================================'
