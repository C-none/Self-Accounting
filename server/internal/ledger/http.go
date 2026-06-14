package ledger

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type contextKey string

const deviceContextKey contextKey = "device"

func (a *App) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/health", a.handleHealth)
	mux.HandleFunc("POST /api/pair/start", a.handlePairStart)
	mux.HandleFunc("POST /api/pair/confirm", a.handlePairConfirm)
	mux.HandleFunc("GET /api/bootstrap", a.requireAuth(a.handleBootstrap))
	mux.HandleFunc("PATCH /api/devices/current", a.requireAuth(a.handlePatchCurrentDevice))
	mux.HandleFunc("POST /api/categories", a.requireAuth(a.handleCreateCategory))
	mux.HandleFunc("PATCH /api/categories/{id}", a.requireAuth(a.handlePatchCategory))
	mux.HandleFunc("DELETE /api/categories/{id}", a.requireAuth(a.handleDeleteCategory))
	mux.HandleFunc("POST /api/members", a.requireAuth(a.handleCreateMember))
	mux.HandleFunc("PATCH /api/members/{id}", a.requireAuth(a.handlePatchMember))
	mux.HandleFunc("DELETE /api/members/{id}", a.requireAuth(a.handleDeleteMember))
	mux.HandleFunc("POST /api/accounts", a.requireAuth(a.handleCreateAccount))
	mux.HandleFunc("PATCH /api/accounts/{id}", a.requireAuth(a.handlePatchAccount))
	mux.HandleFunc("DELETE /api/accounts/{id}", a.requireAuth(a.handleDeleteAccount))
	mux.HandleFunc("GET /api/transactions", a.requireAuth(a.handleListTransactions))
	mux.HandleFunc("POST /api/transactions", a.requireAuth(a.handleCreateTransaction))
	mux.HandleFunc("GET /api/transactions/{id}", a.requireAuth(a.handleGetTransaction))
	mux.HandleFunc("PATCH /api/transactions/{id}", a.requireAuth(a.handlePatchTransaction))
	mux.HandleFunc("DELETE /api/transactions/{id}", a.requireAuth(a.handleDeleteTransaction))
	mux.HandleFunc("GET /api/transactions/{id}/attachments", a.requireAuth(a.handleListAttachments))
	mux.HandleFunc("POST /api/attachments", a.requireAuth(a.handleUploadAttachment))
	mux.HandleFunc("GET /api/attachments/{id}", a.requireAuth(a.handleGetAttachmentFile))
	mux.HandleFunc("GET /api/attachments/{id}/thumbnail", a.requireAuth(a.handleGetAttachmentThumbnail))
	mux.HandleFunc("DELETE /api/attachments/{id}", a.requireAuth(a.handleDeleteAttachment))
	mux.HandleFunc("GET /api/admin/audit-logs", a.requireAdmin(a.handleAdminAuditLogs))
	mux.HandleFunc("POST /api/admin/checkpoint", a.requireAdmin(a.handleAdminCheckpoint))
	mux.HandleFunc("POST /api/admin/backup", a.requireAdmin(a.handleAdminBackup))
	mux.HandleFunc("POST /api/category-suggestions", a.requireAuth(a.handleCategorySuggestions))
	mux.HandleFunc("POST /api/sms/imports", a.requireAuth(a.handleSMSImport))
	mux.HandleFunc("GET /api/stats/category", a.requireAuth(a.handleStatsCategory))
	mux.HandleFunc("GET /api/stats/timeline", a.requireAuth(a.handleStatsTimeline))
	mux.HandleFunc("/", a.handleWeb)
	return a.withCORS(a.withLogging(mux))
}

func (a *App) withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (a *App) withLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		log.Printf("%s %s %d %s", r.Method, r.URL.Path, rec.status, time.Since(start).Round(time.Millisecond))
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

