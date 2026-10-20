# Progress

Session handoff file. Read this first in a new session, then README.md (rules) and LATER.md (deferred items).

**Last updated:** Tue 20 Oct 2026.
**Deadline:** Sat 24 Oct, 11:59 PM. Aim to submit 23 Oct.
**Status:** Days 1–2 done (all 6 functions + `check_staff` helper). Day 3 booking procedure done; race test deferred. Day 4: 4 of 6 procedures tested, `extend_reservation` written, `reassign_table` left. Calendar says Day 8, so about 5 days behind. Original schedule kept; user is catching up.

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
| `db/procedures/extend_reservation.sql` | `extend_reservation(reservation, staff, extra interval)`: both roles; seated only; pushes `upper(period)`; friendly errors on `23P01` (next booking) and `end_by_2300` | **Written, not yet run** |

**Load order (files have no number prefixes, so run them in exactly this order): `schema.sql` → `seed.sql` → `ist_now` → `check_staff` → `allowed_capacities` → `available_tables` → `available_slots` → `seat_map` → `can_cancel` → `book_table` → `cancel_reservation` → `seat_reservation` → `complete_reservation` → `mark_no_show` → `extend_reservation`.**

### Key schema facts
- `reservation.period` is a `tsrange` in IST wall-clock time, stored as `[start, end)`. Default sitting is 2 hours, and staff can extend it.
- Exclusion constraint `no_double_booking`: same `table_id` + overlapping `tsrange(lower, upper + 30 min)`, `WHERE status IN ('booked','seated')`.
- CHECKs: `period_shape`, `start_on_slot` (:00/:30, 07:00–21:00), `end_by_2300`.
- No `min_party` column. Halls are `capacity = 20` and take parties of 11+ only. That rule lives in `allowed_capacities`.
- Seat-map colours are **derived, never stored**.
- Passwords are bcrypt via pgcrypto `crypt(.., gen_salt('bf'))`. All seed passwords are `password123`.

---

## Next Up (pick up here)

1. **Run and test `extend_reservation`** (happy path, clash with next booking, past 23:00, not seated).
2. **`reassign_table(reservation, staff, new table)`**: receptionist only; move to another table at the same restaurant; exclusion constraint guards clashes. Add to load order.
3. Commit + push. Then Day 5: triggers.

### Reminders for later steps
- **Deferred: `book_table` race test** (📸 live, two terminals). Steps are in LATER.md.
- `CALL` arguments can't contain subqueries. Pass plain ids (that's how Go will call it anyway). `lastval()` is fine (e.g. `CALL seat_reservation(lastval(), 2)` right after `book_table`).
- Seed staff ids: 1 = Spice Route waiter, 2 = Spice Route receptionist, 3 = Coastal waiter, 4 = Coastal receptionist. Users: 1 Aarav, 2 Priya, 3 Rohan, 4 Meera (unverified). Restaurants: 1 Spice Route, 2 Coastal Kitchen.
- Time-sensitive tests: insert directly inside `BEGIN … ROLLBACK` to get a booking whose start has passed (`book_table` rejects past starts).
- `available_tables` is advisory. The exclusion constraint is the real guarantee (report point).
- Postgres burns identity numbers on failed / rolled-back inserts, so reservation ids have gaps. Normal.
- **Day 6 "packages"** = Postgres schemas used as namespaces (faculty accepted this).
- **Day 7:** the Go app should connect as a **limited DB role** (can execute procedures, can't alter tables), not as `postgres`. Also choose a migration tool (golang-migrate or goose), which replaces the DROP-and-recreate approach.

---

## Day-by-Day Remaining

| Day | Date | Plan |
|---|---|---|
| 2 (finish) + 3 | **Thu 15 Oct** | Functions 5 and 6. **Booking procedure** (verified email, future start, pick from `available_tables`, insert, handle `23P01`). Race test with two psql terminals. 📸 |
| 4 | Fri 16 Oct | Procedures: cancel (owner + 15-minute rule), seat, complete/free, no-show, extend, reassign. Role checks: seat = receptionist; free / no-show / extend = both; reassign = receptionist. Legal status transitions only. |
| 5 | Sat 17 Oct | Triggers. Candidates: party fits table capacity (incl. halls 11+), block illegal status transitions, auto-set `seated_at` / `cancelled_at`. |
| 6 | Sun 18 Oct | A cursor with a real row-by-row job. Group objects into schemas ("packages"). Test every object. **DB layer done.** |
| 7 | Mon 19 Oct | Go foundation: Echo + pgx, config from `.env`, DB pool, first routes, migration tool. |
| 8 | Tue 20 Oct | All routes, map DB errors to HTTP, customer and staff auth (bcrypt). |
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
