CREATE OR REPLACE FUNCTION util.trg_status_transition()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    IF (OLD.status, NEW.status) NOT IN (
        ('booked', 'seated'),
        ('booked', 'cancelled'),
        ('booked', 'no_show'),
        ('seated', 'completed')
    ) THEN
        RAISE EXCEPTION 'reservation % cannot go from % to %',
            OLD.reservation_id, OLD.status, NEW.status USING ERRCODE = 'RB409';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER status_transition
BEFORE UPDATE OF status ON reservation
FOR EACH ROW
EXECUTE FUNCTION util.trg_status_transition();
