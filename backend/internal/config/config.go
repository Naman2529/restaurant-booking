package config

import (
	"fmt"
	"os"

	"github.com/joho/godotenv"
)

// Config holds the settings the server needs at startup.
// Database settings are not copied in here: pgx reads PGHOST, PGPORT,
// PGUSER, PGPASSWORD and PGDATABASE from the environment by itself.
type Config struct {
	HTTPPort string
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

	for _, key := range []string{"PGHOST", "PGPORT", "PGUSER", "PGPASSWORD", "PGDATABASE"} {
		if os.Getenv(key) == "" {
			return Config{}, fmt.Errorf("config: %s is not set", key)
		}
	}

	port := os.Getenv("HTTP_PORT")
	if port == "" {
		port = "8080"
	}

	return Config{HTTPPort: port}, nil
}
