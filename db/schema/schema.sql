DROP TABLE IF EXISTS revoked_token    CASCADE;
DROP TABLE IF EXISTS floor_feature    CASCADE;
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
    cuisine       text,
    tagline       text,
    photo         text,       -- path of the cover image the front end shows
    address       text,
    phone         text,
    created_at    timestamptz NOT NULL DEFAULT now()
);

-- pos_x / pos_y: the table's centre on the restaurant's floor plan, which is
-- a 1000 x 640 drawing area. Drawing only: no booking rule uses them.
CREATE TABLE dining_table (
    table_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    restaurant_id bigint NOT NULL REFERENCES restaurant ON DELETE CASCADE,
    table_number  int    NOT NULL CHECK (table_number > 0),
    capacity      int    NOT NULL CHECK (capacity IN (2, 4, 6, 8, 10, 20)),
    pos_x         int    NOT NULL DEFAULT 0 CHECK (pos_x BETWEEN 0 AND 1000),
    pos_y         int    NOT NULL DEFAULT 0 CHECK (pos_y BETWEEN 0 AND 640),
    UNIQUE (restaurant_id, table_number)
);

-- The labelled parts of a floor plan (bar, pond, entrance...), drawn around
-- the tables. x / y is the top-left corner on the same 1000 x 640 area.
CREATE TABLE floor_feature (
    feature_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    restaurant_id bigint NOT NULL REFERENCES restaurant ON DELETE CASCADE,
    kind          text   NOT NULL CHECK (kind IN ('entrance', 'bar', 'kitchen', 'counter', 'pond', 'garden',
                                                  'terrace', 'deck', 'window', 'fireplace', 'shelf')),
    label         text   NOT NULL,
    x             int    NOT NULL CHECK (x BETWEEN 0 AND 1000),
    y             int    NOT NULL CHECK (y BETWEEN 0 AND 640),
    width         int    NOT NULL CHECK (width > 0),
    height        int    NOT NULL CHECK (height > 0),

    CONSTRAINT feature_inside_plan CHECK (x + width <= 1000 AND y + height <= 640)
);

CREATE TABLE app_user (
    user_id           bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email             citext      NOT NULL UNIQUE,
    full_name         text        NOT NULL,
    phone             text,
    password_hash     text        NOT NULL,
    email_verified_at timestamptz,
    verify_token_hash text        UNIQUE,
    verify_token_expires_at timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now(),

    -- A token and its expiry are always set (or cleared) together.
    CONSTRAINT verify_token_pair CHECK (
        (verify_token_hash IS NULL) = (verify_token_expires_at IS NULL)
    )
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

-- Tokens logged out before they expired. jti is the token's random id.
-- Rows only matter until expires_at; after that the token is dead anyway.
CREATE TABLE revoked_token (
    jti        text        PRIMARY KEY,
    expires_at timestamptz NOT NULL
);
