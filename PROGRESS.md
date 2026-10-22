# Progress

Session handoff file. Read this first in a new session, then README.md (rules) and LATER.md (deferred items).

**Last updated:** Thu 22 Oct 2026, ~23:00 IST.
**Deadline:** Sat 24 Oct, 11:59 PM. Aim to submit 23 Oct.
**Status:** DB layer done (Days 1–6). Day 7 done (Go server, limited `booking_app` role). **Day 8 done (22 Oct):** all 7 units (error codes, auth SQL, JWT + cookie middleware, DB error → HTTP, auth routes, customer routes, staff routes) plus 5 limitation fixes. The whole API is built and tested with curl. **Next: Day 9** (Go concurrency test, pick the front-end stack, start customer pages). Deferred to the final pass (after the front end): the "test every object" script, all screenshots, and the `book_table` race test. Calendar says Day 10 (Thu 22 Oct), so about 1.5 days behind. Original schedule kept; user is catching up.

---

## Working Agreement

- Claude writes code **one unit at a time** (one table, one function, one procedure), only into the file/folder the user asks for, then explains it and **waits** for the user to run it before writing the next.
- Claude does not edit other files as a side effect without asking first.
- Design and product decisions stay with the user. For implementation choices, Claude picks a sensible default and states it so the user can veto.
- No viva: marks are **100% based on the report**. Screenshots and figure captions are the evidence, so take them as you go.
- The user is deferring report writing and diagrams until later. Code first.
- Keep answers short and plain. Keep the user on schedule.

---

## Environment

- Windows 11, PowerShell, VS Code.
- **PostgreSQL 17.11** (EDB 18 download was blocked with a 403). `C:\Program Files\PostgreSQL\17\bin` is on the user PATH.
- **Go 1.27** installed via winget (not used yet).
- Database: `restaurant_booking`, user `postgres`.
- `.env` in the project root holds `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`. It is gitignored. Load it in each new terminal:
  ```powershell
  Get-Content .env | ForEach-Object { if ($_ -match '^\s*([^#=]+)=(.*)$') { Set-Item "env:$($matches[1].Trim())" $matches[2].Trim() } }
  ```
- Then run files with `psql -v ON_ERROR_STOP=1 -f <file>`.
- VS Code's SQL linter is using the wrong dialect, so ignore its red squiggles. Only trust errors from psql.
- Git remote: https://github.com/Naman2529/restaurant-booking (branch `main`). Commit, then **push**.
- Gitignored: `LATER.md`, `PROJECT_PLAN.md`, `.env`, `graphify-out/`. `docs/screenshots/` is tracked on purpose.

---

## Done

