package api

import (
	"context"
	"errors"
	"log"
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5"
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

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// errBadLogin is the one answer for unknown email and wrong password alike,
// so a login attempt can't tell which emails are registered.
var errBadLogin = echo.NewHTTPError(http.StatusUnauthorized, "wrong email or password")

// POST /auth/customer/login
// The token goes in the cookie (browsers) and in the body (curl / tests,
// sent back as "Authorization: Bearer ...").
func (a *API) customerLogin(c echo.Context) error {
	var req loginRequest
	if err := c.Bind(&req); err != nil {
		return err
	}

	var (
		userID   int64
		fullName string
		verified bool
		hash     string
	)
	err := a.Pool.QueryRow(c.Request().Context(),
		"SELECT user_id, full_name, email_verified, password_hash FROM customer.login_info($1)",
		strings.TrimSpace(req.Email),
	).Scan(&userID, &fullName, &verified, &hash)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}

	// No row → hash stays "" and CheckPassword still does a full bcrypt
	// compare, so unknown emails take as long as wrong passwords.
	if !auth.CheckPassword(hash, req.Password) {
		return errBadLogin
	}

	token, err := a.Tokens.IssueCustomer(userID)
	if err != nil {
		return err
	}
	a.Tokens.SetCookie(c, auth.KindCustomer, token)

	return c.JSON(http.StatusOK, map[string]any{
		"token": token,
		"user": map[string]any{
			"user_id":        userID,
			"full_name":      fullName,
			"email_verified": verified,
		},
	})
}

// POST /auth/staff/login
// restaurant_id and role go into the token; staff routes read them from
// there, never from the request.
func (a *API) staffLogin(c echo.Context) error {
	var req loginRequest
	if err := c.Bind(&req); err != nil {
		return err
	}

	var (
		staffID      int64
		restaurantID int64
		fullName     string
		role         string
		hash         string
	)
	err := a.Pool.QueryRow(c.Request().Context(),
		"SELECT staff_id, restaurant_id, full_name, role, password_hash FROM staff.login_info($1)",
		strings.TrimSpace(req.Email),
	).Scan(&staffID, &restaurantID, &fullName, &role, &hash)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}

	if !auth.CheckPassword(hash, req.Password) {
		return errBadLogin
	}

	token, err := a.Tokens.IssueStaff(staffID, restaurantID, role)
	if err != nil {
		return err
	}
	a.Tokens.SetCookie(c, auth.KindStaff, token)

	return c.JSON(http.StatusOK, map[string]any{
		"token": token,
		"staff": map[string]any{
			"staff_id":      staffID,
			"restaurant_id": restaurantID,
			"full_name":     fullName,
			"role":          role,
		},
	})
}

// logout returns the handler for POST /auth/<kind>/logout (behind Require).
// Revoking blocks this token everywhere, not just in this browser.
func (a *API) logout(kind string) echo.HandlerFunc {
	return func(c echo.Context) error {
		if err := a.Tokens.Revoke(c.Request().Context(), auth.From(c)); err != nil {
			return err
		}
		a.Tokens.ClearCookie(c, kind)
		return c.JSON(http.StatusOK, map[string]string{"message": "logged out"})
	}
}

type customerProfile struct {
	UserID        int64   `json:"id"             db:"user_id"`
	FullName      string  `json:"full_name"      db:"full_name"`
	Email         string  `json:"email"          db:"email"`
	Phone         *string `json:"phone"          db:"phone"`
	EmailVerified bool    `json:"email_verified" db:"email_verified"`
}

type staffProfile struct {
	StaffID        int64  `json:"id"              db:"staff_id"`
	FullName       string `json:"full_name"       db:"full_name"`
	Email          string `json:"email"           db:"email"`
	Role           string `json:"role"            db:"role"`
	RestaurantID   int64  `json:"restaurant_id"   db:"restaurant_id"`
	RestaurantName string `json:"restaurant_name" db:"restaurant_name"`
}

// GET /auth/<kind>/me (behind Require)
// The cookie is HttpOnly, so the front end asks here who is logged in. The
// name, verified flag and restaurant come from the database, so they're
// current (e.g. right after the verify link is clicked).
func (a *API) me(c echo.Context) error {
	cl := auth.From(c)
	ctx := c.Request().Context()

	var out any
	var err error
	if cl.Kind == auth.KindStaff {
		rows, _ := a.Pool.Query(ctx,
			"SELECT staff_id, full_name, email::text AS email, role, restaurant_id, restaurant_name FROM staff.profile($1)",
			cl.SubjectID())
		var p staffProfile
		p, err = pgx.CollectExactlyOneRow(rows, pgx.RowToStructByName[staffProfile])
		out = struct {
			Kind string `json:"kind"`
			staffProfile
		}{cl.Kind, p}
	} else {
		rows, _ := a.Pool.Query(ctx,
			"SELECT user_id, full_name, email::text AS email, phone, email_verified FROM customer.profile($1)",
			cl.SubjectID())
		var p customerProfile
		p, err = pgx.CollectExactlyOneRow(rows, pgx.RowToStructByName[customerProfile])
		out = struct {
			Kind string `json:"kind"`
			customerProfile
		}{cl.Kind, p}
	}
	// A valid token for an account that no longer exists.
	if errors.Is(err, pgx.ErrNoRows) {
		return echo.NewHTTPError(http.StatusUnauthorized, "account not found")
	}
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, out)
}
