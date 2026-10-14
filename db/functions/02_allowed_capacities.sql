CREATE OR REPLACE FUNCTION allowed_capacities(p_party_size int)
RETURNS int[]
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_party_size BETWEEN 1  AND 2  THEN ARRAY[2, 4]
        WHEN p_party_size BETWEEN 3  AND 4  THEN ARRAY[4, 6]
        WHEN p_party_size BETWEEN 5  AND 6  THEN ARRAY[6, 8]
        WHEN p_party_size BETWEEN 7  AND 8  THEN ARRAY[8, 10]
        WHEN p_party_size BETWEEN 9  AND 10 THEN ARRAY[10]
        WHEN p_party_size BETWEEN 11 AND 20 THEN ARRAY[20]
        ELSE ARRAY[]::int[]
    END;
$$;
