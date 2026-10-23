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
      AND util.table_free(t.table_id, p_start)
    ORDER BY t.capacity, t.table_number;
$$;
