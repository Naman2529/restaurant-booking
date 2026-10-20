CREATE OR REPLACE PROCEDURE book_table(
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
    IF p_start <= ist_now() THEN
        RAISE EXCEPTION 'start time % is in the past', p_start;
    END IF;

    SELECT email_verified_at INTO v_verified
    FROM app_user
    WHERE user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'user % does not exist', p_user_id;
    END IF;

    IF v_verified IS NULL THEN
        RAISE EXCEPTION 'user % has not verified their email', p_user_id;
    END IF;

    FOR v_table_id IN
        SELECT a.table_id
        FROM available_tables(p_restaurant_id, p_start, p_party_size) a
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

    RAISE EXCEPTION 'no table available for % people at %', p_party_size, p_start;
END;
$$;
