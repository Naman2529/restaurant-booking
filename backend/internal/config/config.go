package config

import (
	"fmt"
	"os"

	"github.com/joho/godotenv"
)

// Config holds the settings the server needs at startup.
// pgx reads PGHOST, PGPORT and PGDATABASE from the environment by itself.
// PGUSER / PGPASSWORD are for psql (postgres). The app logs in as the
// limited role from db/roles.sql instead, so it gets its own user and password.
type Config struct {
	HTTPPort   string
	DBUser     string
	DBPassword string
	JWTSecret  string

	// CookieSecure marks the auth cookie HTTPS-only. Leave it off for
	// local http://localhost; turn it on when deployed behind HTTPS.
	CookieSecure bool

	// Gmail SMTP (App password). Both empty = verification links are
	// printed to the server log instead of emailed.
	SMTPUser     string
	SMTPPassword string

	// BaseURL is where links in emails point, e.g. http://localhost:8080.
	BaseURL string
}

// Load reads .env into the environment, checks the database variables
// are set, and returns the config.
func Load() (Config, error) {
	// .env lives in the project root. Try the current folder first, then
	// the parent, so it works from either root/ or backend/. A missing
	// file is fine: the variables may already be set in the shell.
	// godotenv never overwrites a variable that is already set.
	for _, path := range []string{".env", "../.env"} {
		_ = godotenv.Load(path)
	}

	for _, key := range []string{"PGHOST", "PGPORT", "PGDATABASE", "APP_DB_PASSWORD", "JWT_SECRET"} {
		if os.Getenv(key) == "" {
			return Config{}, fmt.Errorf("config: %s is not set", key)
		}
	}

	// HS256 needs a long random key; a short one can be brute-forced.
	if len(os.Getenv("JWT_SECRET")) < 32 {
		return Config{}, fmt.Errorf("config: JWT_SECRET must be at least 32 characters")
	}

	port := os.Getenv("HTTP_PORT")
	if port == "" {
		port = "8080"
	}

	user := os.Getenv("APP_DB_USER")
	if user == "" {
		user = "booking_app"
	}

	smtpUser, smtpPassword := os.Getenv("SMTP_USER"), os.Getenv("SMTP_PASSWORD")
	if (smtpUser == "") != (smtpPassword == "") {
		return Config{}, fmt.Errorf("config: set both SMTP_USER and SMTP_PASSWORD, or neither")
	}

	baseURL := os.Getenv("APP_BASE_URL")
	if baseURL == "" {
		baseURL = "http://localhost:" + port
	}

	return Config{
		HTTPPort:   port,
		DBUser:     user,
		DBPassword: os.Getenv("APP_DB_PASSWORD"),
		JWTSecret:  os.Getenv("JWT_SECRET"),

		CookieSecure: os.Getenv("COOKIE_SECURE") == "true",

		SMTPUser:     smtpUser,
		SMTPPassword: smtpPassword,
		BaseURL:      baseURL,
	}, nil
}
