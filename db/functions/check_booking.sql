-- The checks every booking makes before it touches a table. Shared by
-- book_table (the database picks the table) and book_specific_table (the
-- customer picks it), so both refuse the same requests with the same message.
CREATE OR REPLACE FUNCTION util.check_booking(
    p_user_id       bigint,
    p_restaurant_id bigint,
    p_start         timestamp,
    p_party_size    int
)
RETURNS void
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_verified timestamptz;
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
END;
$$;
