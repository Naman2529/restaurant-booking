CREATE OR REPLACE PROCEDURE extend_reservation(
    p_reservation_id bigint,
    p_staff_id       bigint,
    p_extra          interval
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status        text;
    v_period        tsrange;
    v_restaurant_id bigint;
BEGIN
    IF p_extra <= interval '0' THEN
        RAISE EXCEPTION 'extension must be positive, got %', p_extra;
    END IF;

    SELECT r.status, r.period, t.restaurant_id
    INTO v_status, v_period, v_restaurant_id
    FROM reservation r
    JOIN dining_table t ON t.table_id = r.table_id
    WHERE r.reservation_id = p_reservation_id
    FOR UPDATE OF r;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'reservation % does not exist', p_reservation_id;
    END IF;

    PERFORM check_staff(p_staff_id, v_restaurant_id, ARRAY['receptionist', 'waiter']);

    IF v_status <> 'seated' THEN
        RAISE EXCEPTION 'reservation % is % and cannot be extended', p_reservation_id, v_status;
    END IF;

    BEGIN
        UPDATE reservation
        SET period = tsrange(lower(v_period), upper(v_period) + p_extra)
        WHERE reservation_id = p_reservation_id;
    EXCEPTION
        WHEN exclusion_violation THEN
            RAISE EXCEPTION 'cannot extend reservation %: the next booking on this table conflicts', p_reservation_id;
        WHEN check_violation THEN
            RAISE EXCEPTION 'cannot extend reservation %: it would end after 23:00', p_reservation_id;
    END;
END;
$$;
