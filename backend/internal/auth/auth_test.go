package auth

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/labstack/echo/v4"
)

const testSecret = "test-secret-that-is-at-least-32-chars"

// memRevocations is an in-memory RevocationStore, so these tests don't need
// a database.
type memRevocations map[string]bool

func (m memRevocations) Revoke(_ context.Context, jti string, _ time.Time) error {
	m[jti] = true
	return nil
}

func (m memRevocations) IsRevoked(_ context.Context, jti string) (bool, error) {
	return m[jti], nil
}

func newTestTokens() *Tokens {
	return NewTokens(testSecret, false, memRevocations{})
}

func TestStaffTokenRoundTrip(t *testing.T) {
	tk := newTestTokens()

	raw, err := tk.IssueStaff(2, 1, "receptionist")
	if err != nil {
		t.Fatal(err)
	}

	c, err := tk.parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	if c.Kind != KindStaff || c.SubjectID() != 2 || c.RestaurantID != 1 || c.Role != "receptionist" {
		t.Fatalf("wrong claims: %+v", c)
	}
	if len(c.ID) != 32 {
		t.Fatalf("token id (jti) should be 32 hex chars, got %q", c.ID)
	}
}

func TestEachTokenHasOwnID(t *testing.T) {
	tk := newTestTokens()
	a, _ := tk.IssueCustomer(1)
	b, _ := tk.IssueCustomer(1)
	ca, _ := tk.parse(a)
	cb, _ := tk.parse(b)
	if ca.ID == cb.ID {
		t.Fatal("two tokens got the same jti, so logging out one would log out both")
	}
}

func TestWrongSecretRejected(t *testing.T) {
	raw, _ := newTestTokens().IssueCustomer(1)

	other := NewTokens("a-different-secret-also-32-chars-long", false, memRevocations{})
	if _, err := other.parse(raw); err == nil {
		t.Fatal("token signed with another secret was accepted")
	}
}

func TestSetCookie(t *testing.T) {
	tk := newTestTokens()
	rec := httptest.NewRecorder()
	c := echo.New().NewContext(httptest.NewRequest(http.MethodPost, "/", nil), rec)

	tk.SetCookie(c, KindStaff, "abc")

	cookies := rec.Result().Cookies()
	if len(cookies) != 1 {
		t.Fatalf("got %d cookies, want 1", len(cookies))
	}
	ck := cookies[0]
	if ck.Name != "rb_staff" || ck.Value != "abc" || !ck.HttpOnly || ck.SameSite != http.SameSiteStrictMode {
		t.Fatalf("wrong cookie: %+v", ck)
	}
}

// callRequire runs a request through Require(kind) and returns the HTTP status.
// header is sent as Authorization; cookie (if set) is sent as a cookie.
func callRequire(t *testing.T, tk *Tokens, kind, header string, cookie *http.Cookie) int {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	if header != "" {
		req.Header.Set("Authorization", header)
	}
	if cookie != nil {
		req.AddCookie(cookie)
	}
	c := echo.New().NewContext(req, httptest.NewRecorder())

	err := tk.Require(kind)(func(c echo.Context) error {
		return c.NoContent(http.StatusOK)
	})(c)

	var he *echo.HTTPError
	if errors.As(err, &he) {
		return he.Code
	}
	if err != nil {
		t.Fatal(err)
	}
	return http.StatusOK
}

func TestRequire(t *testing.T) {
	tk := newTestTokens()
	customer, _ := tk.IssueCustomer(1)
	staff, _ := tk.IssueStaff(2, 1, "receptionist")

	cases := []struct {
		name   string
		kind   string
		header string
		cookie *http.Cookie
		want   int
	}{
		{"no token", KindCustomer, "", nil, http.StatusUnauthorized},
		{"garbage token", KindCustomer, "Bearer abc.def.ghi", nil, http.StatusUnauthorized},
		{"customer header on customer route", KindCustomer, "Bearer " + customer, nil, http.StatusOK},
		{"customer header on staff route", KindStaff, "Bearer " + customer, nil, http.StatusForbidden},
		{"staff header on staff route", KindStaff, "Bearer " + staff, nil, http.StatusOK},
		{"staff cookie on staff route", KindStaff, "", &http.Cookie{Name: "rb_staff", Value: staff}, http.StatusOK},
		{"customer cookie on staff route", KindStaff, "", &http.Cookie{Name: "rb_customer", Value: customer}, http.StatusUnauthorized},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := callRequire(t, tk, tc.kind, tc.header, tc.cookie); got != tc.want {
				t.Fatalf("got %d, want %d", got, tc.want)
			}
		})
	}
}

func TestLogoutRevokesOnlyThatToken(t *testing.T) {
	tk := newTestTokens()
	phone, _ := tk.IssueCustomer(1)
	laptop, _ := tk.IssueCustomer(1)

	claims, _ := tk.parse(phone)
	if err := tk.Revoke(context.Background(), claims); err != nil {
		t.Fatal(err)
	}

	if got := callRequire(t, tk, KindCustomer, "Bearer "+phone, nil); got != http.StatusUnauthorized {
		t.Fatalf("logged-out token: got %d, want 401", got)
	}
	if got := callRequire(t, tk, KindCustomer, "Bearer "+laptop, nil); got != http.StatusOK {
		t.Fatalf("other device's token: got %d, want 200", got)
	}
}
