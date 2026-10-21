CREATE OR REPLACE PROCEDURE customer.resend_verification(
    p_email citext,
    INOUT p_verify_token text DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_token text := encode(gen_random_bytes(32), 'hex');
BEGIN
    -- A new token replaces the old one, so any earlier link stops working.
    UPDATE app_user
    SET verify_token_hash       = encode(sha256(convert_to(v_token, 'UTF8')), 'hex'),
        verify_token_expires_at = now() + interval '24 hours'
    WHERE email = p_email
      AND email_verified_at IS NULL;

    -- Unknown or already-verified email: no error, just no token. The route
    -- answers the same either way, so it can't reveal which emails exist.
    IF FOUND THEN
        p_verify_token := v_token;
    ELSE
        p_verify_token := NULL;
    END IF;
END;
$$;
