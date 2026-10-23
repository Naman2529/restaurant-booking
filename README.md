# Restaurant Booking System

A multi-tenant table booking system for many restaurants and many customers, where **double-booking is impossible by design**. The rules live in the database itself (constraints, triggers and procedures), so even a buggy or malicious client can't break them, including when many people book the same table at the same moment.

> Status: in progress. Built as a Database Systems Lab mini project and a portfolio project.

---

## The Core Problem

A double-booking is **two active reservations for the same table whose time periods overlap**.

At small scale this rarely happens. At scale it does: two customers click "Book" for the last table at the same instant, both requests see the table as free, and both succeed. This project makes that outcome impossible at the database level rather than relying on application code to get it right.

---

## Features

### Customers
- Sign up with an email address. Only **verified** emails can make reservations.
- Book a table at a restaurant for a party of 1 to 20, either picking the exact table on the restaurant's floor plan (only tables of the right size can be picked) or letting the system choose.
- Cancel their **own** reservations only, and no later than **15 minutes before** arrival.

### Restaurant staff
Each restaurant has its own staff logins. Staff only ever see and manage their own restaurant.

| Action | Receptionist | Waiter |
|---|:---:|:---:|
| Seat an arriving party | ✅ | ❌ |
| Free a table (end a sitting) | ✅ | ✅ |
| Mark a no-show | ✅ | ✅ |
| Extend a sitting | ✅ | ✅ |
| Reassign a booking to another table | ✅ | ❌ |

### Seat map
The staff panel shows each restaurant's tables as a grid of numbered squares, like a cinema seat picker:

| Colour | Meaning | Expected staff action |
|---|---|---|
| Green | Free | — |
| Transparent (bordered) | Free now, but a booking arrives within 30 minutes | Don't give it away |
| Gray | Booking time has started, guests haven't arrived | Mark no-show by +15 min |
| Red | Party seated, within their sitting | — |
| Orange | Sitting time is over | Free the table or extend the sitting |

Colours are worked out from the reservation status and the current time. They are never stored.

---

## Booking Rules

### Tables
Every restaurant has numbered tables of these sizes:

- 2, 4, 6, 8 and 10 seaters
- Halls with capacity 20, for parties of **11 or more only**

### Table assignment
A party gets the smallest table that fits. If none is free, it may move **at most one size up**. Tables are never split or combined.

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
- Bookings start on **30-minute slots** (07:00, 07:30, …), from **07:00 to 21:00**. 21:00 is the last booking.
- A sitting lasts **2 hours** by default. Customers only ever see a start time.
- After each sitting, the table stays blocked for another **30 minutes** to leave room for an extension. For example, a 09:00 booking blocks 11:00, and the next booking can start at 11:30.
- Staff can extend a sitting, or end it at any minute. Bookings still only start on 30-minute slots.
- No one stays past **23:00**.

### Reservation lifecycle

```
booked ──► seated ──► completed
   │
   ├──► cancelled   (by the customer, 15+ minutes before arrival)
   └──► no_show     (by staff)
```

Only **booked** and **seated** reservations hold a table. A table is free whenever it has no active reservation covering that time. There is no "is free" flag.

---

## How the Database Enforces It

| Rule | Enforced by |
|---|---|
| No overlapping bookings on a table, including the 30-minute buffer, simultaneous requests, and extensions | Exclusion constraint |
| Opening hours, 30-minute slots, valid sizes and statuses | CHECK constraints |
| Party size fits the table | Trigger |
| Verified email, table assignment and the upgrade limit | Booking procedure |
| Owner-only cancel, 15-minute cutoff | Cancel procedure |
| Staff role permissions, status changes, extend, reassign | Staff procedures |

## Data Model

| Entity | Purpose |
|---|---|
| `restaurant` | A tenant |
| `dining_table` | A numbered table or hall in a restaurant, with its capacity and its position on the floor plan |
| `floor_feature` | A labelled part of a restaurant's floor plan (bar, pond, entrance...), for drawing only |
| `app_user` | A customer account, with email verification |
| `restaurant_staff` | A staff login tied to one restaurant, with a role (receptionist or waiter) |
| `reservation` | A booking of one table for one time period by one customer, with a status |

---

## Tech Stack

| Layer | Choice |
|---|---|
| Database | PostgreSQL (plain SQL + PL/pgSQL, no ORM) |
| Backend | Go, Echo, pgx |
| Front-end | React + TypeScript (Vite), TanStack Query, React Router |
| Hosting | Local (Go API on :8080, Vite on :5173 proxying the API) |

### Running it

```powershell
psql -f db/reset.sql                 # build the database (load .env first)
cd backend;  go run ./cmd/server     # API on http://localhost:8080
cd frontend; npm install; npx vite   # site on http://localhost:5173
.\run_tests.ps1                      # every database + Go test
```

---

## Known Limitations

- Restaurant staff accounts are created directly in the database. There is no manager role or staff admin panel yet.
- Nothing changes status by itself over time. Staff mark arrivals, no-shows and freed tables manually.
- Once a sitting and its 30-minute buffer have passed, the table no longer blocks new bookings, even if guests are still there. Staff are expected to extend the sitting.
- All restaurants share one time zone (IST) and the same opening hours.
- Tables cannot be split or combined, so parties larger than 20 can't be booked.

## Out of Scope

Menus, orders, billing and payments.
