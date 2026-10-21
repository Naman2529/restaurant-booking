DROP SCHEMA IF EXISTS staff    CASCADE;
DROP SCHEMA IF EXISTS customer CASCADE;
DROP SCHEMA IF EXISTS util     CASCADE;

CREATE SCHEMA util;
CREATE SCHEMA customer;
CREATE SCHEMA staff;

COMMENT ON SCHEMA util     IS 'Internal helpers and trigger functions. Not exposed to the app.';
COMMENT ON SCHEMA customer IS 'What a customer can do: find slots and tables, book, cancel.';
COMMENT ON SCHEMA staff    IS 'What restaurant staff can do: seat map, seat, complete, no-show, extend, reassign, no-show sweep.';
