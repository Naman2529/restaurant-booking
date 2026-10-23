-- True when nothing active is booked on the table over a 2-hour sitting
-- starting at p_start, counting the 30-minute buffer on both sittings.
-- The same test the no_double_booking constraint makes, asked ahead of time.
-- Used by available_tables (the DB picks) and table_availability (the
-- customer's floor plan), so both always agree.
CREATE OR REPLACE FUNCTION util.table_free(p_table_id bigint, p_start timestamp)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT NOT EXISTS (
        SELECT 1
        FROM reservation r
        WHERE r.table_id = p_table_id
          AND r.status IN ('booked', 'seated')
          AND tsrange(lower(r.period), upper(r.period) + interval '30 minutes')
           && tsrange(p_start, p_start + interval '2 hours 30 minutes')
    );
$$;
