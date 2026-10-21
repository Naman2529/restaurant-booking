CREATE OR REPLACE FUNCTION customer.can_cancel(
    p_reservation_id bigint,
    p_user_id        bigint
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM reservation r
        WHERE r.reservation_id = p_reservation_id
          AND r.user_id = p_user_id
          AND r.status = 'booked'
          AND util.ist_now() <= lower(r.period) - interval '15 minutes'
    );
$$;
