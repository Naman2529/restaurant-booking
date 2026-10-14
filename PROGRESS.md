# Progress

Session handoff file. Read this first in a new session, then README.md (rules) and LATER.md (deferred items).

**Last updated:** Thu 15 Oct 2026, early morning (end of the Wed 14 Oct session).
**Deadline:** Sat 24 Oct, 11:59 PM. Aim to submit 23 Oct.
**Status:** Day 1 code done. Day 2 functions 4 of 6 done. About half a day behind.

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
- Gitignored: `LATER.md`, `PROJECT_PLAN.md`, `.env`. `docs/screenshots/` is tracked on purpose.

---

## Done

| File | What | Status |
|---|---|---|
| `db/schema/schema.sql` | 5 tables, CHECKs, exclusion constraint | Run and tested |
| `db/seed/seed.sql` | 2 restaurants, 23 tables, 4 users (Meera unverified), 4 staff, 7 reservations covering every status | Run |
| `db/functions/01_ist_now.sql` | `ist_now()`: current IST as a plain `timestamp` | Run and tested |
| `db/functions/02_allowed_capacities.sql` | `allowed_capacities(party)`: allowed table sizes as `int[]`, smallest first | Written, test shown |
| `db/functions/03_available_tables.sql` | `available_tables(restaurant, start, party)`: free tables, best fit first | Run and tested |
| `db/functions/04_available_slots.sql` | `available_slots(restaurant, date, party)`: bookable 30-minute slots with a free-table count | **Written, not yet confirmed run** |

Reset the database at any time with: `schema.sql` → `seed.sql` → every file in `db/functions/` in order.

### Key schema facts
- `reservation.period` is a `tsrange` in IST wall-clock time, stored as `[start, end)`. Default sitting is 2 hours, and staff can extend it.
- Exclusion constraint `no_double_booking`: same `table_id` + overlapping `tsrange(lower, upper + 30 min)`, `WHERE status IN ('booked','seated')`.
- CHECKs: `period_shape`, `start_on_slot` (:00/:30, 07:00–21:00), `end_by_2300`.
- No `min_party` column. Halls are `capacity = 20` and take parties of 11+ only. That rule lives in `allowed_capacities`.
- Seat-map colours are **derived, never stored**.
- Passwords are bcrypt via pgcrypto `crypt(.., gen_salt('bf'))`. All seed passwords are `password123`.

---

## Next Up (pick up here)

1. **Run and test function 4** (`available_slots`). For Spice Route, 30 Oct, party 9, expect slots 07:00–17:30 and nothing from 18:00 on.
2. **Function 5: `seat_map(restaurant)`** returns every table with its current state, using `ist_now()`:
   - green = free, no booking starting within 30 minutes
   - transparent (bordered) = free, but a booked reservation starts within the next 30 minutes
   - gray = booked, start time has passed, not seated
   - red = seated, now before the period's end
   - orange = seated, now past the period's end
   - It should also return the reservation id so the staff UI can act on it.
3. **Function 6: `can_cancel(reservation, user)`** returns a boolean: the user owns it, the status is `booked`, and `ist_now()` is at least 15 minutes before the start.
4. Commit and push.

### Reminders for later steps
- **The booking procedure must reject past start times** (`start > ist_now()`). The CHECKs only validate time of day, not the date.
- The booking procedure must also check: email verified, party size has allowed capacities, and handle the exclusion violation (SQLSTATE `23P01`) when the race is lost.
- `available_tables` is advisory. The exclusion constraint is the real guarantee (report point).
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
