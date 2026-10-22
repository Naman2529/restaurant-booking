package api

import (
	"net/http"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/labstack/echo/v4"

	"github.com/Naman2529/restaurant-booking/backend/internal/auth"
)

// Times are IST wall-clock with no zone, e.g. "2026-10-30T19:00". They go
// to Postgres as text (cast with ::timestamp) and come back via to_char, so
// Go never turns them into a time.Time that could be shifted to UTC.
const (
	goMinute  = "2006-01-02T15:04"
	sqlMinute = `'YYYY-MM-DD"T"HH24:MI'`
)

// pathID reads the :id part of the URL.
func pathID(c echo.Context) (int64, error) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		return 0, echo.NewHTTPError(http.StatusBadRequest, "id must be a positive number")
	}
	return id, nil
}

type restaurant struct {
	RestaurantID int64   `json:"restaurant_id" db:"restaurant_id"`
	Name         string  `json:"name"          db:"name"`
	Address      *string `json:"address"       db:"address"`
	Phone        *string `json:"phone"         db:"phone"`
}

// GET /restaurants
func (a *API) listRestaurants(c echo.Context) error {
	rows, _ := a.Pool.Query(c.Request().Context(),
		"SELECT restaurant_id, name, address, phone FROM customer.restaurants()")
	list, err := pgx.CollectRows(rows, pgx.RowToStructByName[restaurant])
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, list)
}

type slot struct {
	Start      string `json:"start"       db:"start"`
	FreeTables int    `json:"free_tables" db:"free_tables"`
}

// GET /restaurants/:id/slots?date=2026-10-30&party=4
// Only bookable starts are listed (future, at least one table fits).
func (a *API) listSlots(c echo.Context) error {
	id, err := pathID(c)
	if err != nil {
		return err
	}

	date := c.QueryParam("date")
	if _, err := time.Parse("2006-01-02", date); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, "date must look like 2026-10-30")
	}

	// 1–20 mirrors the reservation CHECK. Without it, party=25 would just
	// show "no slots" instead of saying why.
	party, err := strconv.Atoi(c.QueryParam("party"))
	if err != nil || party < 1 || party > 20 {
		return echo.NewHTTPError(http.StatusUnprocessableEntity, "party must be 1 to 20")
	}

	rows, _ := a.Pool.Query(c.Request().Context(),
		"SELECT to_char(slot_start, "+sqlMinute+") AS start, free_tables "+
			"FROM customer.available_slots($1, $2::date, $3)",
		id, date, party)
	list, err := pgx.CollectRows(rows, pgx.RowToStructByName[slot])
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, list)
}

type bookRequest struct {
	RestaurantID int64  `json:"restaurant_id"`
	Start        string `json:"start"`
	PartySize    int    `json:"party_size"`
}

// POST /reservations (customer)
// The user comes from the token, never the body. book_table does the rest:
// verified email, future start, picking a table, and the double-booking
// retry. Its errors (403 / 409 / 422) come back through ErrorHandler.
func (a *API) book(c echo.Context) error {
	var req bookRequest
	if err := c.Bind(&req); err != nil {
		return err
	}
	if _, err := time.Parse(goMinute, req.Start); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, "start must look like 2026-10-30T19:00")
	}

	var reservationID int64
	err := a.Pool.QueryRow(c.Request().Context(),
		"CALL customer.book_table($1, $2, $3::timestamp, $4, NULL)",
		auth.From(c).SubjectID(), req.RestaurantID, req.Start, req.PartySize,
	).Scan(&reservationID)
	if err != nil {
		return err
	}

	return c.JSON(http.StatusCreated, map[string]any{
		"reservation_id": reservationID,
		"message":        "table booked",
	})
}

type reservation struct {
	ReservationID  int64  `json:"reservation_id"  db:"reservation_id"`
	RestaurantID   int64  `json:"restaurant_id"   db:"restaurant_id"`
	RestaurantName string `json:"restaurant_name" db:"restaurant_name"`
	TableNumber    int    `json:"table_number"    db:"table_number"`
	PartySize      int    `json:"party_size"      db:"party_size"`
	StartsAt       string `json:"starts_at"       db:"starts_at"`
	EndsAt         string `json:"ends_at"         db:"ends_at"`
	Status         string `json:"status"          db:"status"`
	CanCancel      bool   `json:"can_cancel"      db:"can_cancel"`
}

// GET /reservations (customer): my reservations, newest first.
func (a *API) myReservations(c echo.Context) error {
	rows, _ := a.Pool.Query(c.Request().Context(),
		"SELECT reservation_id, restaurant_id, restaurant_name, table_number, party_size, "+
			"to_char(starts_at, "+sqlMinute+") AS starts_at, "+
			"to_char(ends_at, "+sqlMinute+") AS ends_at, "+
			"status, can_cancel "+
			"FROM customer.my_reservations($1)",
		auth.From(c).SubjectID())
	list, err := pgx.CollectRows(rows, pgx.RowToStructByName[reservation])
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, list)
}

// POST /reservations/:id/cancel (customer)
// It's a POST, not a DELETE: the row stays, its status becomes cancelled.
// Someone else's reservation answers 404, same as a missing one.
func (a *API) cancel(c echo.Context) error {
	id, err := pathID(c)
	if err != nil {
		return err
	}

	_, err = a.Pool.Exec(c.Request().Context(),
		"CALL customer.cancel_reservation($1, $2)", id, auth.From(c).SubjectID())
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, map[string]string{"message": "reservation cancelled"})
}
