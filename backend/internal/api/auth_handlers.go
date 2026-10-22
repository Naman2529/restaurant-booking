package api

import (
	"context"
	"errors"
	"log"
	"net/http"
	"strings"

	"github.com/labstack/echo/v4"

	"github.com/Naman2529/restaurant-booking/backend/internal/auth"
	"github.com/Naman2529/restaurant-booking/backend/internal/mail"
)

type signUpRequest struct {
	Email    string `json:"email"`
	FullName string `json:"full_name"`
	Phone    string `json:"phone"`
	Password string `json:"password"`
}

// POST /auth/signup
// The password is hashed here (bcrypt) and only the hash goes to the DB.
// customer.sign_up checks the rest (email shape, name, duplicate email).
func (a *API) signUp(c echo.Context) error {
	var req signUpRequest
	if err := c.Bind(&req); err != nil {
		return err // already a 400
	}

	hash, err := auth.HashPassword(req.Password)
	if errors.Is(err, auth.ErrPasswordLength) {
		return echo.NewHTTPError(http.StatusUnprocessableEntity, err.Error())
	}
	if err != nil {
		return err
	}

	// Empty phone → NULL (the column is optional).
	var phone *string
	if p := strings.TrimSpace(req.Phone); p != "" {
		phone = &p
	}

	email := strings.TrimSpace(req.Email)
	ctx := c.Request().Context()

	var userID int64
	var token string
	err = a.Pool.QueryRow(ctx,
		"CALL customer.sign_up($1, $2, $3, $4, NULL, NULL)",
		email, req.FullName, phone, hash,
	).Scan(&userID, &token)
	if err != nil {
		return err
	}

	// The account exists now, so a failed email doesn't undo it: log it and
	// still answer 201. The user can ask for a new link via /auth/resend.
	// WithoutCancel: keep sending even if the client hangs up.
	link := mail.VerifyLink(a.BaseURL, token)
	if err := a.Mail.SendVerification(context.WithoutCancel(ctx), email, req.FullName, link); err != nil {
		log.Printf("signup: sending verification to user %d failed: %v", userID, err)
	}

	return c.JSON(http.StatusCreated, map[string]any{
		"user_id": userID,
		"message": "account created, check your email for the verification link",
	})
}

// GET /auth/verify?token=...
// This is the link in the email, so it's a GET (see LATER.md for the
// email-scanner caveat).
func (a *API) verifyEmail(c echo.Context) error {
	token := c.QueryParam("token")
	if token == "" {
		return echo.NewHTTPError(http.StatusBadRequest, "token is required")
	}

	var userID int64
	err := a.Pool.QueryRow(c.Request().Context(),
		"CALL customer.verify_email($1, NULL)", token,
	).Scan(&userID)
	if err != nil {
		return err // RB404: invalid, expired or already used
	}

	return c.JSON(http.StatusOK, map[string]string{
		"message": "email verified, you can book tables now",
	})
}

type resendRequest struct {
	Email string `json:"email"`
}

// POST /auth/resend
// Always gives the same answer, so it can't be used to find out which
// emails are registered.
func (a *API) resendVerification(c echo.Context) error {
	var req resendRequest
	if err := c.Bind(&req); err != nil {
		return err
	}
	email := strings.TrimSpace(req.Email)
	ctx := c.Request().Context()

	// NULL token = unknown or already verified email.
	var token *string
	err := a.Pool.QueryRow(ctx,
		"CALL customer.resend_verification($1, NULL)", email,
	).Scan(&token)
	if err != nil {
		return err
	}

	if token != nil {
		link := mail.VerifyLink(a.BaseURL, *token)
		if err := a.Mail.SendVerification(context.WithoutCancel(ctx), email, "there", link); err != nil {
			log.Printf("resend: sending verification failed: %v", err)
		}
	}

	return c.JSON(http.StatusOK, map[string]string{
		"message": "if that email is registered and not verified yet, a new link has been sent",
	})
}
