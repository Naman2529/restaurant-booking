package api

import (
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/labstack/echo/v4"
)

// ErrorHandler replaces Echo's default one. Handlers just `return err` from a
// CALL, and the client gets the right status with the procedure's message.
// Errors that aren't from the database pass through unchanged.
func ErrorHandler(err error, c echo.Context) {
	c.Echo().DefaultHTTPErrorHandler(toHTTP(err), c)
}

// toHTTP turns a Postgres error into an *echo.HTTPError.
//
//	RBxxx  our own codes (USING ERRCODE): status = the last 3 digits,
//	       message = the procedure's message, written for users, no ids
//	23P01  exclusion_violation (no_double_booking) → 409
//	23505  unique_violation → 409
//	23514  check_violation → 422
//	other  → 500, message hidden; the full error only goes to the server log
func toHTTP(err error) error {
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) {
		return err
	}

	if code, ok := strings.CutPrefix(pgErr.Code, "RB"); ok {
		if status, err := strconv.Atoi(code); err == nil && status >= 400 && status <= 599 {
			return echo.NewHTTPError(status, pgErr.Message)
		}
	}

	switch pgErr.Code {
	case "23P01":
		return echo.NewHTTPError(http.StatusConflict, "that table is already booked for this time")
	case "23505":
		return echo.NewHTTPError(http.StatusConflict, "already exists")
	case "23514":
		return echo.NewHTTPError(http.StatusUnprocessableEntity, "value not allowed")
	}

	// No message given, so Echo answers "Internal Server Error". The Logger
	// middleware still prints the original error (with the SQLSTATE).
	return echo.NewHTTPError(http.StatusInternalServerError).SetInternal(err)
}
