package db

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Connect opens a connection pool and pings the database once, so a wrong
// password or a stopped server fails at startup, not on the first request.
// An empty connection string tells pgx to read the PG* environment variables;
// user and password are then replaced with the app's limited role.
func Connect(ctx context.Context, user, password string) (*pgxpool.Pool, error) {
	cfg, err := pgxpool.ParseConfig("")
	if err != nil {
		return nil, fmt.Errorf("db: parse config: %w", err)
	}
	cfg.ConnConfig.User = user
	cfg.ConnConfig.Password = password

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("db: open pool: %w", err)
	}

	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	if err := pool.Ping(pingCtx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("db: ping: %w", err)
	}

	return pool, nil
}
