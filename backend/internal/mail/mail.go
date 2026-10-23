package mail

import (
	"context"
	"crypto/tls"
	"fmt"
	"log"
	"net"
	netmail "net/mail"
	"net/smtp"
	"net/url"
	"strings"
	"time"
)

const (
	gmailHost   = "smtp.gmail.com"
	gmailAddr   = "smtp.gmail.com:587"
	sendTimeout = 15 * time.Second
)

// Sender sends the "verify your email" message.
type Sender interface {
	SendVerification(ctx context.Context, to, name, link string) error
}

// New returns a Gmail sender if SMTP credentials are set, otherwise one that
// only prints the link to the server log (handy without email set up).
func New(user, password string) Sender {
	if user == "" || password == "" {
		return LogSender{}
	}
	return Gmail{User: user, Password: password}
}

// VerifyLink builds the link that goes in the email. It opens the front
// end's /verify-email page, which calls GET /auth/verify from JavaScript.
// Email scanners that pre-open links don't run JavaScript, so they can't use
// up the single-use token. baseURL is the front end's address.
func VerifyLink(baseURL, token string) string {
	return strings.TrimRight(baseURL, "/") + "/verify-email?token=" + url.QueryEscape(token)
}

// LogSender prints the link instead of emailing it.
type LogSender struct{}

func (LogSender) SendVerification(_ context.Context, to, _, link string) error {
	log.Printf("verification link for %s: %s", to, link)
	return nil
}

// Gmail sends through smtp.gmail.com with an App password.
type Gmail struct {
	User     string
	Password string
}

func (g Gmail) SendVerification(ctx context.Context, to, name, link string) error {
	msg, err := verificationMessage(g.User, to, name, link)
	if err != nil {
		return err
	}
	return g.send(ctx, to, msg)
}

// send does the SMTP conversation by hand (instead of smtp.SendMail) so the
// whole thing has a timeout and can't hang a request.
func (g Gmail) send(ctx context.Context, to string, msg []byte) error {
	ctx, cancel := context.WithTimeout(ctx, sendTimeout)
	defer cancel()

	var d net.Dialer
	conn, err := d.DialContext(ctx, "tcp", gmailAddr)
	if err != nil {
		return fmt.Errorf("mail: dial: %w", err)
	}
	defer conn.Close()
	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}

	c, err := smtp.NewClient(conn, gmailHost)
	if err != nil {
		return fmt.Errorf("mail: hello: %w", err)
	}
	defer c.Close()

	// Port 587 starts in plain text; STARTTLS upgrades it before the
	// password is sent.
	if err := c.StartTLS(&tls.Config{ServerName: gmailHost}); err != nil {
		return fmt.Errorf("mail: starttls: %w", err)
	}
	if err := c.Auth(smtp.PlainAuth("", g.User, g.Password, gmailHost)); err != nil {
		return fmt.Errorf("mail: login: %w", err)
	}
	if err := c.Mail(g.User); err != nil {
		return fmt.Errorf("mail: from: %w", err)
	}
	if err := c.Rcpt(to); err != nil {
		return fmt.Errorf("mail: to: %w", err)
	}

	w, err := c.Data()
	if err != nil {
		return fmt.Errorf("mail: data: %w", err)
	}
	if _, err := w.Write(msg); err != nil {
		return fmt.Errorf("mail: write: %w", err)
	}
	if err := w.Close(); err != nil {
		return fmt.Errorf("mail: send: %w", err)
	}
	return c.Quit()
}

// verificationMessage builds the raw email. The address is parsed first,
// which rejects line breaks, so user input can't add extra headers
// (e.g. a hidden Bcc).
func verificationMessage(from, to, name, link string) ([]byte, error) {
	addr, err := netmail.ParseAddress(to)
	if err != nil || addr.Address != to {
		return nil, fmt.Errorf("mail: invalid address %q", to)
	}
	name = strings.NewReplacer("\r", " ", "\n", " ").Replace(name)

	var b strings.Builder
	b.WriteString("From: Restaurant Booking <" + from + ">\r\n")
	b.WriteString("To: " + addr.Address + "\r\n")
	b.WriteString("Subject: Verify your email\r\n")
	b.WriteString("MIME-Version: 1.0\r\n")
	b.WriteString("Content-Type: text/plain; charset=UTF-8\r\n")
	b.WriteString("\r\n")
	b.WriteString("Hi " + name + ",\r\n\r\n")
	b.WriteString("Thanks for signing up. Confirm your email to start booking tables:\r\n\r\n")
	b.WriteString(link + "\r\n\r\n")
	b.WriteString("This link works once and expires in 24 hours.\r\n")
	b.WriteString("If you didn't sign up, you can ignore this email.\r\n")
	return []byte(b.String()), nil
}
