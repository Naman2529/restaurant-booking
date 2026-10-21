package auth

import (
	"errors"

	"golang.org/x/crypto/bcrypt"
)

// ErrPasswordLength is returned for passwords bcrypt can't handle safely:
// under 8 characters is too weak, over 72 bytes bcrypt silently ignores.
var ErrPasswordLength = errors.New("password must be 8 to 72 characters")

// dummyHash is compared against when an email doesn't exist, so a login for
// an unknown email takes as long as one with a wrong password. Otherwise the
// response time would reveal which emails are registered.
var dummyHash, _ = bcrypt.GenerateFromPassword([]byte("not-a-real-password"), bcrypt.DefaultCost)

// HashPassword returns a bcrypt hash (cost 10) to store in the database.
func HashPassword(password string) (string, error) {
	if len(password) < 8 || len(password) > 72 {
		return "", ErrPasswordLength
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(hash), nil
}

// CheckPassword reports whether password matches hash. Pass hash = "" when
// the account wasn't found; it still does a full bcrypt comparison.
func CheckPassword(hash, password string) bool {
	if hash == "" {
		_ = bcrypt.CompareHashAndPassword(dummyHash, []byte(password))
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}
