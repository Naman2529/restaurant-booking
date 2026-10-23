-- Test 03: customer procedures (sign up, verify, resend, book, cancel) and auth (logout).
--   psql -f db/tests/03_customer_procedures.sql
-- Errors show their code (RBxxx). The last three digits are the HTTP status the API returns.

\echo
\echo '################################################################'
\echo '##  TEST 03 - CUSTOMER + AUTH PROCEDURES'
\echo '################################################################'
\ir _setup.sql
\set VERBOSITY verbose

-- A real bcrypt hash, the shape Go sends (the plain password never reaches the DB).
SELECT crypt('password123', gen_salt('bf', 10)) AS hash \gset

\echo
\echo '---------------- sign_up / verify_email / resend_verification ----------------'

\echo
\echo '=== T3.1  sign_up a new customer  (EXPECT: new user_id + a 64-char verify token, returned once) ==='
CALL customer.sign_up('test.user@example.com', 'Test User', '+91 98100 00009', :'hash', NULL, NULL) \gset su_
SELECT :su_p_user_id AS user_id, :'su_p_verify_token' AS verify_token, length(:'su_p_verify_token') AS token_length;
\set new_user :su_p_user_id

\echo
\echo '=== T3.2  Stored row: only the SHA-256 of the token is kept, not verified yet  (EXPECT: hash is 64 hex chars, verified = f, expires in 24 h) ==='
SELECT email, email_verified_at IS NOT NULL AS verified, length(verify_token_hash) AS hash_length,
       verify_token_expires_at - created_at AS valid_for
FROM app_user WHERE user_id = :new_user;

\echo
\echo '=== T3.3  Same email in different case  (EXPECT: RB409 email ... is already registered) ==='
CALL customer.sign_up('TEST.User@Example.com', 'Copy', NULL, :'hash', NULL, NULL);

\echo
\echo '=== T3.4  Email without @  (EXPECT: RB422 email ... is not valid) ==='
CALL customer.sign_up('not-an-email', 'Someone', NULL, :'hash', NULL, NULL);

\echo
\echo '=== T3.5  Blank name  (EXPECT: RB422 full name is required) ==='
CALL customer.sign_up('blank@example.com', '   ', NULL, :'hash', NULL, NULL);

\echo
\echo '=== T3.6  Plain password instead of a bcrypt hash  (EXPECT: RB422 password hash is not a bcrypt hash) ==='
CALL customer.sign_up('plain@example.com', 'Plain Text', NULL, 'password123', NULL, NULL);

\echo
\echo '=== T3.7  Unverified new user tries to book  (EXPECT: RB403 verify your email before booking) ==='
CALL customer.book_table(:new_user, :spice, '2026-11-12 19:00', 2, NULL);

\echo
\echo '=== T3.8  verify_email with the right token  (EXPECT: returns the user_id, verified = t, token cleared) ==='
CALL customer.verify_email(:'su_p_verify_token', NULL);
SELECT email, email_verified_at IS NOT NULL AS verified, verify_token_hash IS NULL AS token_cleared
FROM app_user WHERE user_id = :new_user;

\echo
\echo '=== T3.9  Same link clicked twice  (EXPECT: RB404 verification link is invalid, expired or already used) ==='
CALL customer.verify_email(:'su_p_verify_token', NULL);

\echo
\echo '=== T3.10 Made-up token  (EXPECT: RB404 verification link is invalid, expired or already used) ==='
CALL customer.verify_email('0000000000000000000000000000000000000000000000000000000000000000', NULL);

\echo
\echo '=== T3.11 Meera (seed, unverified) asks twice for a new link, uses the first  (EXPECT: RB404, the second link replaced it) ==='
CALL customer.resend_verification('meera@example.com', NULL) \gset first_
CALL customer.resend_verification('meera@example.com', NULL) \gset second_
CALL customer.verify_email(:'first_p_verify_token', NULL);

\echo
\echo '=== T3.12 Meera uses the second link  (EXPECT: returns Meera''s user_id) ==='
CALL customer.verify_email(:'second_p_verify_token', NULL);

\echo
\echo '=== T3.13 resend for a verified email and for an unknown one  (EXPECT: both NULL, no error: nobody can probe who is registered) ==='
CALL customer.resend_verification('aarav@example.com', NULL);
CALL customer.resend_verification('nobody@example.com', NULL);

