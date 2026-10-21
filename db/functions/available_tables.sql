CREATE OR REPLACE FUNCTION customer.available_tables(
    p_restaurant_id bigint,
    p_start         timestamp,
    p_party_size    int
)
RETURNS TABLE (table_id bigint, table_number int, capacity int)
LANGUAGE sql
STABLE
AS $$
    SELECT t.table_id, t.table_number, t.capacity
    FROM dining_table t
    WHERE t.restaurant_id = p_restaurant_id
      AND t.capacity = ANY (util.allowed_capacities(p_party_size))
      AND NOT EXISTS (
          SELECT 1
          FROM reservation r
          WHERE r.table_id = t.table_id
            AND r.status IN ('booked', 'seated')
            AND tsrange(lower(r.period), upper(r.period) + interval '30 minutes')
             && tsrange(p_start, p_start + interval '2 hours 30 minutes')
      )
    ORDER BY t.capacity, t.table_number;
$$;
