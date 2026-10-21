-- The app hashes the password with bcrypt (Go) and passes only the hash,
-- so the plain password never reaches the database.
CREATE OR REPLACE PROCEDURE customer.sign_up(
    p_email         text,
    p_full_name     text,
    p_phone         text,
    p_password_hash text,
    INOUT p_user_id      bigint DEFAULT NULL,
    INOUT p_verify_token text   DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_email IS NULL OR position('@' IN p_email) = 0 THEN
        RAISE EXCEPTION 'email % is not valid', p_email USING ERRCODE = 'RB422';
    END IF;

    IF coalesce(trim(p_full_name), '') = '' THEN
        RAISE EXCEPTION 'full name is required' USING ERRCODE = 'RB422';
    END IF;

    -- Safety net: a bcrypt hash is 60 characters starting with $2.
    -- Stops a buggy client from storing a plain password.
    IF p_password_hash IS NULL OR p_password_hash NOT LIKE '$2%' OR length(p_password_hash) <> 60 THEN
        RAISE EXCEPTION 'password hash is not a bcrypt hash' USING ERRCODE = 'RB422';
    END IF;

    -- The plain token goes back to the caller once (for the link).
    -- Only its hash is stored, so a leaked table can't verify anyone.
    p_verify_token := encode(gen_random_bytes(32), 'hex');

    BEGIN
        INSERT INTO app_user (email, full_name, phone, password_hash,
                              verify_token_hash, verify_token_expires_at)
        VALUES (p_email, trim(p_full_name), p_phone, p_password_hash,
                encode(sha256(convert_to(p_verify_token, 'UTF8')), 'hex'),
                now() + interval '24 hours')
        RETURNING user_id INTO p_user_id;
    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION 'email % is already registered', p_email USING ERRCODE = 'RB409';
    END;
END;
$$;
