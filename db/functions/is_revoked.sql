-- Checked by the app on every logged-in request (primary key lookup).
CREATE OR REPLACE FUNCTION auth.is_revoked(p_jti text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT EXISTS (SELECT 1 FROM revoked_token WHERE jti = p_jti);
$$;
