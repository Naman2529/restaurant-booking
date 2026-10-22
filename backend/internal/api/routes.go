package api

import (
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"

	"github.com/Naman2529/restaurant-booking/backend/internal/auth"
	"github.com/Naman2529/restaurant-booking/backend/internal/mail"
)

// API holds what the handlers need. Handlers stay thin: JSON in → CALL a
// procedure → JSON out. DB errors are returned as-is; ErrorHandler maps them.
type API struct {
	Pool    *pgxpool.Pool
	Tokens  *auth.Tokens
	Mail    mail.Sender
	BaseURL string // where links in emails point
}

// Register adds every route to e.
func (a *API) Register(e *echo.Echo) {
	g := e.Group("/auth")
	g.POST("/signup", a.signUp)
	g.GET("/verify", a.verifyEmail)
	g.POST("/resend", a.resendVerification)

	customer := a.Tokens.Require(auth.KindCustomer)
	g.POST("/customer/login", a.customerLogin)
	g.POST("/customer/logout", a.logout(auth.KindCustomer), customer)
	g.GET("/customer/me", me, customer)

	staff := a.Tokens.Require(auth.KindStaff)
	g.POST("/staff/login", a.staffLogin)
	g.POST("/staff/logout", a.logout(auth.KindStaff), staff)
	g.GET("/staff/me", me, staff)

	// Browsing is public; booking needs a customer login.
	e.GET("/restaurants", a.listRestaurants)
	e.GET("/restaurants/:id/slots", a.listSlots)

	r := e.Group("/reservations", customer)
	r.POST("", a.book)
	r.GET("", a.myReservations)
	r.POST("/:id/cancel", a.cancel)

	// Staff panel. Restaurant and staff id come from the token; the DB
	// checks the role (seat / reassign = receptionist only).
	s := e.Group("/staff", staff)
	s.GET("/seat-map", a.seatMap)
	s.GET("/reservations", a.dayReservations)
	s.POST("/reservations/:id/seat", a.staffAction("seat_reservation", "party seated"))
	s.POST("/reservations/:id/complete", a.staffAction("complete_reservation", "table freed"))
	s.POST("/reservations/:id/no-show", a.staffAction("mark_no_show", "marked as no-show"))
	s.POST("/reservations/:id/extend", a.extend)
	s.POST("/reservations/:id/reassign", a.reassign)
	s.POST("/no-show-sweep", a.noShowSweep)
}