| File | What | Status |
|---|---|---|
| `db/schema/schema.sql` | 5 tables, CHECKs, exclusion constraint | Run and tested |
| `db/seed/seed.sql` | 2 restaurants, 23 tables, 4 users (Meera unverified), 4 staff, 7 reservations covering every status | Run |
| `db/functions/ist_now.sql` | `ist_now()`: current IST as a plain `timestamp` | Run and tested |
| `db/functions/allowed_capacities.sql` | `allowed_capacities(party)`: allowed table sizes as `int[]`, smallest first | Written, test shown |
| `db/functions/available_tables.sql` | `available_tables(restaurant, start, party)`: free tables, best fit first | Run and tested |
| `db/functions/available_slots.sql` | `available_slots(restaurant, date, party)`: bookable 30-minute slots with a free-table count | Run and tested |
| `db/functions/seat_map.sql` | `seat_map(restaurant)`: every table with derived colour (green / transparent / gray / red / orange) plus the reservation id and period it is showing | Run (all green on seed) |
| `db/functions/can_cancel.sql` | `can_cancel(reservation, user)`: owner + status `booked` + at least 15 min before start | Run and tested |
| `db/procedures/book_table.sql` | `book_table(user, restaurant, start, party, INOUT reservation_id)`: rejects past starts, missing/unverified users; tries `available_tables` smallest first; catches `23P01` and moves to the next table | Run and tested (happy path, unverified, past) |
| `db/functions/check_staff.sql` | `check_staff(staff, restaurant, roles[])`: raises if staff missing, at another restaurant, or wrong role. Used via `PERFORM` by every staff procedure | Run and tested |
| `db/procedures/cancel_reservation.sql` | `cancel_reservation(reservation, user)`: row lock, specific errors (missing / not owner / not booked / under 15 min via `can_cancel`), sets `cancelled` + `cancelled_at` | Run and tested |
| `db/procedures/seat_reservation.sql` | `seat_reservation(reservation, staff)`: receptionist only; booked → seated + `seated_at`; allowed from 30 min before start until period end | Run and tested |
| `db/procedures/complete_reservation.sql` | `complete_reservation(reservation, staff)`: both roles; seated → completed (frees the table) | Run and tested (seat map back to green) |
| `db/procedures/mark_no_show.sql` | `mark_no_show(reservation, staff)`: both roles; booked → no_show, only after start time (gray tables) | Run and tested (gray → green) |
| `db/procedures/extend_reservation.sql` | `extend_reservation(reservation, staff, extra interval)`: both roles; seated only; pushes `upper(period)`; friendly errors on `23P01` (next booking) and `end_by_2300` | Run and tested (happy, clash, 23:00 boundary, past 23:00, not seated, wrong restaurant, non-positive) |
| `db/procedures/reassign_table.sql` | `reassign_table(reservation, staff, new_table_number)` (took a table id until 22 Oct): receptionist only; `booked` only (seated parties never move); same restaurant, different table, capacity in `allowed_capacities`; friendly error on `23P01`. Error messages show table **numbers**, never ids | Run and tested (8 cases) |
| `db/triggers/party_fits_table.sql` | BEFORE INSERT OR UPDATE OF `party_size, table_id`: table capacity must be in `allowed_capacities(party)`. Backstop for raw writes (defence in depth with the procedures) | Run and tested (8 cases, existing rows checked) |
| `db/triggers/status_transition.sql` | BEFORE UPDATE OF `status`: only `booked→seated/cancelled/no_show` and `seated→completed`; same-status is a no-op. INSERT not checked on purpose (super admin / seed can insert any status; app only goes through `book_table`) | Run and tested (9 cases) |
| `db/triggers/status_timestamps.sql` | BEFORE UPDATE OF `status`: sets `seated_at` / `cancelled_at` to `now()`, overwriting any value passed (no backdating). Procedures still set them too; kept on purpose | Run and tested |
| `db/cursors/no_show_sweep.sql` | `no_show_sweep(restaurant, staff, INOUT marked, INOUT skipped)`: explicit cursor (OPEN/FETCH/CLOSE) over `booked` rows with start + 15 min ≤ now; calls `mark_no_show` per row inside `BEGIN … EXCEPTION` (savepoint), so one failure is skipped and logged and the loop goes on. NOTICE per row. Why not one UPDATE: reuses `mark_no_show` rules, per-row error isolation, per-row log | Run and tested (wrong staff, 2 marked, seated + other restaurant ignored, second run = 0). Skip path untested (needs 2 sessions, do with race test) |

