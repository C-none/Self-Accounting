package ledger

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

func unixNow() int64 {
	return time.Now().Unix()
}

func ensureDirForFile(path string) error {
	dir := filepath.Dir(path)
	if dir == "." || dir == "" {
		return nil
	}
	return os.MkdirAll(dir, 0o755)
}

func randomBytes(n int) ([]byte, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return nil, err
	}
	return b, nil
}

func randomID(prefix string) (string, error) {
	b, err := randomBytes(16)
	if err != nil {
		return "", err
	}
	return prefix + "_" + base64.RawURLEncoding.EncodeToString(b), nil
}

func randomToken() (string, error) {
	b, err := randomBytes(32)
	if err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

func randomPairingCode() (string, error) {
	b, err := randomBytes(5)
	if err != nil {
		return "", err
	}
	var n uint64
	for _, v := range b {
		n = (n << 8) | uint64(v)
	}
	return fmt.Sprintf("%08d", n%100000000), nil
}

func loadOrCreateSecret(path string) ([]byte, error) {
	if data, err := os.ReadFile(path); err == nil {
		decoded, decErr := hex.DecodeString(strings.TrimSpace(string(data)))
		if decErr == nil && len(decoded) >= 32 {
			return decoded, nil
		}
	} else if !os.IsNotExist(err) {
		return nil, err
	}
	secret, err := randomBytes(32)
	if err != nil {
		return nil, err
	}
	if err := ensureDirForFile(path); err != nil {
		return nil, err
	}
	if err := os.WriteFile(path, []byte(hex.EncodeToString(secret)), 0o600); err != nil {
		return nil, err
	}
	return secret, nil
}

func hmacHex(secret []byte, value string) string {
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(value))
	return hex.EncodeToString(mac.Sum(nil))
}

func equalHash(a, b string) bool {
	return subtle.ConstantTimeCompare([]byte(a), []byte(b)) == 1
}

func bearerToken(r *http.Request) string {
	header := r.Header.Get("Authorization")
	if header == "" {
		return ""
	}
	parts := strings.SplitN(header, " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
		return ""
	}
	return strings.TrimSpace(parts[1])
}

func isLocalhostRemote(remoteAddr string) bool {
	host, _, err := net.SplitHostPort(remoteAddr)
	if err != nil {
		host = remoteAddr
	}
	ip := net.ParseIP(host)
	if ip == nil {
		return host == "localhost"
	}
	return ip.IsLoopback()
}

func boolFromInt(v int) bool {
	return v != 0
}

func intFromBool(v bool) int {
	if v {
		return 1
	}
	return 0
}

func parsePositiveInt(raw string, fallback, max int) int {
	if raw == "" {
		return fallback
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n <= 0 {
		return fallback
	}
	if max > 0 && n > max {
		return max
	}
	return n
}
