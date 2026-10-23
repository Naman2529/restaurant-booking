package mail

import (
	"strings"
	"testing"
)

func TestVerificationMessage(t *testing.T) {
	link := VerifyLink("http://localhost:8080/", "abc123")
	if link != "http://localhost:8080/verify-email?token=abc123" {
		t.Fatalf("wrong link: %s", link)
	}

	msg, err := verificationMessage("me@gmail.com", "aarav@example.com", "Aarav", link)
	if err != nil {
		t.Fatal(err)
	}
	s := string(msg)
	for _, want := range []string{"To: aarav@example.com\r\n", "Subject: Verify your email\r\n", "Hi Aarav,", link} {
		if !strings.Contains(s, want) {
			t.Fatalf("message missing %q:\n%s", want, s)
		}
	}
}

func TestHeaderInjectionRejected(t *testing.T) {
	bad := []string{
		"victim@example.com\r\nBcc: everyone@example.com",
		"Someone <victim@example.com>",
		"not-an-address",
	}
	for _, to := range bad {
		if _, err := verificationMessage("me@gmail.com", to, "X", "http://x"); err == nil {
			t.Fatalf("accepted bad address %q", to)
		}
	}
}

func TestNameCannotBreakLines(t *testing.T) {
	msg, err := verificationMessage("me@gmail.com", "a@example.com", "Eve\r\nBcc: x@example.com", "http://x")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(msg), "\r\nBcc:") {
		t.Fatal("name added a header line")
	}
}

func TestNewFallsBackToLog(t *testing.T) {
	if _, ok := New("", "").(LogSender); !ok {
		t.Fatal("without credentials, New should return LogSender")
	}
	if _, ok := New("me@gmail.com", "app-password").(Gmail); !ok {
		t.Fatal("with credentials, New should return Gmail")
	}
}
