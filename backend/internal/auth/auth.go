package auth

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/labstack/echo/v4"
)

const (
	KindCustomer = "customer"
	KindStaff    = "staff"

	tokenTTL  = 12 * time.Hour
	claimsKey = "claims"
)

// Claims is what a token says about its holder. Subject holds the
// user_id (customer) or staff_id (staff). ID (the JWT "jti") is a random
// id for this one token, used to revoke it at logout. RestaurantID and
// Role are only set for staff, so staff routes never trust a restaurant
// id sent by the client.
type Claims struct {
	Kind         string `json:"kind"`
	RestaurantID int64  `json:"rid,omitempty"`
	Role         string `json:"role,omitempty"`
	jwt.RegisteredClaims
}

// SubjectID returns the user_id or staff_id stored in Subject.
func (c *Claims) SubjectID() int64 {
	id, _ := strconv.ParseInt(c.Subject, 10, 64)
	return id
}

// RevocationStore remembers logged-out tokens. The real one is in the
// database (PGRevocations); tests use an in-memory one.
type RevocationStore interface {
	Revoke(ctx context.Context, jti string, expiresAt time.Time) error
	IsRevoked(ctx context.Context, jti string) (bool, error)
}

// Tokens signs and checks JWTs with one secret (HS256), sets the cookie
// that carries them in a browser, and revokes them at logout.
type Tokens struct {
	secret       []byte
	secureCookie bool
	revoked      RevocationStore
}

func NewTokens(secret string, secureCookie bool, revoked RevocationStore) *Tokens {
	return &Tokens{secret: []byte(secret), secureCookie: secureCookie, revoked: revoked}
}

// cookieName is per kind (rb_customer / rb_staff), so a customer login and
// a staff login in the same browser don't overwrite each other.
func cookieName(kind string) string {
	return "rb_" + kind
}

// SetCookie stores the token in an HttpOnly cookie. JavaScript can't read it,
// so an XSS bug can't steal the token. SameSite=Strict stops other sites from
// sending it along with forged requests (CSRF).
func (t *Tokens) SetCookie(c echo.Context, kind, token string) {
	c.SetCookie(&http.Cookie{
		Name:     cookieName(kind),
		Value:    token,
		Path:     "/",
		MaxAge:   int(tokenTTL.Seconds()),
		HttpOnly: true,
		Secure:   t.secureCookie,
		SameSite: http.SameSiteStrictMode,
	})
}

// ClearCookie tells the browser to delete the cookie. Logout also calls
// Revoke, so a copy of the token kept elsewhere stops working too.
func (t *Tokens) ClearCookie(c echo.Context, kind string) {
	c.SetCookie(&http.Cookie{
		Name:     cookieName(kind),
		Value:    "",
		Path:     "/",
		MaxAge:   -1,
		HttpOnly: true,
		Secure:   t.secureCookie,
		SameSite: http.SameSiteStrictMode,
	})
}

// tokenFrom takes the token from the kind's cookie (browsers) or, failing
// that, from "Authorization: Bearer ..." (curl, tests).
func tokenFrom(r *http.Request, kind string) string {
	if ck, err := r.Cookie(cookieName(kind)); err == nil && ck.Value != "" {
		return ck.Value
	}
	if raw, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer "); ok {
		return raw
	}
	return ""
}

func (t *Tokens) IssueCustomer(userID int64) (string, error) {
	return t.issue(Claims{Kind: KindCustomer}, userID)
}

func (t *Tokens) IssueStaff(staffID, restaurantID int64, role string) (string, error) {
	return t.issue(Claims{Kind: KindStaff, RestaurantID: restaurantID, Role: role}, staffID)
}

func (t *Tokens) issue(c Claims, id int64) (string, error) {
	jti := make([]byte, 16)
	if _, err := rand.Read(jti); err != nil {
		return "", err
	}

	now := time.Now()
	c.ID = hex.EncodeToString(jti)
	c.Subject = strconv.FormatInt(id, 10)
	c.IssuedAt = jwt.NewNumericDate(now)
	c.ExpiresAt = jwt.NewNumericDate(now.Add(tokenTTL))
	return jwt.NewWithClaims(jwt.SigningMethodHS256, c).SignedString(t.secret)
}

// Revoke is logout: the token is refused from now until it expires.
func (t *Tokens) Revoke(ctx context.Context, c *Claims) error {
	return t.revoked.Revoke(ctx, c.ID, c.ExpiresAt.Time)
}

func (t *Tokens) parse(raw string) (*Claims, error) {
	var c Claims
	_, err := jwt.ParseWithClaims(raw, &c,
		func(*jwt.Token) (any, error) { return t.secret, nil },
		// Only accept HS256, so a forged token can't switch the algorithm.
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithExpirationRequired(),
	)
	if err != nil {
		return nil, err
	}
	return &c, nil
}

// Require lets a request through only if it carries a valid token of the
// given kind ("customer" or "staff"), and stores the claims on the request.
func (t *Tokens) Require(kind string) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			raw := tokenFrom(c.Request(), kind)
			if raw == "" {
				return echo.NewHTTPError(http.StatusUnauthorized, "missing token")
			}

			claims, err := t.parse(raw)
			if err != nil || claims.ID == "" {
				return echo.NewHTTPError(http.StatusUnauthorized, "invalid or expired token")
			}

			if claims.Kind != kind {
				return echo.NewHTTPError(http.StatusForbidden, "this route is for "+kind+" accounts")
			}

			// If the check itself fails (DB down), refuse the request rather
			// than risk letting a logged-out token through.
			revoked, err := t.revoked.IsRevoked(c.Request().Context(), claims.ID)
			if err != nil {
				return err
			}
			if revoked {
				return echo.NewHTTPError(http.StatusUnauthorized, "token has been logged out")
			}

			c.Set(claimsKey, claims)
			return next(c)
		}
	}
}

// From returns the claims stored by Require. Only call it behind Require.
func From(c echo.Context) *Claims {
	return c.Get(claimsKey).(*Claims)
}
