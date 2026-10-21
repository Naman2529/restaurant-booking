-- Logout. Puts the token's id on the revoked list until it would have
-- expired anyway, and clears out rows that no longer matter.
CREATE OR REPLACE PROCEDURE auth.revoke_token(
    p_jti        text,
    p_expires_at timestamptz
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF coalesce(p_jti, '') = '' THEN
        RAISE EXCEPTION 'token id is required' USING ERRCODE = 'RB422';
    END IF;

    DELETE FROM revoked_token WHERE expires_at < now();

    -- Logging out twice is fine.
    INSERT INTO revoked_token (jti, expires_at)
    VALUES (p_jti, p_expires_at)
    ON CONFLICT (jti) DO NOTHING;
END;
$$;
