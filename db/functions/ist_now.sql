CREATE OR REPLACE FUNCTION util.ist_now()
RETURNS timestamp
LANGUAGE sql
STABLE
AS $$
    SELECT now() AT TIME ZONE 'Asia/Kolkata';
$$;
