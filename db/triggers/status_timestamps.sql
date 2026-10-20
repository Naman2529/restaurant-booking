CREATE OR REPLACE FUNCTION trg_status_timestamps()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    IF NEW.status = 'seated' THEN
        NEW.seated_at := now();
    ELSIF NEW.status = 'cancelled' THEN
        NEW.cancelled_at := now();
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER status_timestamps
BEFORE UPDATE OF status ON reservation
FOR EACH ROW
EXECUTE FUNCTION trg_status_timestamps();
