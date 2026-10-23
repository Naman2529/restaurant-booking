-- Every table of a restaurant for one start time and party size, for the
-- customer's floor plan. fits_party: its size is allowed for this party
-- (smallest that fits, or one size up). is_free: nothing active is booked
-- over that sitting, and the start hasn't passed. Only tables with both are
-- bookable. Nothing about other customers' bookings is returned.
CREATE OR REPLACE FUNCTION customer.table_availability(
    p_restaurant_id bigint,
    p_start         timestamp,
    p_party_size    int
)
RETURNS TABLE (table_number int, capacity int, fits_party boolean, is_free boolean)
LANGUAGE sql
STABLE
AS $$
    SELECT t.table_number,
           t.capacity,
           t.capacity = ANY (util.allowed_capacities(p_party_size)),
           p_start > util.ist_now() AND util.table_free(t.table_id, p_start)
    FROM dining_table t
    WHERE t.restaurant_id = p_restaurant_id
    ORDER BY t.table_number;
$$;
