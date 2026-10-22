-- One restaurant's reservations for one day, for the staff list (find a
-- booking to seat or reassign). The restaurant comes from the staff token,
-- so staff only ever see their own. Table numbers only, never ids.
CREATE OR REPLACE FUNCTION staff.day_reservations(p_restaurant_id bigint, p_date date)
RETURNS TABLE (
    reservation_id bigint,
    table_number   int,
    capacity       int,
    party_size     int,
    customer_name  text,
    customer_phone text,
    starts_at      timestamp,
    ends_at        timestamp,
    status         text
)
LANGUAGE sql
STABLE
AS $$
    SELECT r.reservation_id, t.table_number, t.capacity, r.party_size,
           u.full_name, u.phone, lower(r.period), upper(r.period), r.status
    FROM reservation r
    JOIN dining_table t ON t.table_id = r.table_id
    JOIN app_user u     ON u.user_id = r.user_id
    WHERE t.restaurant_id = p_restaurant_id
      AND lower(r.period)::date = p_date
    ORDER BY lower(r.period), t.table_number;
$$;
