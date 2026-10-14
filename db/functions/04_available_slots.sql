CREATE OR REPLACE FUNCTION available_slots(
    p_restaurant_id bigint,
    p_date          date,
    p_party_size    int
)
RETURNS TABLE (slot_start timestamp, free_tables int)
LANGUAGE sql
STABLE
AS $$
    SELECT s.slot_start, count(*)::int
    FROM generate_series(
             p_date + time '07:00',
             p_date + time '21:00',
             interval '30 minutes'
         ) AS s(slot_start)
    CROSS JOIN LATERAL available_tables(p_restaurant_id, s.slot_start, p_party_size) AS a
    WHERE s.slot_start > ist_now()
    GROUP BY s.slot_start
    ORDER BY s.slot_start;
$$;
