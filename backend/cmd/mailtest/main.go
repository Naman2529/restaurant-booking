// mailtest sends one test verification email, to check the Gmail settings
// in .env without going through sign-up.
//
//	go run ./cmd/mailtest you@example.com
package main

import (
	"context"
	"log"
	"os"

	"github.com/Naman2529/restaurant-booking/backend/internal/config"
	"github.com/Naman2529/restaurant-booking/backend/internal/mail"
)

func main() {
	if len(os.Args) != 2 {
		log.Fatal("usage: go run ./cmd/mailtest <to-address>")
	}

	cfg, err := config.Load()
	if err != nil {
		log.Fatal(err)
	}
	if cfg.SMTPUser == "" {
		log.Fatal("SMTP_USER / SMTP_PASSWORD are not set in .env")
	}

	link := mail.VerifyLink(cfg.BaseURL, "test-token-not-real")
	err = mail.New(cfg.SMTPUser, cfg.SMTPPassword).SendVerification(context.Background(), os.Args[1], "Test", link)
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("sent to %s", os.Args[1])
}