\echo
\echo '=== T3.14 Link used after its 24 h expiry  (EXPECT: RB404 verification link is invalid, expired or already used) ==='
CALL customer.sign_up('late@example.com', 'Late Clicker', NULL, :'hash', NULL, NULL) \gset late_
UPDATE app_user SET verify_token_expires_at = now() - interval '1 minute' WHERE email = 'late@example.com';
CALL customer.verify_email(:'late_p_verify_token', NULL);

\echo
\echo '---------------- book_table (now = 10 Nov 19:20) ----------------'

\echo
\echo '=== T3.15 Book Spice Route, 12 Nov 19:00, party 2  (EXPECT: reservation id, smallest table = table 1) ==='
CALL customer.book_table(:aarav, :spice, '2026-11-12 19:00', 2, NULL) \gset first_
SELECT r.reservation_id, t.table_number, t.capacity, r.party_size, r.period, r.status
FROM reservation r JOIN dining_table t USING (table_id)
WHERE r.reservation_id = :first_p_reservation_id;

\echo
\echo '=== T3.16 Nine more parties of 2 at the same slot  (EXPECT: tables 2-4, then 4-seaters 5-8, then 2 refused RB409 no table available) ==='
\set VERBOSITY default
DO $$
DECLARE
    v_user bigint := (SELECT user_id FROM app_user WHERE email = 'priya@example.com');
    v_rest bigint := (SELECT restaurant_id FROM restaurant WHERE name = 'Spice Route');
    v_id   bigint;
    v_num  int;
BEGIN
    FOR i IN 2..10 LOOP
        BEGIN
            v_id := NULL;
            CALL customer.book_table(v_user, v_rest, '2026-11-12 19:00', 2, v_id);
            SELECT t.table_number INTO v_num
            FROM reservation r JOIN dining_table t USING (table_id)
            WHERE r.reservation_id = v_id;
            RAISE NOTICE 'party % -> reservation %, table %', i, v_id, v_num;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'party % -> refused: % %', i, SQLSTATE, SQLERRM;
        END;
    END LOOP;
END
$$;
\set VERBOSITY verbose

\echo
\echo '=== T3.17 Party of 12  (EXPECT: a hall, table 14) ==='
CALL customer.book_table(:rohan, :spice, '2026-11-12 19:00', 12, NULL) \gset hall_
SELECT t.table_number, t.capacity, r.party_size
FROM reservation r JOIN dining_table t USING (table_id)
WHERE r.reservation_id = :hall_p_reservation_id;

\echo
\echo '=== T3.18 Start already passed: today 19:00 (now 19:20)  (EXPECT: RB422 start time ... is in the past) ==='
CALL customer.book_table(:aarav, :spice, '2026-11-10 19:00', 2, NULL);

\echo
\echo '=== T3.19 Party of 0 and party of 21  (EXPECT: RB422 party size must be 1 to 20, twice) ==='
CALL customer.book_table(:aarav, :spice, '2026-11-12 13:00', 0, NULL);
CALL customer.book_table(:aarav, :spice, '2026-11-12 13:00', 21, NULL);

\echo
\echo '=== T3.20 Start at 13:15 and at 21:30  (EXPECT: RB422 start must be on a :00 or :30 slot from 07:00 to 21:00, twice) ==='
CALL customer.book_table(:aarav, :spice, '2026-11-12 13:15', 2, NULL);
CALL customer.book_table(:aarav, :spice, '2026-11-12 21:30', 2, NULL);

\echo
\echo '=== T3.21 Restaurant that does not exist  (EXPECT: RB404 restaurant not found) ==='
CALL customer.book_table(:aarav, 999999, '2026-11-12 13:00', 2, NULL);

\echo
\echo '=== T3.22 User that does not exist  (EXPECT: RB404 user account not found) ==='
CALL customer.book_table(999999, :spice, '2026-11-12 13:00', 2, NULL);

\echo
\echo '---------------- cancel_reservation (now = 10 Nov 19:20) ----------------'

\echo
\echo '=== T3.23 Aarav cancels his own 12 Nov booking  (EXPECT: status cancelled, cancelled_at set) ==='
CALL customer.cancel_reservation(:first_p_reservation_id, :aarav);
SELECT reservation_id, status, cancelled_at IS NOT NULL AS cancelled_at_set
FROM reservation WHERE reservation_id = :first_p_reservation_id;

\echo
\echo '=== T3.24 The freed table is bookable again  (EXPECT: table 1 offered for 12 Nov 19:00) ==='
SELECT * FROM customer.available_tables(:spice, '2026-11-12 19:00', 2);

