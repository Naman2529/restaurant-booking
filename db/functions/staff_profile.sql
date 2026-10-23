-- Who is logged in, for GET /auth/staff/me: name, role and the restaurant's
-- name for the dashboard greeting.
CREATE OR REPLACE FUNCTION staff.profile(p_staff_id bigint)
RETURNS TABLE (staff_id bigint, full_name text, email citext, role text,
               restaurant_id bigint, restaurant_name text)
LANGUAGE sql
STABLE
AS $$
    SELECT s.staff_id, s.full_name, s.email, s.role, r.restaurant_id, r.name
    FROM restaurant_staff s
    JOIN restaurant r ON r.restaurant_id = s.restaurant_id
    WHERE s.staff_id = p_staff_id;
$$;
