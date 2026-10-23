-- A restaurant's floor plan, ready to draw: its labelled features and every
-- table with its position, on a 1000 x 640 area. Customers and staff draw the
-- same plan; the colours come from table_availability or staff.seat_map.
-- Returns NULL for a restaurant that doesn't exist.
CREATE OR REPLACE FUNCTION customer.floor_plan(p_restaurant_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object(
        'restaurant_id', r.restaurant_id,
        'name',          r.name,
        'width',         1000,
        'height',        640,
        'features', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
                       'kind', f.kind, 'label', f.label,
                       'x', f.x, 'y', f.y, 'width', f.width, 'height', f.height)
                   ORDER BY f.feature_id)
            FROM floor_feature f
            WHERE f.restaurant_id = r.restaurant_id), '[]'::jsonb),
        'tables', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
                       'table_number', t.table_number, 'capacity', t.capacity,
                       'x', t.pos_x, 'y', t.pos_y)
                   ORDER BY t.table_number)
            FROM dining_table t
            WHERE t.restaurant_id = r.restaurant_id), '[]'::jsonb)
    )
    FROM restaurant r
    WHERE r.restaurant_id = p_restaurant_id;
$$;
