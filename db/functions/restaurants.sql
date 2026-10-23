-- Every restaurant a customer can book at, for the home page.
CREATE OR REPLACE FUNCTION customer.restaurants()
RETURNS TABLE (restaurant_id bigint, name text, cuisine text, tagline text, photo text,
               address text, phone text)
LANGUAGE sql
STABLE
AS $$
    SELECT r.restaurant_id, r.name, r.cuisine, r.tagline, r.photo, r.address, r.phone
    FROM restaurant r
    ORDER BY r.name;
$$;
