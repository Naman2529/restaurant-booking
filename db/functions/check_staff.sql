CREATE OR REPLACE FUNCTION check_staff(
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
        RAISE EXCEPTION 'staff % does not exist', p_staff_id;
    END IF;

    IF v_restaurant_id <> p_restaurant_id THEN
        RAISE EXCEPTION 'staff % does not work at this restaurant', p_staff_id;
    END IF;

    IF NOT v_role = ANY (p_roles) THEN
        RAISE EXCEPTION 'only a % can do this', array_to_string(p_roles, ' or ');
    END IF;
END;
$$;
