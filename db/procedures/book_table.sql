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
    v_verified timestamptz;
    v_table_id bigint;
BEGIN
    IF p_start <= util.ist_now() THEN
        RAISE EXCEPTION 'start time % is in the past', p_start USING ERRCODE = 'RB422';
    END IF;

    -- Same rules as the reservation CHECKs, raised here first so the
    -- customer gets a clear message instead of a raw constraint error.
    IF p_party_size IS NULL OR p_party_size NOT BETWEEN 1 AND 20 THEN
        RAISE EXCEPTION 'party size must be 1 to 20' USING ERRCODE = 'RB422';
    END IF;

    IF date_part('minute', p_start) NOT IN (0, 30)
       OR date_part('second', p_start) <> 0
       OR p_start::time NOT BETWEEN '07:00' AND '21:00' THEN
        RAISE EXCEPTION 'start must be on a :00 or :30 slot from 07:00 to 21:00' USING ERRCODE = 'RB422';
    END IF;

    PERFORM 1 FROM restaurant WHERE restaurant_id = p_restaurant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'restaurant not found' USING ERRCODE = 'RB404';
    END IF;

    SELECT email_verified_at INTO v_verified
    FROM app_user
    WHERE user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'user account not found' USING ERRCODE = 'RB404';
    END IF;

    IF v_verified IS NULL THEN
        RAISE EXCEPTION 'verify your email before booking' USING ERRCODE = 'RB403';
    END IF;

    FOR v_table_id IN
        SELECT a.table_id
        FROM customer.available_tables(p_restaurant_id, p_start, p_party_size) a
    LOOP
        BEGIN
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
