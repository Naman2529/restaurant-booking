-- The customer picks the table on the floor plan. Same checks as book_table,
-- but only that table is tried, and only if its size is allowed for the
-- party (smallest that fits, or one size up), so the floor plan can't be
-- used to grab a 10-seater for two.
CREATE OR REPLACE PROCEDURE customer.book_specific_table(
    p_user_id        bigint,
    p_restaurant_id  bigint,
    p_start          timestamp,
    p_party_size     int,
    p_table_number   int,
    INOUT p_reservation_id bigint DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_table_id bigint;
    v_capacity int;
BEGIN
    PERFORM util.check_booking(p_user_id, p_restaurant_id, p_start, p_party_size);

    -- Looked up inside the chosen restaurant, so another restaurant's table
    -- can't be named. The row lock makes bookings for this table take turns,
    -- for the same deadlock reason as in book_table.
    SELECT table_id, capacity INTO v_table_id, v_capacity
    FROM dining_table
    WHERE restaurant_id = p_restaurant_id
      AND table_number = p_table_number
    FOR NO KEY UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'table % not found', p_table_number USING ERRCODE = 'RB404';
    END IF;

    IF NOT v_capacity = ANY (util.allowed_capacities(p_party_size)) THEN
        RAISE EXCEPTION 'table % (capacity %) is not allowed for a party of %',
            p_table_number, v_capacity, p_party_size USING ERRCODE = 'RB422';
    END IF;

    BEGIN
        INSERT INTO reservation (user_id, table_id, party_size, period)
        VALUES (p_user_id, v_table_id, p_party_size,
                tsrange(p_start, p_start + interval '2 hours'))
        RETURNING reservation_id INTO p_reservation_id;
    EXCEPTION
        WHEN exclusion_violation THEN
            RAISE EXCEPTION 'table % was just booked for that time, please pick another', p_table_number
                USING ERRCODE = 'RB409';
    END;
END;
$$;
