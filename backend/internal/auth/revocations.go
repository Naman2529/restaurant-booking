package auth

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// PGRevocations is the RevocationStore backed by the revoked_token table,
// through auth.revoke_token / auth.is_revoked.
type PGRevocations struct {
	Pool *pgxpool.Pool
}

func (s PGRevocations) Revoke(ctx context.Context, jti string, expiresAt time.Time) error {
	_, err := s.Pool.Exec(ctx, "CALL auth.revoke_token($1, $2)", jti, expiresAt)
	return err
}

func (s PGRevocations) IsRevoked(ctx context.Context, jti string) (bool, error) {
	var revoked bool
	err := s.Pool.QueryRow(ctx, "SELECT auth.is_revoked($1)", jti).Scan(&revoked)
	return revoked, err
}
