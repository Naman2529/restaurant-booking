CREATE OR REPLACE PROCEDURE complete_reservation(
    p_reservation_id bigint,
    p_staff_id       bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status        text;
    v_restaurant_id bigint;
BEGIN
    SELECT r.status, t.restaurant_id
    INTO v_status, v_restaurant_id
    FROM reservation r
    JOIN dining_table t ON t.table_id = r.table_id
    WHERE r.reservation_id = p_reservation_id
    FOR UPDATE OF r;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'reservation % does not exist', p_reservation_id;
    END IF;

    PERFORM check_staff(p_staff_id, v_restaurant_id, ARRAY['receptionist', 'waiter']);

    IF v_status <> 'seated' THEN
        RAISE EXCEPTION 'reservation % is % and cannot be completed', p_reservation_id, v_status;
    END IF;

    UPDATE reservation
    SET status = 'completed'
    WHERE reservation_id = p_reservation_id;
END;
$$;
