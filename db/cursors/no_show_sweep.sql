CREATE OR REPLACE PROCEDURE staff.no_show_sweep(
    p_restaurant_id bigint,
    p_staff_id      bigint,
    INOUT p_marked  int DEFAULT 0,
    INOUT p_skipped int DEFAULT 0
)
LANGUAGE plpgsql
AS $$
DECLARE
    c_overdue CURSOR FOR
        SELECT r.reservation_id, t.table_number, lower(r.period) AS starts_at
        FROM reservation r
        JOIN dining_table t ON t.table_id = r.table_id
        WHERE t.restaurant_id = p_restaurant_id
          AND r.status = 'booked'
          AND lower(r.period) + interval '15 minutes' <= util.ist_now()
        ORDER BY lower(r.period);

    v_reservation_id bigint;
    v_table_number   int;
    v_starts_at      timestamp;
BEGIN
    PERFORM util.check_staff(p_staff_id, p_restaurant_id, ARRAY['receptionist', 'waiter']);

    p_marked  := 0;
    p_skipped := 0;

    OPEN c_overdue;

    LOOP
        FETCH c_overdue INTO v_reservation_id, v_table_number, v_starts_at;
        EXIT WHEN NOT FOUND;

        BEGIN
            CALL staff.mark_no_show(v_reservation_id, p_staff_id);
            p_marked := p_marked + 1;
            RAISE NOTICE 'marked reservation % (table %, %) as no-show',
                v_reservation_id, v_table_number, v_starts_at;
        EXCEPTION
            WHEN OTHERS THEN
                p_skipped := p_skipped + 1;
                RAISE NOTICE 'skipped reservation % (table %): %',
                    v_reservation_id, v_table_number, SQLERRM;
        END;
    END LOOP;

    CLOSE c_overdue;
END;
$$;
