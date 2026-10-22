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
}
