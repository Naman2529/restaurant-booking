CREATE OR REPLACE FUNCTION util.check_staff(
    p_staff_id      bigint,
    p_restaurant_id bigint,
    p_roles         text[]
)
RETURNS void
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_role          text;
    v_restaurant_id bigint;
BEGIN
    SELECT role, restaurant_id INTO v_role, v_restaurant_id
    FROM restaurant_staff
    WHERE staff_id = p_staff_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'staff account not found' USING ERRCODE = 'RB403';
    END IF;

    -- Every caller gets here after looking up a reservation, so a mismatch
    -- means "that reservation is at another restaurant". Answer exactly like
    -- a missing reservation, so staff can't probe other restaurants' ids.
    IF v_restaurant_id <> p_restaurant_id THEN
        RAISE EXCEPTION 'reservation not found' USING ERRCODE = 'RB404';
    END IF;

    IF NOT v_role = ANY (p_roles) THEN
        RAISE EXCEPTION 'only a % can do this', array_to_string(p_roles, ' or ') USING ERRCODE = 'RB403';
    END IF;
END;
$$;
