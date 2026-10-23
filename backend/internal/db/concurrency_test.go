package db

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"

	"github.com/Naman2529/restaurant-booking/backend/internal/config"
)

// Integration test against the real database (run reset.sql first).
// Many goroutines call customer.book_table for the same slot at the same
// instant, each on its own connection, logged in as booking_app like the
// server. The exclusion constraint must let exactly as many through as
// there are fitting tables, and never put two bookings on one table.
//
//	go test -v -run TestConcurrentBooking ./internal/db/
//
// Bookings are committed (that is the point), so the test deletes them as
// postgres before and after. The slot is in Jan 2027, away from seed data.
//
// This test found a real bug on 24 Oct: two sessions inserting onto the same
// table at once could deadlock (40P01) inside the exclusion check, failing the
// booking instead of trying the next table. Fixed in book_table with a
// per-table row lock; see docs/report/testing-findings.md.

const raceSlot = "2027-01-15T19:00"

type outcome struct {
	reservationID int64
	code          string // SQLSTATE when refused, "" when booked
	msg           string
}

func TestConcurrentBooking(t *testing.T) {
	if testing.Short() {
		t.Skip("integration test: needs the database")
	}
	// go test runs in this package's folder; .env is in the project root.
	_ = godotenv.Load("../../../.env")
	cfg, err := config.Load()
	if err != nil {
		t.Skipf("no database config: %v", err)
	}
	ctx := context.Background()

	admin, err := Connect(ctx, os.Getenv("PGUSER"), os.Getenv("PGPASSWORD"))
	if err != nil {
		t.Skipf("database not reachable: %v", err)
	}
	t.Cleanup(admin.Close) // registered first, so it runs after the cleanup below

	cleanup := func() {
		if _, err := admin.Exec(ctx,
			`DELETE FROM reservation WHERE lower(period) = $1::timestamp`, raceSlot); err != nil {
			t.Fatalf("cleanup: %v", err)
		}
	}
	cleanup()
	t.Cleanup(cleanup)

	cases := []struct {
		name       string
		restaurant string
		party      int
		goroutines int
		wantBooked int // tables that fit this party at this restaurant
	}{
		// Coastal Kitchen has one hall (table 8): the only table for 11+.
		{"one hall, 50 parties of 15", "Coastal Kitchen", 15, 50, 1},
		// Spice Route: four 2-seaters + four 4-seaters (one size up) fit a party of 2.
		{"eight small tables, 50 parties of 2", "Spice Route", 2, 50, 8},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var restaurantID int64
			if err := admin.QueryRow(ctx,
				`SELECT restaurant_id FROM restaurant WHERE name = $1`, tc.restaurant).Scan(&restaurantID); err != nil {
				t.Fatalf("restaurant: %v", err)
			}
			userIDs := verifiedUsers(t, admin)

			results := race(t, cfg, restaurantID, userIDs, tc.party, tc.goroutines)

			booked := 0
			refused := map[string]int{}
			for _, r := range results {
				if r.code == "" {
					booked++
				} else {
					refused[r.code+" "+r.msg]++
				}
			}
			t.Logf("%d goroutines fired at %s for a party of %d at %s", tc.goroutines, raceSlot, tc.party, tc.restaurant)
			t.Logf("booked:  %d", booked)
			for msg, n := range refused {
				t.Logf("refused: %d x %s", n, msg)
			}

			if booked != tc.wantBooked {
				t.Errorf("booked %d, want exactly %d", booked, tc.wantBooked)
			}
			for msg := range refused {
				if !strings.HasPrefix(msg, "RB409 ") {
					t.Errorf("refusals must be RB409 (no table), got %q", msg)
				}
			}

			// The real proof: what is in the table now, not what the goroutines think.
			rows, err := admin.Query(ctx, `
				SELECT t.table_number, count(*)
				FROM reservation r
				JOIN dining_table t ON t.table_id = r.table_id
				WHERE t.restaurant_id = $1
				  AND lower(r.period) = $2::timestamp
				  AND r.status IN ('booked', 'seated')
				GROUP BY t.table_number
				ORDER BY t.table_number`, restaurantID, raceSlot)
			if err != nil {
				t.Fatalf("check: %v", err)
			}
			defer rows.Close()
			var tables []string
			total := 0
			for rows.Next() {
				var number, count int
				if err := rows.Scan(&number, &count); err != nil {
					t.Fatalf("scan: %v", err)
				}
				tables = append(tables, fmt.Sprintf("table %d x%d", number, count))
				total += count
				if count != 1 {
					t.Errorf("DOUBLE BOOKING: table %d has %d active bookings at %s", number, count, raceSlot)
				}
			}
			if total != tc.wantBooked {
				t.Errorf("database holds %d bookings, want %d", total, tc.wantBooked)
			}
			t.Logf("in the database: %s", strings.Join(tables, ", "))
		})
	}
}

// race opens one connection per goroutine first, then releases them all at
// once, so the CALLs really hit Postgres at the same moment.
func race(t *testing.T, cfg config.Config, restaurantID int64, userIDs []int64, party, n int) []outcome {
	t.Helper()
	ctx := context.Background()

	pcfg, err := pgxpool.ParseConfig("")
	if err != nil {
		t.Fatalf("pool config: %v", err)
	}
	pcfg.ConnConfig.User = cfg.DBUser
	pcfg.ConnConfig.Password = cfg.DBPassword
	pcfg.MaxConns = int32(n)
	pool, err := pgxpool.NewWithConfig(ctx, pcfg)
	if err != nil {
		t.Fatalf("pool: %v", err)
	}
	defer pool.Close()

	conns := make([]*pgxpool.Conn, n)
	for i := range conns {
		if conns[i], err = pool.Acquire(ctx); err != nil {
			t.Fatalf("acquire %d: %v", i, err)
		}
	}

	results := make([]outcome, n)
	start := make(chan struct{})
	var ready, done sync.WaitGroup
	ready.Add(n)
	done.Add(n)

	for i := range n {
		go func() {
			defer done.Done()
			defer conns[i].Release()
			user := userIDs[i%len(userIDs)]
			ready.Done()
			<-start

			callCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
			defer cancel()
			var id *int64
			err := conns[i].QueryRow(callCtx,
				`CALL customer.book_table($1, $2, $3::timestamp, $4, NULL)`,
				user, restaurantID, raceSlot, party).Scan(&id)

			var pgErr *pgconn.PgError
			switch {
			case err == nil && id != nil:
				results[i] = outcome{reservationID: *id}
			case errors.As(err, &pgErr):
				results[i] = outcome{code: pgErr.Code, msg: pgErr.Message}
			default:
				results[i] = outcome{code: "GO", msg: fmt.Sprint(err)}
			}
		}()
	}

	ready.Wait()
	close(start)
	done.Wait()

	return results
}

func verifiedUsers(t *testing.T, admin *pgxpool.Pool) []int64 {
	t.Helper()
	rows, err := admin.Query(context.Background(),
		`SELECT user_id FROM app_user WHERE email_verified_at IS NOT NULL ORDER BY user_id`)
	if err != nil {
		t.Fatalf("users: %v", err)
	}
	defer rows.Close()
	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			t.Fatalf("scan: %v", err)
		}
		ids = append(ids, id)
	}
	if len(ids) == 0 {
		t.Fatal("no verified users in the seed")
	}
	return ids
}
