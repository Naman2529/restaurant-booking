DROP TABLE IF EXISTS reservation      CASCADE;
DROP TABLE IF EXISTS restaurant_staff CASCADE;
DROP TABLE IF EXISTS app_user         CASCADE;
DROP TABLE IF EXISTS dining_table     CASCADE;
DROP TABLE IF EXISTS restaurant       CASCADE;

CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE restaurant (
    restaurant_id bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          text        NOT NULL,
    address       text,
    phone         text,
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE dining_table (
    table_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    restaurant_id bigint NOT NULL REFERENCES restaurant ON DELETE CASCADE,
    table_number  int    NOT NULL CHECK (table_number > 0),
    capacity      int    NOT NULL CHECK (capacity IN (2, 4, 6, 8, 10, 20)),
    UNIQUE (restaurant_id, table_number)
);

CREATE TABLE app_user (
    user_id           bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email             citext      NOT NULL UNIQUE,
    full_name         text        NOT NULL,
    phone             text,
    password_hash     text        NOT NULL,
    email_verified_at timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE restaurant_staff (
    staff_id      bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    restaurant_id bigint      NOT NULL REFERENCES restaurant ON DELETE CASCADE,
    email         citext      NOT NULL UNIQUE,
    full_name     text        NOT NULL,
    password_hash text        NOT NULL,
    role          text        NOT NULL CHECK (role IN ('receptionist', 'waiter')),
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE reservation (
    reservation_id bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id        bigint      NOT NULL REFERENCES app_user     ON DELETE RESTRICT,
    table_id       bigint      NOT NULL REFERENCES dining_table ON DELETE RESTRICT,
    party_size     int         NOT NULL CHECK (party_size BETWEEN 1 AND 20),
    period         tsrange     NOT NULL,
    status         text        NOT NULL DEFAULT 'booked'
                   CHECK (status IN ('booked', 'seated', 'completed', 'no_show', 'cancelled')),
    created_at     timestamptz NOT NULL DEFAULT now(),
    seated_at      timestamptz,
    cancelled_at   timestamptz,

    CONSTRAINT period_shape CHECK (
        NOT isempty(period)
        AND NOT lower_inf(period) AND NOT upper_inf(period)
        AND lower_inc(period) AND NOT upper_inc(period)
    ),

    CONSTRAINT start_on_slot CHECK (
        date_part('minute', lower(period)) IN (0, 30)
        AND date_part('second', lower(period)) = 0
        AND lower(period)::time BETWEEN '07:00' AND '21:00'
    ),

    CONSTRAINT end_by_2300 CHECK (
        upper(period) <= lower(period)::date + time '23:00'
    ),

    CONSTRAINT no_double_booking EXCLUDE USING gist (
        table_id WITH =,
        tsrange(lower(period), upper(period) + interval '30 minutes') WITH &&
    ) WHERE (status IN ('booked', 'seated'))
);
