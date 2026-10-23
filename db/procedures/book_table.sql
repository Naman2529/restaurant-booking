CREATE OR REPLACE PROCEDURE customer.book_table(
    p_user_id        bigint,
    p_restaurant_id  bigint,
    p_start          timestamp,
    p_party_size     int,
    INOUT p_reservation_id bigint DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_table_id bigint;
BEGIN
    -- Past start, party size, slot, restaurant, user, verified email.
    PERFORM util.check_booking(p_user_id, p_restaurant_id, p_start, p_party_size);

    FOR v_table_id IN
        SELECT a.table_id
        FROM customer.available_tables(p_restaurant_id, p_start, p_party_size) a
    LOOP
        BEGIN
            -- Bookings for the same table take turns. Without this, two
            -- sessions inserting onto one table at the same instant can each
            -- wait on the other's uncommitted row inside the exclusion check,
            -- and Postgres aborts one with a deadlock (40P01) instead of an
            -- exclusion_violation, so it never tries the next table. Found by
            -- the Go concurrency test (24 Oct). With the lock, the second
            -- session waits, then sees the first one's committed row and
            -- moves on. NO KEY UPDATE doesn't block the foreign-key check on
            -- the insert. A failed attempt rolls back this block and releases
            -- the lock, so a session only ever holds one table: no cycles.
            PERFORM 1 FROM dining_table WHERE table_id = v_table_id FOR NO KEY UPDATE;

            INSERT INTO reservation (user_id, table_id, party_size, period)
            VALUES (p_user_id, v_table_id, p_party_size,
                    tsrange(p_start, p_start + interval '2 hours'))
            RETURNING reservation_id INTO p_reservation_id;
            RETURN;
        EXCEPTION
            WHEN exclusion_violation THEN
                NULL;
        END;
    END LOOP;

    RAISE EXCEPTION 'no table available for % people at %', p_party_size, p_start USING ERRCODE = 'RB409';
END;
$$;
