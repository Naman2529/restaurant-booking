\set ON_ERROR_STOP on

\ir schema/packages.sql
\ir schema/schema.sql
\ir seed/seed.sql

-- util
\ir functions/ist_now.sql
\ir functions/check_staff.sql
\ir functions/allowed_capacities.sql

-- customer
\ir functions/available_tables.sql
\ir functions/available_slots.sql
\ir functions/can_cancel.sql
\ir procedures/book_table.sql
\ir procedures/cancel_reservation.sql

-- staff
\ir functions/seat_map.sql
\ir procedures/seat_reservation.sql
\ir procedures/complete_reservation.sql
\ir procedures/mark_no_show.sql
\ir procedures/extend_reservation.sql
\ir procedures/reassign_table.sql
\ir cursors/no_show_sweep.sql

-- triggers
\ir triggers/party_fits_table.sql
\ir triggers/status_transition.sql
\ir triggers/status_timestamps.sql
