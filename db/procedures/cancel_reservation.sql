CREATE OR REPLACE PROCEDURE customer.cancel_reservation(
    p_reservation_id bigint,
    p_user_id        bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_owner  bigint;
    v_status text;
BEGIN
    SELECT user_id, status INTO v_owner, v_status
    FROM reservation
    WHERE reservation_id = p_reservation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'reservation % does not exist', p_reservation_id;
    END IF;

    IF v_owner <> p_user_id THEN
        RAISE EXCEPTION 'reservation % does not belong to user %', p_reservation_id, p_user_id;
    END IF;

    IF v_status <> 'booked' THEN
        RAISE EXCEPTION 'reservation % is % and cannot be cancelled', p_reservation_id, v_status;
    END IF;

    IF NOT customer.can_cancel(p_reservation_id, p_user_id) THEN
        RAISE EXCEPTION 'reservation % starts in less than 15 minutes and cannot be cancelled', p_reservation_id;
    END IF;

    UPDATE reservation
    SET status = 'cancelled',
        cancelled_at = now()
    WHERE reservation_id = p_reservation_id;
END;
$$;
