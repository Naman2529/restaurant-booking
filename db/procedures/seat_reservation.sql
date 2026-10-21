CREATE OR REPLACE PROCEDURE staff.seat_reservation(
    p_reservation_id bigint,
    p_staff_id       bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status        text;
    v_period        tsrange;
    v_restaurant_id bigint;
BEGIN
    SELECT r.status, r.period, t.restaurant_id
    INTO v_status, v_period, v_restaurant_id
    FROM reservation r
    JOIN dining_table t ON t.table_id = r.table_id
    WHERE r.reservation_id = p_reservation_id
    FOR UPDATE OF r;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'reservation % does not exist', p_reservation_id;
    END IF;

    PERFORM util.check_staff(p_staff_id, v_restaurant_id, ARRAY['receptionist']);

    IF v_status <> 'booked' THEN
        RAISE EXCEPTION 'reservation % is % and cannot be seated', p_reservation_id, v_status;
    END IF;

    IF util.ist_now() < lower(v_period) - interval '30 minutes' THEN
        RAISE EXCEPTION 'reservation % starts at %, too early to seat', p_reservation_id, lower(v_period);
    END IF;

    IF util.ist_now() >= upper(v_period) THEN
        RAISE EXCEPTION 'reservation % has already ended', p_reservation_id;
    END IF;

    UPDATE reservation
    SET status = 'seated',
        seated_at = now()
    WHERE reservation_id = p_reservation_id;
END;
$$;
