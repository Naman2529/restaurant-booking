CREATE OR REPLACE PROCEDURE staff.reassign_table(
    p_reservation_id bigint,
    p_staff_id       bigint,
    p_new_table_id   bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status         text;
    v_party_size     int;
    v_old_table_id   bigint;
    v_restaurant_id  bigint;
    v_new_restaurant bigint;
    v_new_capacity   int;
    v_new_number     int;
BEGIN
    SELECT r.status, r.party_size, r.table_id, t.restaurant_id
    INTO v_status, v_party_size, v_old_table_id, v_restaurant_id
    FROM reservation r
    JOIN dining_table t ON t.table_id = r.table_id
    WHERE r.reservation_id = p_reservation_id
    FOR UPDATE OF r;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'reservation not found' USING ERRCODE = 'RB404';
    END IF;

    PERFORM util.check_staff(p_staff_id, v_restaurant_id, ARRAY['receptionist']);

    IF v_status <> 'booked' THEN
        RAISE EXCEPTION 'reservation % is % and cannot be reassigned', p_reservation_id, v_status USING ERRCODE = 'RB409';
    END IF;

    SELECT restaurant_id, capacity, table_number
    INTO v_new_restaurant, v_new_capacity, v_new_number
    FROM dining_table
    WHERE table_id = p_new_table_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'table not found' USING ERRCODE = 'RB404';
    END IF;

    IF v_new_restaurant <> v_restaurant_id THEN
        -- Another restaurant's table looks exactly like a missing one.
        RAISE EXCEPTION 'table not found' USING ERRCODE = 'RB404';
    END IF;

    IF p_new_table_id = v_old_table_id THEN
        RAISE EXCEPTION 'reservation % is already on table %', p_reservation_id, v_new_number USING ERRCODE = 'RB422';
    END IF;

    IF NOT v_new_capacity = ANY (util.allowed_capacities(v_party_size)) THEN
        RAISE EXCEPTION 'table % (capacity %) is not allowed for a party of %',
            v_new_number, v_new_capacity, v_party_size USING ERRCODE = 'RB422';
    END IF;

    BEGIN
        UPDATE reservation
        SET table_id = p_new_table_id
        WHERE reservation_id = p_reservation_id;
    EXCEPTION
        WHEN exclusion_violation THEN
            RAISE EXCEPTION 'cannot reassign reservation %: table % is booked at that time',
                p_reservation_id, v_new_number USING ERRCODE = 'RB409';
    END;
END;
$$;
