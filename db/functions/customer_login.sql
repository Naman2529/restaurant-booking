-- Returns the account for an email (no rows if unknown). The app checks the
-- password against password_hash with bcrypt in Go, so the slow hashing
-- runs on the app server, not the database.
-- Unverified users can log in; book_table is what stops them booking.
CREATE OR REPLACE FUNCTION customer.login_info(p_email citext)
RETURNS TABLE (user_id bigint, full_name text, email_verified boolean, password_hash text)
LANGUAGE sql
STABLE
AS $$
    SELECT u.user_id, u.full_name, u.email_verified_at IS NOT NULL, u.password_hash
    FROM app_user u
    WHERE u.email = p_email;
$$;
