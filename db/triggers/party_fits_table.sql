CREATE OR REPLACE FUNCTION trg_party_fits_table()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_capacity     int;
    v_table_number int;
BEGIN
    SELECT capacity, table_number
    INTO v_capacity, v_table_number
    FROM dining_table
    WHERE table_id = NEW.table_id;

    IF NOT v_capacity = ANY (allowed_capacities(NEW.party_size)) THEN
        RAISE EXCEPTION 'table % (capacity %) is not allowed for a party of %',
            v_table_number, v_capacity, NEW.party_size;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER party_fits_table
BEFORE INSERT OR UPDATE OF party_size, table_id ON reservation
FOR EACH ROW
EXECUTE FUNCTION trg_party_fits_table();