\echo
\echo '=== T3.25 Cancel the same booking again  (EXPECT: RB409 ... is cancelled and cannot be cancelled) ==='
CALL customer.cancel_reservation(:first_p_reservation_id, :aarav);

\echo
\echo '=== T3.26 Aarav tries to cancel Rohan''s hall booking  (EXPECT: RB404 reservation not found, same as a missing id) ==='
CALL customer.cancel_reservation(:hall_p_reservation_id, :aarav);

\echo
\echo '=== T3.27 Reservation id that does not exist  (EXPECT: RB404 reservation not found) ==='
CALL customer.cancel_reservation(999999, :aarav);

\echo
\echo '=== T3.28 Booking at 19:30 today, cancelled at 19:20 (10 min before)  (EXPECT: RB409 ... starts in less than 15 minutes) ==='
CALL customer.book_table(:aarav, :spice, '2026-11-10 19:30', 2, NULL) \gset soon_
CALL customer.cancel_reservation(:soon_p_reservation_id, :aarav);

\echo
\echo '---------------- book_specific_table (customer picks on the floor plan) ----------------'

\echo
\echo '=== T3.33 Party of 2 picks table 6, a 4-seater (one size up), 14 Nov 19:00  (EXPECT: booked on table 6) ==='
CALL customer.book_specific_table(:aarav, :spice, '2026-11-14 19:00', 2, 6, NULL) \gset pick_
SELECT r.reservation_id, t.table_number, t.capacity, r.party_size, r.period
FROM reservation r JOIN dining_table t USING (table_id)
WHERE r.reservation_id = :pick_p_reservation_id;

\echo
\echo '=== T3.34 Party of 2 picks table 9, a 6-seater (two sizes up)  (EXPECT: RB422 table 9 (capacity 6) is not allowed for a party of 2) ==='
CALL customer.book_specific_table(:aarav, :spice, '2026-11-14 19:00', 2, 9, NULL);

\echo
\echo '=== T3.35 Priya picks table 6 for 20:00, inside Aarav''s sitting + buffer  (EXPECT: RB409 table 6 was just booked for that time, please pick another) ==='
CALL customer.book_specific_table(:priya, :spice, '2026-11-14 20:00', 2, 6, NULL);

\echo
\echo '=== T3.36 Table 99 does not exist  (EXPECT: RB404 table 99 not found) ==='
CALL customer.book_specific_table(:aarav, :spice, '2026-11-14 19:00', 2, 99, NULL);

\echo
\echo '=== T3.37 Same shared checks as book_table: past start, unverified user  (EXPECT: RB422 in the past; RB403 verify your email) ==='
CALL customer.book_specific_table(:aarav, :spice, '2026-11-10 19:00', 2, 1, NULL);
CALL customer.book_specific_table(:late_p_user_id, :spice, '2026-11-14 19:00', 2, 1, NULL);

\echo
\echo '=== T3.38 table_availability now shows table 6 taken for 14 Nov 19:00, party 2  (EXPECT: 6 not free; 1-5, 7, 8 bookable) ==='
SELECT table_number, capacity, fits_party AND is_free AS bookable
FROM customer.table_availability(:spice, '2026-11-14 19:00', 2)
WHERE fits_party;

\echo
\echo '---------------- auth.revoke_token / is_revoked (logout) ----------------'

\echo
\echo '=== T3.29 Log out token "jti-abc"  (EXPECT: is_revoked = t) ==='
CALL auth.revoke_token('jti-abc', now() + interval '12 hours');
SELECT auth.is_revoked('jti-abc') AS abc_revoked, auth.is_revoked('jti-other') AS other_revoked;

\echo
\echo '=== T3.30 Log out the same token twice  (EXPECT: no error, still one row) ==='
CALL auth.revoke_token('jti-abc', now() + interval '12 hours');
SELECT count(*) AS rows_for_abc FROM revoked_token WHERE jti = 'jti-abc';

\echo
\echo '=== T3.31 Expired rows are cleaned up on the next logout  (EXPECT: jti-old gone, jti-new kept) ==='
INSERT INTO revoked_token VALUES ('jti-old', now() - interval '1 hour');
CALL auth.revoke_token('jti-new', now() + interval '12 hours');
SELECT jti FROM revoked_token ORDER BY jti;

\echo
\echo '=== T3.32 Empty token id  (EXPECT: RB422 token id is required) ==='
CALL auth.revoke_token('', now());

ROLLBACK;
\echo '(rolled back: database unchanged)'
