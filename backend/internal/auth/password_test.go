package auth

import (
	"errors"
	"strings"
	"testing"
)

func TestHashAndCheck(t *testing.T) {
	hash, err := HashPassword("secret123")
	if err != nil {
		t.Fatal(err)
	}
	if len(hash) != 60 || !strings.HasPrefix(hash, "$2") {
		t.Fatalf("not a bcrypt hash: %q", hash)
	}
	if !CheckPassword(hash, "secret123") {
		t.Fatal("right password rejected")
	}
	if CheckPassword(hash, "wrongpass") {
		t.Fatal("wrong password accepted")
	}
}

// The seed hashes passwords with pgcrypto's crypt(.., gen_salt('bf')).
// This hash for "password123" was copied from the seeded app_user table,
// so seeded users can still log in now that Go does the checking.
func TestPgcryptoHashCompatible(t *testing.T) {
	const seeded = "$2a$06$3pOqLZV3diXYVJDmgAXjgOsogGnYJUFNuwn6BKe0k/FX6a.XO55yq"
	if !CheckPassword(seeded, "password123") {
		t.Fatal("pgcrypto bcrypt hash not accepted")
	}
}

func TestUnknownAccount(t *testing.T) {
	if CheckPassword("", "anything") {
		t.Fatal("empty hash accepted")
	}
}

func TestPasswordLength(t *testing.T) {
	for _, pw := range []string{"short", strings.Repeat("a", 73)} {
		if _, err := HashPassword(pw); !errors.Is(err, ErrPasswordLength) {
			t.Fatalf("len %d: got %v, want ErrPasswordLength", len(pw), err)
		}
	}
}
