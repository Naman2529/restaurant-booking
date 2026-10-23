-- Who is logged in, for GET /auth/customer/me. The token only carries the
-- id, so the front end asks here for the name and whether the email is
-- verified (it changes after the link is clicked).
CREATE OR REPLACE FUNCTION customer.profile(p_user_id bigint)
RETURNS TABLE (user_id bigint, full_name text, email citext, phone text, email_verified boolean)
LANGUAGE sql
STABLE
AS $$
    SELECT u.user_id, u.full_name, u.email, u.phone, u.email_verified_at IS NOT NULL
    FROM app_user u
    WHERE u.user_id = p_user_id;
$$;
