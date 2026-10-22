-- A customer's own reservations, newest first. Shows the table number
-- (never the id) and whether the Cancel button should be enabled, using
-- the same can_cancel rule that cancel_reservation enforces.
CREATE OR REPLACE FUNCTION customer.my_reservations(p_user_id bigint)
RETURNS TABLE (
    reservation_id  bigint,
    restaurant_id   bigint,
    restaurant_name text,
    table_number    int,
    party_size      int,
    starts_at       timestamp,
    ends_at         timestamp,
    status          text,
    can_cancel      boolean
)
LANGUAGE sql
STABLE
AS $$
    SELECT r.reservation_id, rs.restaurant_id, rs.name, t.table_number, r.party_size,
           lower(r.period), upper(r.period), r.status,
           customer.can_cancel(r.reservation_id, p_user_id)
    FROM reservation r
    JOIN dining_table t ON t.table_id = r.table_id
    JOIN restaurant rs  ON rs.restaurant_id = t.restaurant_id
    WHERE r.user_id = p_user_id
    ORDER BY lower(r.period) DESC;
$$;
