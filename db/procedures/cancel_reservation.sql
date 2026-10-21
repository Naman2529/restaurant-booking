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
        RAISE EXCEPTION 'reservation not found' USING ERRCODE = 'RB404';
    END IF;

    IF v_owner <> p_user_id THEN
        -- Same message and code as "doesn't exist", so nobody can probe
        -- which reservation ids belong to other people.
        RAISE EXCEPTION 'reservation not found' USING ERRCODE = 'RB404';
    END IF;

    IF v_status <> 'booked' THEN
        RAISE EXCEPTION 'reservation % is % and cannot be cancelled', p_reservation_id, v_status USING ERRCODE = 'RB409';
    END IF;

    IF NOT customer.can_cancel(p_reservation_id, p_user_id) THEN
        RAISE EXCEPTION 'reservation % starts in less than 15 minutes and cannot be cancelled', p_reservation_id USING ERRCODE = 'RB409';
    END IF;

    UPDATE reservation
    SET status = 'cancelled',
        cancelled_at = now()
    WHERE reservation_id = p_reservation_id;
END;
$$;
