package api

import (
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/labstack/echo/v4"

	"github.com/Naman2529/restaurant-booking/backend/internal/auth"
)

// Every staff route takes the staff id and restaurant from the token. The
// role (receptionist / waiter) is NOT checked here: util.check_staff in the
// database is the one place that decides who may do what.

type seatMapTable struct {
	TableNumber   int     `json:"table_number"   db:"table_number"`
	Capacity      int     `json:"capacity"       db:"capacity"`
	Colour        string  `json:"colour"         db:"colour"`
	ReservationID *int64  `json:"reservation_id" db:"reservation_id"`
	StartsAt      *string `json:"starts_at"      db:"starts_at"`
	EndsAt        *string `json:"ends_at"        db:"ends_at"`
}

// GET /staff/seat-map
// Colours are worked out in the database from status + time, never stored.
func (a *API) seatMap(c echo.Context) error {
	rows, _ := a.Pool.Query(c.Request().Context(),
		"SELECT table_number, capacity, colour, reservation_id, "+
			"to_char(lower(period), "+sqlMinute+") AS starts_at, "+
			"to_char(upper(period), "+sqlMinute+") AS ends_at "+
			"FROM staff.seat_map($1)",
		auth.From(c).RestaurantID)
	list, err := pgx.CollectRows(rows, pgx.RowToStructByName[seatMapTable])
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, list)
}

type staffReservation struct {
	ReservationID int64   `json:"reservation_id" db:"reservation_id"`
	TableNumber   int     `json:"table_number"   db:"table_number"`
	Capacity      int     `json:"capacity"       db:"capacity"`
	PartySize     int     `json:"party_size"     db:"party_size"`
	CustomerName  string  `json:"customer_name"  db:"customer_name"`
	CustomerPhone *string `json:"customer_phone" db:"customer_phone"`
	StartsAt      string  `json:"starts_at"      db:"starts_at"`
	EndsAt        string  `json:"ends_at"        db:"ends_at"`
	Status        string  `json:"status"         db:"status"`
}

// GET /staff/reservations?date=2026-10-30 (no date = today in IST)
func (a *API) dayReservations(c echo.Context) error {
	date := c.QueryParam("date")
	if date != "" {
		if _, err := time.Parse("2006-01-02", date); err != nil {
			return echo.NewHTTPError(http.StatusBadRequest, "date must look like 2026-10-30")
		}
	}

	// An empty date means today in IST. util.ist_now() is hidden from
	// booking_app, so the same expression is written out here.
	rows, _ := a.Pool.Query(c.Request().Context(),
		"SELECT reservation_id, table_number, capacity, party_size, customer_name, customer_phone, "+
			"to_char(starts_at, "+sqlMinute+") AS starts_at, "+
			"to_char(ends_at, "+sqlMinute+") AS ends_at, status "+
			"FROM staff.day_reservations($1, coalesce(NULLIF($2, '')::date, (now() AT TIME ZONE 'Asia/Kolkata')::date))",
		auth.From(c).RestaurantID, date)
	list, err := pgx.CollectRows(rows, pgx.RowToStructByName[staffReservation])
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, list)
}

// staffAction returns a handler for the simple POST /staff/reservations/:id/<action>
// routes: they all CALL one procedure with (reservation_id, staff_id).
func (a *API) staffAction(procedure, done string) echo.HandlerFunc {
	return func(c echo.Context) error {
		id, err := pathID(c)
		if err != nil {
			return err
		}
		_, err = a.Pool.Exec(c.Request().Context(),
			"CALL staff."+procedure+"($1, $2)", id, auth.From(c).SubjectID())
		if err != nil {
			return err
		}
		return c.JSON(http.StatusOK, map[string]string{"message": done})
	}
}

type extendRequest struct {
	Minutes int `json:"minutes"`
}

// POST /staff/reservations/:id/extend {"minutes": 30}
// extend_reservation rejects non-positive values and anything past 23:00.
func (a *API) extend(c echo.Context) error {
	id, err := pathID(c)
	if err != nil {
		return err
	}
	var req extendRequest
	if err := c.Bind(&req); err != nil {
		return err
	}

	_, err = a.Pool.Exec(c.Request().Context(),
		"CALL staff.extend_reservation($1, $2, make_interval(mins => $3))",
		id, auth.From(c).SubjectID(), req.Minutes)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, map[string]string{"message": "sitting extended"})
}

type reassignRequest struct {
	TableNumber int `json:"table_number"`
}

// POST /staff/reservations/:id/reassign {"table_number": 7}
// Takes the table NUMBER staff see; the procedure finds it in their restaurant.
func (a *API) reassign(c echo.Context) error {
	id, err := pathID(c)
	if err != nil {
		return err
	}
	var req reassignRequest
	if err := c.Bind(&req); err != nil {
		return err
	}

	_, err = a.Pool.Exec(c.Request().Context(),
		"CALL staff.reassign_table($1, $2, $3)",
		id, auth.From(c).SubjectID(), req.TableNumber)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, map[string]string{"message": "reservation moved"})
}

// POST /staff/no-show-sweep
// Runs the cursor procedure: every booking 15+ minutes past its start that
// nobody seated becomes a no-show. One bad row is skipped, not fatal.
func (a *API) noShowSweep(c echo.Context) error {
	cl := auth.From(c)
	var marked, skipped int
	err := a.Pool.QueryRow(c.Request().Context(),
		"CALL staff.no_show_sweep($1, $2, NULL, NULL)",
		cl.RestaurantID, cl.SubjectID(),
	).Scan(&marked, &skipped)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, map[string]int{"marked": marked, "skipped": skipped})
}
