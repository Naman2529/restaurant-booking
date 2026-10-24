# Terrasse: Restaurant Table Booking

A multi-tenant table booking system for many restaurants and many customers, in which **double-booking is impossible by design**. The rules live in the database itself (an exclusion constraint, CHECK constraints, triggers and procedures), so even a buggy or malicious client can't break them, including when many people book the same table at the same moment.

- **PostgreSQL** does the real work: 7 tables, 19 functions, 13 procedures, 3 triggers and an explicit cursor, grouped into 4 schemas.
- A **Go** REST API (Echo + pgx) is a thin layer over the database: JSON in, `CALL` a procedure, JSON out.
- A **React + TypeScript** front end lets customers pick a table on a floor plan, and gives staff a live, colour-coded seat map.
- Verified under load: **50 concurrent sessions** booking the same slot always yield exactly one booking per table.

---

## Contents

- [The core problem](#the-core-problem)
- [Features](#features)
- [Booking rules](#booking-rules)
- [How the database enforces it](#how-the-database-enforces-it)
- [Architecture](#architecture)
- [Tech stack](#tech-stack)
- [Project structure](#project-structure)
- [Running it locally](#running-it-locally)
- [API reference](#api-reference)
- [Testing and verification](#testing-and-verification)
- [Deploying to production](#deploying-to-production)
- [Known limitations](#known-limitations)

---

## The core problem

A double booking is **two active reservations for the same table whose time periods overlap**.

At small scale this rarely happens. At scale it does. Two customers click "Book" for the last table at the same instant; both requests check the table, both see it free, and both insert a booking. Checking more carefully in application code doesn't help, because the check and the insert are still two separate steps. Terrasse makes that outcome impossible at the database level instead.

---

## Features

### Customers
- Sign up with an email address. A single-use verification link (valid for 24 hours) is emailed, and only **verified** accounts can book.
- Browse restaurants, pick a date and party size (1 to 20), and see the free 30-minute slots.
- Pick the exact table on the restaurant's **floor plan** (only tables of a suitable size can be picked), or let the system choose.
- Get a booking ticket with a QR code and a calendar (`.ics`) download.
- See their bookings and cancel their **own**, no later than **15 minutes** before arrival.

### Restaurant staff
Each restaurant has its own staff logins. Staff only ever see and manage their own restaurant.

| Action | Receptionist | Waiter |
|---|:---:|:---:|
| Seat an arriving party | ✅ | ❌ |
| Free a table (end a sitting) | ✅ | ✅ |
| Mark a no-show | ✅ | ✅ |
| Extend a sitting | ✅ | ✅ |
| Reassign a booking to another table | ✅ | ❌ |
| Run the no-show sweep (mark every overdue booking at once) | ✅ | ✅ |

### Live seat map
The staff panel shows the restaurant's floor plan, refreshed every 30 seconds. Each table's colour is **derived by the database** from the reservation status and the current time. It is never stored.

| Colour | Meaning | Expected staff action |
|---|---|---|
| Green | Free | — |
| Transparent (outlined) | Free now, but a booking arrives within 30 minutes | Don't give it away |
| Gray | Booking time has started, guests haven't arrived | Mark no-show after +15 min |
| Red | Party seated, within their sitting | — |
| Orange | Sitting time is over | Free the table or extend the sitting |

---

## Booking rules

### Tables and assignment
Tables seat 2, 4, 6, 8 or 10. Halls seat 20 and take parties of **11 or more only**. A party gets the smallest table that fits, and may move **at most one size up**. Tables are never split or combined.

| Party size | Normal table | Largest allowed |
|---|---|---|
| 1–2 | 2-seater | 4-seater |
| 3–4 | 4-seater | 6-seater |
| 5–6 | 6-seater | 8-seater |
| 7–8 | 8-seater | 10-seater |
| 9–10 | 10-seater | 10-seater |
| 11–20 | Hall | Hall |
| 21+ | Refused | — |

### Time
- All restaurants use **IST**.
- Bookings start on **30-minute slots** from **07:00 to 21:00**.
- A sitting lasts **2 hours**. After it, the table stays blocked for another **30 minutes** so staff can extend the sitting: a 09:00 booking blocks the table until 11:30.
- Staff can extend a sitting or end it at any minute. Nobody stays past **23:00**.

### Reservation lifecycle

```
booked ──► seated ──► completed
   │
   ├──► cancelled   (customer, 15+ minutes before arrival)
   └──► no_show     (staff, after the start time)
```

Only `booked` and `seated` reservations hold a table. There is no "is free" flag: a table is free whenever no active reservation covers that time.

---

## How the database enforces it

| Rule | Enforced by |
|---|---|
| No overlapping bookings on a table, including the 30-minute buffer, simultaneous requests and extensions | Exclusion constraint `no_double_booking` |
| Opening hours, 30-minute slots, valid sizes and statuses | CHECK constraints |
| Party size fits the table, legal status changes only, timestamps can't be back-dated | Triggers |
| Verified email, table choice, the one-size-up limit | Booking procedures |
| Owner-only cancel, 15-minute cutoff | Cancel procedure |
| Staff role, own restaurant only, seat / extend / reassign windows | Staff procedures (`util.check_staff`) |
| The app can't bypass any of the above | `booking_app` role: no INSERT / UPDATE / DELETE, only `EXECUTE` on the routines |

The guarantee is a single constraint, enforced inside a GiST index for every transaction:

```sql
CONSTRAINT no_double_booking EXCLUDE USING gist (
    table_id WITH =,
    tsrange(lower(period), upper(period) + interval '30 minutes') WITH &&
) WHERE (status IN ('booked', 'seated'))
```

`customer.available_tables` and the floor plan only **advise**, because a table can be taken a millisecond later. The constraint is the real guarantee. `book_table` tries the free tables smallest first. When another session wins a table, it catches the `exclusion_violation` and moves on to the next one, so the customer still gets a table if one is left.

### Database objects, grouped into packages (schemas)

| Schema | Visible to the app | Contents |
|---|---|---|
| `util` | No | `ist_now`, `allowed_capacities`, `table_free`, `check_booking`, `check_staff`, trigger functions |
| `customer` | Yes | `restaurants`, `available_slots`, `available_tables`, `table_availability`, `floor_plan`, `can_cancel`, `my_reservations`, `sign_up`, `verify_email`, `resend_verification`, `book_table`, `book_specific_table`, `cancel_reservation`, … |
| `staff` | Yes | `seat_map`, `day_reservations`, `seat_reservation`, `complete_reservation`, `mark_no_show`, `extend_reservation`, `reassign_table`, `no_show_sweep` (cursor), … |
| `auth` | Yes | `revoke_token`, `is_revoked` (logout) |

Every routine in `customer`, `staff` and `auth` is `SECURITY DEFINER` with a pinned `search_path`. A caller therefore can't hijack it with a same-named temp table or function.

### Data model

| Table | Purpose |
|---|---|
| `restaurant` | A tenant |
| `dining_table` | A numbered table or hall in a restaurant, with its capacity and position on the floor plan |
| `floor_feature` | A labelled part of a floor plan (bar, pond, entrance…), for drawing only |
| `app_user` | A customer account, with email verification |
| `restaurant_staff` | A staff login tied to one restaurant, with a role (receptionist or waiter) |
| `reservation` | One table, one time period (`tsrange`), one customer, one status |
| `revoked_token` | Logged-out session tokens, kept until they would have expired |

The schema is in BCNF. Derived facts (free / taken, seat-map colour, the minimum party for a table) are computed, never stored.

---

## Architecture

```
Browser ── React SPA (Vite, :5173)
   │        same origin via the Vite proxy; HttpOnly + SameSite=Strict JWT cookie
   ▼
Go REST API ── Echo (:8080)
   │        thin handlers: validate JSON → CALL one procedure → map the error → JSON
   │        connects as booking_app (cannot write tables directly)
   ▼
PostgreSQL ── util · customer · staff · auth schemas + 7 tables
```

Design notes:

- **The database is the service layer.** There is no ORM and no business logic in Go. The user id (and, for staff, the restaurant) always comes from the signed token, never from the request body. Staff roles are checked only in the database.
- **Errors carry their HTTP status.** Every `RAISE` uses a custom SQLSTATE whose last three characters are the status, and the API maps it directly. Messages are written for users and shown as they are.

  | Code | Meaning |
  |---|---|
  | `RB404` | Not found. Also used for "not yours", so nobody can probe other people's ids |
  | `RB403` | Not allowed (wrong role, unverified email) |
  | `RB409` | Clash with the current state or time (table taken, too late to cancel…) |
  | `RB422` | Invalid input |

  Postgres's own codes map too (`23P01` → 409, `23514` → 422). Anything unexpected becomes a generic 500, and the details stay in the server log.
- **Times are IST wall-clock strings** (`2026-10-30T19:00`) end to end. They are cast in SQL and never converted through a time zone.
- **Auth:**
  - Passwords are hashed with bcrypt in Go. For unknown emails the server still compares against a dummy hash, so response time doesn't reveal which emails exist.
  - Sessions are JWTs (HS256, 12 hours) in an `HttpOnly`, `SameSite=Strict` cookie. A `Bearer` header is also accepted, for API clients.
  - Logout revokes the token's random `jti`.
  - Verification tokens are 32 random bytes; only their SHA-256 is stored.
  - The verification link opens a React page that calls the API from JavaScript, so email scanners that pre-open links can't use up the single-use token.

---

## Tech stack

| Layer | Choice |
|---|---|
| Database | PostgreSQL 17 (plain SQL + PL/pgSQL; extensions `btree_gist`, `citext`, `pgcrypto`) |
| Back end | Go 1.27, Echo v4, pgx v5, golang-jwt v5, `x/crypto/bcrypt` |
| Front end | React 19, TypeScript, Vite 6, TanStack Query 5, React Router 7, Sonner |
| Email | Gmail SMTP (STARTTLS), or the server log when SMTP isn't configured |

---

## Project structure

```
db/
  schema/       packages.sql (the 4 schemas), schema.sql (tables + constraints)
  seed/         seed.sql: 6 restaurants with floor plans, staff, customers, reservations
  functions/    one file per function
  procedures/   one file per procedure
  cursors/      no_show_sweep.sql
  triggers/     party_fits_table, status_transition, status_timestamps
  roles.sql     booking_app role, SECURITY DEFINER, grants
  reset.sql     rebuilds the whole database in dependency order
  demo/         staff_demo.sql: a busy evening for demoing the seat map
backend/
  cmd/server/   main.go: config → DB pool → Echo → routes
  internal/
    api/        routes, handlers, error mapping
    auth/       JWT, cookies, middleware, bcrypt, logout revocation
    config/     .env loading and validation
    db/         connection pool
    mail/       Gmail sender + log fallback
frontend/
  src/pages/    customer pages (home, restaurant, floor plan, ticket, bookings, auth)
  src/staff/    staff panel (seat map, today's list, table actions)
  src/components/FloorPlan.tsx   shared SVG floor plan
  src/lib/      API client, IST time helpers, session hooks
  public/photos/ restaurant photos + credits.json
```

---

## Running it locally

### Prerequisites

- **PostgreSQL 17** (any recent version with `btree_gist` should work), with `psql` on your `PATH`
- **Go 1.27+**
- **Node.js 20+** and npm

### 1. Clone and configure

```bash
git clone https://github.com/Naman2529/restaurant-booking.git
cd restaurant-booking
cp .env.example .env        # PowerShell: Copy-Item .env.example .env
```

Edit `.env`:

| Variable | Required | Purpose |
|---|---|---|
| `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE` | Yes | A PostgreSQL **superuser** connection, used by `psql` to build the database. The API reuses the host, port and database name |
| `APP_DB_PASSWORD` | Yes | Password for the `booking_app` role. `roles.sql` sets it, and the API logs in with it |
| `JWT_SECRET` | Yes | At least 32 random characters |
| `HTTP_PORT` | No | API port (default `8080`) |
| `APP_BASE_URL` | No | Public URL of the front end, used in verification links. Set it to `http://localhost:5173` for local use |
| `COOKIE_SECURE` | No | `true` when served over HTTPS |
| `SMTP_USER`, `SMTP_PASSWORD` | No | Gmail address and app password. Without them, verification links are printed to the API log |
| `APP_DB_USER` | No | Defaults to `booking_app` |

### 2. Create and build the database

Create the database once, then build everything (schemas, tables, seed data, routines, triggers, roles) with `reset.sql`. psql needs the `.env` values in the environment.

**PowerShell**
```powershell
Get-Content .env | ForEach-Object { if ($_ -match '^\s*([^#=]+)=(.*)$') { Set-Item "env:$($matches[1].Trim())" $matches[2].Trim() } }
createdb restaurant_booking
psql -v ON_ERROR_STOP=1 -f db/reset.sql
```

**bash / zsh**
```bash
set -a; . ./.env; set +a
createdb restaurant_booking
psql -v ON_ERROR_STOP=1 -f db/reset.sql
```

> `reset.sql` **drops and recreates everything**. Run it again any time to get back to the seed data.

### 3. Start the API

```bash
cd backend
go run ./cmd/server          # http://localhost:8080 (loads ../.env itself)
```

`GET http://localhost:8080/health` should return `{"db_user":"booking_app","status":"ok"}`.

### 4. Start the front end

In a second terminal:

```bash
cd frontend
npm install
npx vite                     # http://localhost:5173
```

Vite proxies `/auth`, `/restaurants`, `/reservations`, `/staff` and `/health` to the API, so the browser stays on one origin (the auth cookie needs that; no CORS is configured).

### 5. Try it

Open **http://localhost:5173**. Every seed account uses the password `password123`.

| Account | Email |
|---|---|
| Customer (verified) | `aarav@example.com`, `priya@example.com`, `rohan@example.com` |
| Customer (unverified: can log in but not book) | `meera@example.com` |
| Staff | `reception@<restaurant>.example.com`, `waiter@<restaurant>.example.com` |

The `<restaurant>` part is one of `spiceroute`, `coastalkitchen`, `cafelumiere`, `nonnastable`, `hillsidetea`, `lotuspond`. Staff log in at `/login?as=business`.

**Busy-evening demo.** To see every seat-map colour at once:

```bash
psql -f db/demo/staff_demo.sql   # busy evening at Spice Route, DB clock pinned to 19:20
psql -f db/reset.sql             # undo it afterwards
```

---

## API reference

All bodies are JSON. Errors are always `{"message": "..."}` with a meaningful status (400, 401, 403, 404, 409 or 422).

| Area | Method | Route | Database routine |
|---|---|---|---|
| Auth | POST | `/auth/signup` | `customer.sign_up` |
| | GET | `/auth/verify?token=` | `customer.verify_email` |
| | POST | `/auth/resend` | `customer.resend_verification` |
| | POST | `/auth/{customer,staff}/login` | `customer.login_info` / `staff.login_info` |
| | POST | `/auth/{customer,staff}/logout` | `auth.revoke_token` |
| | GET | `/auth/{customer,staff}/me` | `customer.profile` / `staff.profile` |
| Public | GET | `/restaurants` | `customer.restaurants` |
| | GET | `/restaurants/:id/slots?date=&party=` | `customer.available_slots` |
| | GET | `/restaurants/:id/floor-plan` | `customer.floor_plan` |
| | GET | `/restaurants/:id/tables?start=&party=` | `customer.table_availability` |
| Customer | POST | `/reservations` (optional `table_number`) | `customer.book_table` / `customer.book_specific_table` |
| | GET | `/reservations`, `/reservations/:id` | `customer.my_reservations` |
| | POST | `/reservations/:id/cancel` | `customer.cancel_reservation` |
| Staff | GET | `/staff/seat-map` | `staff.seat_map` |
| | GET | `/staff/reservations?date=` | `staff.day_reservations` |
| | POST | `/staff/reservations/:id/seat` | `staff.seat_reservation` |
| | POST | `/staff/reservations/:id/complete` | `staff.complete_reservation` |
| | POST | `/staff/reservations/:id/no-show` | `staff.mark_no_show` |
| | POST | `/staff/reservations/:id/extend` `{minutes}` | `staff.extend_reservation` |
| | POST | `/staff/reservations/:id/reassign` `{table_number}` | `staff.reassign_table` |
| | POST | `/staff/no-show-sweep` | `staff.no_show_sweep` |

Customer routes need a customer session, and staff routes a staff session. Both are set as a cookie by login, or can be sent as `Authorization: Bearer <token>`.

---

## Testing and verification

The system was verified with a test suite that is kept outside this repository:

- **151 SQL test cases**, one script per area: constraints, functions, customer procedures, staff procedures, triggers, the cursor, and roles and permissions.
  - Each script runs inside `BEGIN … ROLLBACK` with a **pinned clock** (`util.ist_now()` is swapped inside the transaction), so the time-based rules give the same answer whenever the tests run.
  - The roles tests run as `booking_app`. They prove that direct writes, calls into `util` and a `search_path` hijack are all refused.
- **Go unit tests** for error mapping, JWT handling (forged signatures, `alg=none`, wrong session kind), password hashing and mail.
- **A Go concurrency test**: 50 goroutines, each on its own connection as `booking_app`, are released at the same instant to book one slot. Exactly as many succeed as there are fitting tables (1 hall, or 8 small tables), and a direct query confirms no table holds two bookings.

**A real bug found by that test.** Under load, two sessions inserting onto the same table could deadlock inside the exclusion check (`40P01`). `book_table` didn't catch that error, so a customer got an error while a table stayed free. In one run, 36 sessions failed this way and 7 timed out. **No double booking ever happened**: the constraint held, and only availability suffered. The fix locks the table row (`FOR NO KEY UPDATE`) before each insert, so bookings for the same table take turns. A session only ever holds one such lock, so waits can't form a cycle.

---

## Deploying to production

Not deployed yet. What a deployment needs:

1. **One origin for the site and the API.** The cookie is `SameSite=Strict`. Build the front end (`cd frontend && npx vite build` → `frontend/dist`). Then either serve `dist/` and the API behind one reverse proxy that routes `/auth`, `/restaurants`, `/reservations`, `/staff` and `/health` to the Go server, or add a static-file route to the Go server (not built yet) and serve `dist/` from there.
2. **HTTPS**, with `COOKIE_SECURE=true` and `APP_BASE_URL` set to the public URL.
3. **A hosted PostgreSQL** where `psql` can run `db/reset.sql` once, as a role allowed to create roles and extensions (it uses psql `\ir` includes, so migration tools can't run it). **Don't re-run it on live data**: it drops everything.
4. **Secrets** (`JWT_SECRET`, `APP_DB_PASSWORD`, SMTP credentials) from the host's secret store, not a committed file.
5. **A transactional email service** in place of a personal Gmail account (Gmail limits daily sends).

---

## Known limitations

- No manager role: staff accounts are created directly in the database.
- Nothing changes status by itself. Staff mark arrivals, no-shows and freed tables, or run the no-show sweep.
- Once a sitting and its 30-minute buffer have passed, the table no longer blocks new bookings, even if the guests are still there. Staff are expected to extend the sitting.
- One time zone (IST) and the same opening hours for every restaurant.
- Tables can't be combined, so parties larger than 20 can't book. There are no walk-ins without an account.
- No rate limiting on login, sign-up or resend-link.
- `booking_app` can `SELECT` every table, including password hashes. Column-level grants would tighten this.
- Every authenticated request makes one primary-key lookup to check for logout (the cost of revocable JWTs).

**Out of scope:** menus, orders, billing and payments.

---

Built as the BCSE302P Database Systems Lab mini project (VIT Vellore). Restaurant photos are openly licensed; credits are in `frontend/public/photos/credits.json` and in the site footer.
