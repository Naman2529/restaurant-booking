package api

import (
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/labstack/echo/v4"
)

// handle runs err through ErrorHandler and returns the status and body.
func handle(err error) (int, string) {
	rec := httptest.NewRecorder()
	c := echo.New().NewContext(httptest.NewRequest(http.MethodGet, "/", nil), rec)
	ErrorHandler(err, c)
	return rec.Code, rec.Body.String()
}

func pg(code, msg string) error {
	return &pgconn.PgError{Code: code, Message: msg}
}

func TestErrorHandler(t *testing.T) {
	cases := []struct {
		name     string
		err      error
		wantCode int
		wantBody string
	}{
		{"RB404", pg("RB404", "reservation not found"), 404, "reservation not found"},
		{"RB403", pg("RB403", "verify your email before booking"), 403, "verify your email"},
		{"RB409", pg("RB409", "no table free"), 409, "no table free"},
		{"RB422", pg("RB422", "start time is in the past"), 422, "start time is in the past"},
		{"wrapped RB404", fmt.Errorf("cancel: %w", pg("RB404", "reservation not found")), 404, "reservation not found"},
		{"bad RB code", pg("RBXYZ", "oops"), 500, "Internal Server Error"},
		{"23P01", pg("23P01", `conflicting key value violates exclusion constraint "no_double_booking"`), 409, "already booked"},
		{"23505", pg("23505", "duplicate key"), 409, "already exists"},
		{"23514", pg("23514", `violates check constraint "start_on_slot"`), 422, "value not allowed"},
		{"other pg error", pg("42P01", `relation "secret_table" does not exist`), 500, "Internal Server Error"},
		{"plain Go error", errors.New("boom"), 500, "Internal Server Error"},
		{"echo HTTP error", echo.NewHTTPError(401, "missing token"), 401, "missing token"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			code, body := handle(tc.err)
			if code != tc.wantCode {
				t.Fatalf("status: got %d, want %d (body %s)", code, tc.wantCode, body)
			}
			if !strings.Contains(body, tc.wantBody) {
				t.Fatalf("body %s should contain %q", body, tc.wantBody)
			}
		})
	}
}

// A 500 must never show the database's own message to the client.
func TestUnknownDBErrorHidden(t *testing.T) {
	_, body := handle(pg("42P01", `relation "secret_table" does not exist`))
	if strings.Contains(body, "secret_table") {
		t.Fatalf("DB detail leaked to client: %s", body)
	}
}