| `db/schema/packages.sql` | "Packages" = 3 Postgres schemas: `util` (helpers + trigger functions), `customer` (slots, tables, book, cancel, can_cancel), `staff` (seat map, seat, complete, no-show, extend, reassign, sweep). Every object is schema-qualified, and so is every call between them | Run |
| `db/reset.sql` | Rebuilds the whole DB in one go with `\ir`: packages → schema → seed → util → customer → staff → triggers → roles | Run clean (21 Oct) |
| `db/roles.sql` | `booking_app` login role (password from `APP_DB_PASSWORD` via `\getenv`). Every routine in `customer` / `staff` becomes `SECURITY DEFINER` with a pinned `search_path` (loop over `pg_proc`). EXECUTE revoked from PUBLIC, granted to `booking_app` on `customer` + `staff` only. `util` hidden. Tables: SELECT only | Run and tested (book via procedure ✅, direct UPDATE denied ✅, `util.ist_now()` denied ✅) |
| `backend/internal/config/config.go` | Loads `.env` (godotenv, current dir then parent, never overrides). Requires `PGHOST`, `PGPORT`, `PGDATABASE`, `APP_DB_PASSWORD`. `HTTP_PORT` (default 8080), `APP_DB_USER` (default `booking_app`) | Built |
| `backend/internal/db/db.go` | `Connect(ctx, user, password)`: `pgxpool.ParseConfig("")` reads `PG*`, then user/password swapped for the app role. Pings with a 5 s timeout at startup | Built |
| `backend/cmd/server/main.go` | Config → DB → Echo (Logger + Recover). `GET /health` returns `current_user` (shows `booking_app`). Ctrl+C = graceful shutdown (10 s) | Run and tested |
| **Day 8 unit 1:** error codes | Every `RAISE EXCEPTION` in procedures / functions / triggers now has `USING ERRCODE`: `RB404` not found, `RB403` not allowed (wrong owner / role / restaurant, unverified), `RB409` state or time clash (wrong status, too early, <15 min, no table, table taken), `RB422` bad input (past start, bad extension, past 23:00, capacity). Last 3 chars = HTTP status. Postgres's own: `23P01` → 409, `23514` → 422, rest → 500 | Run and tested (RB404 / RB403 / RB422 / RB403 seen with `\set VERBOSITY verbose`) |
| **Day 8 unit 2:** `app_user.verify_token_hash` + `db/procedures/sign_up.sql`, `verify_email.sql`, `db/functions/customer_login.sql`, `staff_login.sql` | `customer.sign_up(email, name, phone, password, INOUT user_id, INOUT verify_token)`: validates (RB422), bcrypt via pgcrypto, random 32-byte token returned once, only its SHA-256 stored, duplicate email → RB409. `customer.verify_email(token, INOUT user_id)`: single-use (clears hash), bad/used → RB404. `customer.login(email citext, password)` / `staff.login(...)`: password checked in Postgres; 0 rows = bad credentials (no "which one was wrong"). Unverified users can log in; `book_table` stops them booking. All picked up by `roles.sql` automatically | Run and tested as `booking_app` (sign-up, case-insensitive login, wrong password, duplicate, bad email, short password, staff login, verify once ✅ / twice → RB404) |
| **Day 8 unit 3:** `backend/internal/auth/auth.go` + `auth_test.go`, config `JWT_SECRET` (≥ 32 chars, in `.env`) + `COOKIE_SECURE` | JWT HS256 (golang-jwt/v5), 12 h. Claims: `kind` (customer/staff), `sub` (id); staff also `rid` + `role`, so staff routes take the restaurant from the token, never the client. Only HS256 accepted. `SetCookie` / `ClearCookie`: `HttpOnly`, `SameSite=Strict`, per-kind name (`rb_customer` / `rb_staff`). `Require(kind)` reads cookie first, then `Authorization: Bearer` (curl / tests); 401 no/bad token, 403 wrong kind. `auth.From(c)` gives handlers the claims. Role (receptionist/waiter) NOT checked in Go: `check_staff` in the DB is the one source of truth | Tested (all PASS) |
| **Fix 1:** no-leak errors | "Not yours" (cancel), "other restaurant's reservation" (`check_staff`) and "other restaurant's table" (reassign) now raise exactly the same `RB404 reservation not found` / `table not found` as a missing id. No user / staff ids in any message. Unverified booking → `RB403 verify your email before booking` | Run and tested |
| **Fix 2:** link expiry + resend | `app_user.verify_token_expires_at` + CHECK `verify_token_pair` (hash and expiry set/cleared together). `sign_up` sets now() + 24 h; `verify_email` rejects expired (`RB404 ... invalid, expired or already used`). New `customer.resend_verification(email, INOUT token)`: new token for unverified users only, NULL (no error) for unknown / verified emails so it can't reveal who's registered | Run and tested (Meera resend → verify; expired → RB404) |
| **Fix 3:** bcrypt in Go | `customer.sign_up` now takes `p_password_hash` and rejects anything not shaped like bcrypt (60 chars, `$2…`). `customer.login` / `staff.login` **renamed** `customer.login_info` / `staff.login_info`: return the account + `password_hash`, no check in SQL. `internal/auth/password.go`: `HashPassword` (8–72 chars, cost 10), `CheckPassword(hash, pw)` (pass `""` for unknown email: compares against a dummy hash so timing doesn't reveal which emails exist). Seed still uses pgcrypto (cost 6); compatible, tested | Run and tested |
| **Fix 4:** logout revocation | New 4th schema **`auth`** (`packages.sql`, `roles.sql` grant it). Table `revoked_token(jti PK, expires_at)`. `auth.revoke_token(jti, expires_at)` (idempotent, deletes expired rows), `auth.is_revoked(jti)`. Go: every token gets a random 16-byte `jti`; `Tokens.Revoke(ctx, claims)`; `Require` checks `IsRevoked` (DB error → refuse). `NewTokens(secret, secureCookie, store)`; `auth.PGRevocations{Pool}` is the DB store. `Claims.ID()` renamed **`SubjectID()`** (`ID` is the jti now) | Run and tested (incl. `booking_app` can't delete from the list) |
| **Fix 5:** Gmail | `internal/mail`: `Sender` interface; `mail.New(user, pw)` → `Gmail` (smtp.gmail.com:587, STARTTLS, 15 s timeout) or `LogSender` (prints link) if not configured. `VerifyLink(base, token)` → `<base>/auth/verify?token=…`. Address parsed first (blocks header injection). Config: `SMTP_USER` + `SMTP_PASSWORD` (both or neither), `APP_BASE_URL` (default `http://localhost:<port>`). Dev tool: `go run ./cmd/mailtest <to>` | Tested; real email sent to namanbhatia2501@gmail.com |
| **Day 8 unit 4:** `backend/internal/api/errors.go` + `errors_test.go` | `api.ErrorHandler` replaces Echo's (handlers just `return err`). `errors.As` finds a `*pgconn.PgError` even when wrapped. `RBxxx` → last 3 digits + the procedure's message; `23P01` → 409, `23505` → 409 (added, backstop), `23514` → 422, generic messages. Anything else → 500 "Internal Server Error" via `SetInternal`, full error only in the server log. Non-DB errors (incl. `echo.HTTPError`) pass through. Not wired yet: `e.HTTPErrorHandler = api.ErrorHandler` goes into `main.go` with unit 5 | Tested (13 cases PASS, incl. DB detail not leaked) |
| **Day 8 unit 5a:** `internal/api/routes.go` + `auth_handlers.go`, `main.go` wired | `api.API{Pool, Tokens, Mail, BaseURL}` + `Register(e)`. `POST /auth/signup` (HashPassword → `customer.sign_up` → email; email failure still 201 + log), `GET /auth/verify?token=`, `POST /auth/resend` (same answer always). `main.go`: `e.HTTPErrorHandler = api.ErrorHandler`, `NewTokens`, `mail.New` | Tested by Claude (15 cases: 201/409/422/400, single-use + replaced links 404, resend same answer) |
| **Day 8 unit 5b:** login / logout / me | `POST /auth/{customer,staff}/login` (login_info → CheckPassword, `""` hash if no row → same 401 "wrong email or password"; token in cookie AND body). `POST /auth/{kind}/logout` (Require → Revoke + ClearCookie). `GET /auth/{kind}/me` (front end can't read the HttpOnly cookie) | Tested (26 cases: wrong kind 403, forged payload / signature / `alg=none` 401, logout kills only that token) |
| **Day 8 unit 6:** `db/functions/restaurants.sql`, `my_reservations.sql`, `internal/api/customer_handlers.go` | `customer.restaurants()`, `customer.my_reservations(user)` (table number, `can_cancel` per row). Routes: `GET /restaurants`, `GET /restaurants/:id/slots?date=&party=` (public); `POST /reservations`, `GET /reservations`, `POST /reservations/:id/cancel` (customer). User id always from the token. Times = IST strings `2026-10-30T19:00`: sent as text + `::timestamp`, read back with `to_char`, never a Go `time.Time` | Tested (30 cases) |
| **`book_table` messages** | Now raises RB422 "party size must be 1 to 20", RB422 "start must be on a :00 or :30 slot from 07:00 to 21:00", RB404 "restaurant not found" before trying tables (were raw CHECK 422 / misleading 409) | Tested |
| **Day 8 unit 7:** `db/functions/day_reservations.sql`, `internal/api/staff_handlers.go`; `reassign_table` changed | `staff.day_reservations(restaurant, date)` (list for seating / reassigning, with customer name + phone). **`staff.reassign_table` now takes `p_new_table_number int`** and looks it up inside the reservation's restaurant (other restaurants' tables can't be named). Routes under `/staff` (staff token; restaurant + staff id from the token, role checked only by `check_staff`): `GET seat-map`, `GET reservations?date=` (default today IST), `POST reservations/:id/{seat,complete,no-show}`, `POST reservations/:id/extend {minutes}`, `POST reservations/:id/reassign {table_number}`, `POST no-show-sweep` → `{marked, skipped}` | Tested (35 cases incl. waiter → 403 on seat / reassign, other restaurant → 404, extend past 23:00 → 422, sweep marks 1 then 0) |

**Load order: just run `psql -f db/reset.sql`** (after loading `.env`). It drops and recreates everything. Old unprefixed copies in `public` were dropped on 21 Oct. Don't drop all of `public`: the citext / pgcrypto / btree_gist functions live there.

### Key schema facts
- `reservation.period` is a `tsrange` in IST wall-clock time, stored as `[start, end)`. Default sitting is 2 hours, and staff can extend it.
- Exclusion constraint `no_double_booking`: same `table_id` + overlapping `tsrange(lower, upper + 30 min)`, `WHERE status IN ('booked','seated')`.
- CHECKs: `period_shape`, `start_on_slot` (:00/:30, 07:00–21:00), `end_by_2300`.
- No `min_party` column. Halls are `capacity = 20` and take parties of 11+ only. That rule lives in `allowed_capacities`.
- Seat-map colours are **derived, never stored**.
- Passwords are bcrypt via pgcrypto `crypt(.., gen_salt('bf'))`. All seed passwords are `password123`.

---

## Next Up (pick up here)

1. Commit + push Day 8 (units 5–7 are not committed yet): `git add db backend PROGRESS.md`.
2. **Day 9 (next):** Go concurrency test: many goroutines call `POST /reservations` (or `CALL customer.book_table`) for the same slot / one table, exactly one wins, the rest get 409. 📸 Then pick the front-end stack and start the customer pages.
3. Open question for the user: seed passwords are bcrypt cost 6 (pgcrypto default), Go uses cost 10, so a wrong password for a **seed** account answers ~12 ms vs ~55 ms for unknown emails (timing leak, seed only). Fix = `gen_salt('bf', 10)` in `seed.sql`. Not changed yet.
4. Report "Limitations" candidates: `booking_app` has SELECT on every table (incl. `app_user.password_hash`); seat map turns a booked table green once its period has ended even if never marked no-show (sweep handles it).

- **API routes (all built, 22 Oct):** `/auth/signup`, `/auth/verify`, `/auth/resend`, `/auth/{customer,staff}/{login,logout,me}`; `/restaurants`, `/restaurants/:id/slots`; `/reservations` (GET, POST), `/reservations/:id/cancel`; `/staff/seat-map`, `/staff/reservations`, `/staff/reservations/:id/{seat,complete,no-show,extend,reassign}`, `/staff/no-show-sweep`.
- **Testing the API:** Claude runs the server binary from the scratchpad with every `.env` var except `SMTP_*`, so verify links go to the log, not Gmail. Time-sensitive staff tests insert rows as `postgres` for today (seated / booked in the past). `reset.sql` afterwards.

- **Day 8 decisions (22 Oct, user):** JWT (not server sessions), sign-up with the verify link printed to the server log (not emailed), `ERRCODE` on every `RAISE` (not "everything is 400"). Later: **cookie + header** both supported (cookie for browsers, header for curl / tests).
- **API layout (built 22 Oct):** one `internal/api` package: `errors.go`, `routes.go`, `auth_handlers.go`, `customer_handlers.go`, `staff_handlers.go`. Handlers stay thin: JSON in → `CALL` procedure → map error → JSON out. Postgres is the "service layer", no models folder (no ORM). `internal/api` created with unit 4 (user didn't object).
- **Commands:** by default the user runs them and pastes the output. When the user says "run it yourself", Claude runs them (load `.env` first; `reset.sql` from the root; `go` from `backend/`). Never commit / push unasked.

- **Backend facts:** `backend/`, module `github.com/Naman2529/restaurant-booking/backend`. Echo v4 + pgx v5 (`pgxpool`). Run with `go run ./cmd/server` from `backend/` (no need to load `.env` by hand for Go). After adding an import, run `go mod tidy`.
- **No migration tool** (decided 21 Oct): goose / golang-migrate can't run psql `\ir`, and the rubric doesn't need one. `reset.sql` stays the way to build the DB.
- Go calls must be schema-qualified: `CALL customer.book_table(...)`, `SELECT * FROM staff.seat_map(...)`.
- `booking_app` can't INSERT/UPDATE anything. Any new write the app needs (e.g. sign-up, verify email) needs a new procedure in `customer` / `staff`, then re-run `reset.sql` so `roles.sql` picks it up.
- `.env` now also has `APP_DB_PASSWORD`, `HTTP_PORT`, `JWT_SECRET`, `SMTP_USER`, `SMTP_PASSWORD`, `APP_BASE_URL`.
- Schemas are now 4: `util`, `customer`, `staff`, **`auth`** (logout). psql still logs in as `postgres` (`PGUSER`); Go as `booking_app`.
- Report "Discussion" material (talked through 22 Oct): trade-offs of putting rules in the DB. Constraints = uncontroversial; procedures/triggers = debated (harder testing, weak tooling, migrations, DB is hardest to scale, bcrypt CPU in Postgres, Postgres lock-in, two languages, user-facing messages in SQL, SECURITY DEFINER risk) vs. wins (concurrency guarantee, every client protected, fewer round trips, rubric).
- **Final pass (after the front end):** the "test every object" script (reset + exercise every object), all screenshots, and the `book_table` race test.
- psql: a `=*#` prompt means a transaction is still open. Make sure it's `=#` before `\i`-ing a file, or a later `ROLLBACK` undoes the CREATE too.

### Reminders for later steps
- **`table_id` ≠ `table_number`.** Ids are global across restaurants and the seed's `INSERT … SELECT … JOIN` doesn't fix their order. In tests, look tables up by `(restaurant_id, table_number)` with `\gset`, never hard-code ids. Staff/UI only ever see table numbers.
- Test pattern: `\set ON_ERROR_ROLLBACK on`, `BEGIN`, inserts with `RETURNING … \gset`, the `CALL`s, `ROLLBACK`.
- Screenshots: user takes them all in one pass at the end. Don't prompt for them while working.
- **Deferred: `book_table` race test** (📸 live, two terminals). Steps are in LATER.md.
- `CALL` arguments can't contain subqueries. Pass plain ids (that's how Go will call it anyway). `lastval()` is fine (e.g. `CALL seat_reservation(lastval(), 2)` right after `book_table`).
- Seed staff ids: 1 = Spice Route waiter, 2 = Spice Route receptionist, 3 = Coastal waiter, 4 = Coastal receptionist. Users: 1 Aarav, 2 Priya, 3 Rohan, 4 Meera (unverified). Restaurants: 1 Spice Route, 2 Coastal Kitchen.
- Time-sensitive tests: insert directly inside `BEGIN … ROLLBACK` to get a booking whose start has passed (`book_table` rejects past starts).
- `available_tables` is advisory. The exclusion constraint is the real guarantee (report point).
- Postgres burns identity numbers on failed / rolled-back inserts, so reservation ids have gaps. Normal.
- **Day 6 "packages"** = Postgres schemas used as namespaces (faculty accepted this).

---

## Day-by-Day Remaining

| Day | Date | Plan |
|---|---|---|
| 2 (finish) + 3 | **Thu 15 Oct** | Functions 5 and 6. **Booking procedure** (verified email, future start, pick from `available_tables`, insert, handle `23P01`). Race test with two psql terminals. 📸 |
| 4 | Fri 16 Oct | Procedures: cancel (owner + 15-minute rule), seat, complete/free, no-show, extend, reassign. Role checks: seat = receptionist; free / no-show / extend = both; reassign = receptionist. Legal status transitions only. |
| 5 | Sat 17 Oct | Triggers. Candidates: party fits table capacity (incl. halls 11+), block illegal status transitions, auto-set `seated_at` / `cancelled_at`. |
| 6 | Sun 18 Oct | A cursor with a real row-by-row job. Group objects into schemas ("packages"). Test every object. **DB layer done.** |
| 7 | Mon 19 Oct | Go foundation: Echo + pgx, config from `.env`, DB pool, first routes, migration tool. |
| 8 | Tue 20 Oct | All routes, map DB errors to HTTP, customer and staff auth (bcrypt). ✅ **Done 22 Oct** |
| 9 | Wed 21 Oct | Go concurrency test (many goroutines, one slot, exactly one wins). 📸 Pick the front-end stack and start the customer pages. |
| 10 | Thu 22 Oct | Front-end: remaining customer pages + staff seat map. |
| 11 | Fri 23 Oct | Deploy (optional, cut first if behind). Test case table with screenshots. |
| 12 | Sat 24 Oct | Report: Abstract, Results, Conclusion, References, Appendices. Export the PDF and submit before evening. |

### Report backlog (deferred, not forgotten)
- Day 1: requirements (use README.md), **ER diagram** (draw.io or dbdiagram.io → `docs/er-diagram/`), schema.
- Day 2: normalization 1NF → BCNF. Point to make: `min_party` was dropped because `table_id → capacity → min_party` is a transitive dependency. Also the functions section.

If behind, cut in this order: optional features → admin page polish → deployment. Never cut: rubric DB objects, the concurrency test, test cases + screenshots, the basic front-end.

---

## Screenshots (`docs/screenshots/`)

| Fig | What | Taken? |
|---|---|---|
| 01 | Schema description (`\d reservation`) | ✅ `fig-01-schema.png` |
| 02 | Seed data: reservations | check |
| 03 | Seed row counts | check |
| 04 | Overlapping booking rejected (`no_double_booking`) | check |
| 05 | Booking inside the 30-minute buffer rejected | check |
| 06 | Booking at 21:30 rejected (`start_on_slot`) | check |
| 07 | Booking ending exactly at the buffer boundary allowed | check |
| — | `allowed_capacities` for party sizes 0–22 | check |
| — | `available_tables`: party 9 at 20:00 (none) vs 13:00 (table 13) | check |
| — | `available_slots`: party 9, 30 Oct (gap from 18:00) | to do |
| — | `seat_map` / `can_cancel` / `book_table` | to do (in the Day 6 test script) |
| — | `book_table` race test (two terminals) | to do (deferred, live) |

Plan: most DB screenshots come from one test script on Day 6 that resets the DB and exercises every object. Frontend screenshots on Days 10–11.
