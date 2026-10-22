package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"time"

	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"

	"github.com/Naman2529/restaurant-booking/backend/internal/api"
	"github.com/Naman2529/restaurant-booking/backend/internal/auth"
	"github.com/Naman2529/restaurant-booking/backend/internal/config"
	"github.com/Naman2529/restaurant-booking/backend/internal/db"
	"github.com/Naman2529/restaurant-booking/backend/internal/mail"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatal(err)
	}

	// ctx is cancelled when you press Ctrl+C, which starts a clean shutdown.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	pool, err := db.Connect(ctx, cfg.DBUser, cfg.DBPassword)
	if err != nil {
		log.Fatal(err)
	}
	defer pool.Close()

	e := echo.New()
	e.HideBanner = true
	e.HTTPErrorHandler = api.ErrorHandler
	e.Use(middleware.Logger())
	e.Use(middleware.Recover())

	// /health proves the chain works (HTTP → pool → Postgres) and shows which
	// role the app is logged in as. It should say booking_app, never postgres.
	e.GET("/health", func(c echo.Context) error {
		var user string
		err := pool.QueryRow(c.Request().Context(), "SELECT current_user").Scan(&user)
		if err != nil {
			return c.JSON(http.StatusServiceUnavailable, map[string]string{"status": "db down"})
		}
		return c.JSON(http.StatusOK, map[string]string{
			"status":  "ok",
			"db_user": user,
		})
	})

	a := &api.API{
		Pool:    pool,
		Tokens:  auth.NewTokens(cfg.JWTSecret, cfg.CookieSecure, auth.PGRevocations{Pool: pool}),
		Mail:    mail.New(cfg.SMTPUser, cfg.SMTPPassword),
		BaseURL: cfg.BaseURL,
	}
	a.Register(e)

	go func() {
		if err := e.Start(":" + cfg.HTTPPort); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatal(err)
		}
	}()

	<-ctx.Done()
	log.Print("shutting down")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := e.Shutdown(shutdownCtx); err != nil {
		log.Print(err)
	}
}
