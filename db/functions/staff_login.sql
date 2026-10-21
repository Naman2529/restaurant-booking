-- Returns the staff account for an email (no rows if unknown). The app
-- checks the password with bcrypt in Go. restaurant_id and role go into the
-- staff token, so every staff route knows which restaurant the caller
-- belongs to without trusting the client.
CREATE OR REPLACE FUNCTION staff.login_info(p_email citext)
RETURNS TABLE (staff_id bigint, restaurant_id bigint, full_name text, role text, password_hash text)
LANGUAGE sql
STABLE
AS $$
    SELECT s.staff_id, s.restaurant_id, s.full_name, s.role, s.password_hash
    FROM restaurant_staff s
    WHERE s.email = p_email;
$$;
