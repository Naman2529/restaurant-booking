CREATE OR REPLACE PROCEDURE customer.verify_email(
    p_token text,
    INOUT p_user_id bigint DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Clearing the hash makes the link single-use.
    UPDATE app_user
    SET email_verified_at       = now(),
        verify_token_hash       = NULL,
        verify_token_expires_at = NULL
    WHERE verify_token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
      AND verify_token_expires_at > now()
    RETURNING user_id INTO p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'verification link is invalid, expired or already used' USING ERRCODE = 'RB404';
    END IF;
END;
$$;
