CREATE OR REPLACE FUNCTION staff.seat_map(p_restaurant_id bigint)
RETURNS TABLE (
    table_id       bigint,
    table_number   int,
    capacity       int,
    colour         text,
    reservation_id bigint,
    period         tsrange
)
LANGUAGE sql
STABLE
AS $$
    SELECT t.table_id,
           t.table_number,
           t.capacity,
           CASE
               WHEN r.status = 'seated' AND util.ist_now() < upper(r.period) THEN 'red'
               WHEN r.status = 'seated'                                 THEN 'orange'
               WHEN r.status = 'booked' AND lower(r.period) <= util.ist_now() THEN 'gray'
               WHEN r.status = 'booked'                                 THEN 'transparent'
               ELSE 'green'
           END,
           r.reservation_id,
           r.period
    FROM dining_table t
    LEFT JOIN LATERAL (
        SELECT r.reservation_id, r.status, r.period
        FROM reservation r
        WHERE r.table_id = t.table_id
          AND (
                r.status = 'seated'
             OR (r.status = 'booked'
                 AND lower(r.period) <= util.ist_now() + interval '30 minutes'
                 AND util.ist_now() < upper(r.period))
          )
        ORDER BY r.status = 'seated' DESC, lower(r.period)
        LIMIT 1
    ) r ON true
    WHERE t.restaurant_id = p_restaurant_id
    ORDER BY t.table_number;
$$;