func (a *App) requireAuth(next func(http.ResponseWriter, *http.Request, Device)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		device, err := a.authenticate(r)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "unauthorized", "device token is invalid")
			return
		}
		ctx := context.WithValue(r.Context(), deviceContextKey, device)
		next(w, r.WithContext(ctx), device)
	}
}

func (a *App) requireAdmin(next func(http.ResponseWriter, *http.Request, Device)) http.HandlerFunc {
	return a.requireAuth(func(w http.ResponseWriter, r *http.Request, device Device) {
		if !device.IsAdmin {
			writeError(w, http.StatusForbidden, "forbidden", "admin device token is required")
			return
		}
		next(w, r, device)
	})
}

func (a *App) authenticate(r *http.Request) (Device, error) {
	token := bearerToken(r)
	if token == "" {
		return Device{}, errors.New("missing bearer token")
	}
	hash := hmacHex(a.secret, token)
	rows, err := a.db.QueryContext(r.Context(), `SELECT id, name, platform, token_hash, is_admin, last_seen_at FROM devices WHERE active = 1 AND revoked_at IS NULL`)
	if err != nil {
		return Device{}, err
	}
	defer rows.Close()
	var matched Device
	found := false
	for rows.Next() {
		var d Device
		var storedHash string
		var isAdmin int
		var lastSeen sql.NullInt64
		if err := rows.Scan(&d.ID, &d.Name, &d.Platform, &storedHash, &isAdmin, &lastSeen); err != nil {
			return Device{}, err
		}
		if equalHash(hash, storedHash) {
			d.IsAdmin = boolFromInt(isAdmin)
			if lastSeen.Valid {
				d.LastSeenAt = &lastSeen.Int64
			}
			matched = d
			found = true
			break
		}
	}
	if err := rows.Err(); err != nil {
		return Device{}, err
	}
	rows.Close()
	if !found {
		return Device{}, errors.New("invalid bearer token")
	}
	_, _ = a.db.ExecContext(r.Context(), `UPDATE devices SET last_seen_at = ? WHERE id = ?`, unixNow(), matched.ID)
	return matched, nil
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]any{
		"error": map[string]string{
			"code":    code,
			"message": message,
		},
	})
}

func decodeJSON(r *http.Request, dst any) error {
	defer r.Body.Close()
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	return dec.Decode(dst)
}

func (a *App) handleHealth(w http.ResponseWriter, r *http.Request) {
	status := "ok"
	dbStatus := "ok"
	journalMode := ""
	if err := a.db.PingContext(r.Context()); err != nil {
		status = "degraded"
		dbStatus = err.Error()
	} else {
		_ = a.db.QueryRowContext(r.Context(), `PRAGMA journal_mode`).Scan(&journalMode)
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"status":       status,
		"server_time":  unixNow(),
		"database":     dbStatus,
		"journal_mode": journalMode,
	})
}

func (a *App) handleWeb(w http.ResponseWriter, r *http.Request) {
	if strings.HasPrefix(r.URL.Path, "/api/") {
		writeError(w, http.StatusNotFound, "not_found", "api route not found")
		return
	}
	webDir := a.cfg.Server.WebDir
	indexPath := filepath.Join(webDir, "index.html")
	if _, err := os.Stat(indexPath); err != nil {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("<!doctype html><title>小小记账</title><body>Flutter Web build is not available. Run flutter build web in ./client.</body>"))
		return
	}
	clean := filepath.Clean(strings.TrimPrefix(r.URL.Path, "/"))
	if clean == "." || clean == "" {
		http.ServeFile(w, r, indexPath)
		return
	}
	target := filepath.Join(webDir, clean)
	rel, err := filepath.Rel(webDir, target)
	if err != nil || strings.HasPrefix(rel, "..") {
		http.NotFound(w, r)
		return
	}
	if info, err := os.Stat(target); err == nil && !info.IsDir() {
		http.ServeFile(w, r, target)
		return
	}
	http.ServeFile(w, r, indexPath)
}
