package ledger

import (
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"time"
)

func (a *App) handlePairStart(w http.ResponseWriter, r *http.Request) {
	code, expiresAt, err := a.getOrCreateRuntimePairingCode(r)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to create pairing code")
		return
	}

	if _, err := a.authenticate(r); err == nil {
		writeJSON(w, http.StatusOK, map[string]any{
			"pairing_code": code,
			"expires_at":   expiresAt,
			"delivery":     "response",
		})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"expires_at": expiresAt,
		"delivery":   "server_console",
	})
}

func (a *App) getOrCreateRuntimePairingCode(r *http.Request) (string, int64, error) {
	a.pairingCodeMu.Lock()
	defer a.pairingCodeMu.Unlock()

	now := unixNow()
	if a.activePlainCode != nil && a.activePlainCode.expiresAt >= now {
		printPairingCode(a.activePlainCode.code, a.activePlainCode.expiresAt)
		return a.activePlainCode.code, a.activePlainCode.expiresAt, nil
	}

	code, err := randomPairingCode()
	if err != nil {
		return "", 0, err
	}
	id, err := randomID("pair")
	if err != nil {
		return "", 0, err
	}
	expiresAt := now + int64((10 * time.Minute).Seconds())
	if _, err := a.db.ExecContext(r.Context(), `INSERT INTO pairing_codes(id, code_hash, expires_at, created_at) VALUES (?, ?, ?, ?)`,
		id, hmacHex(a.secret, code), expiresAt, now); err != nil {
		return "", 0, err
	}
	a.activePlainCode = &runtimePairingCode{
		id:        id,
		code:      code,
		expiresAt: expiresAt,
	}
	printPairingCode(code, expiresAt)
	return code, expiresAt, nil
}

func (a *App) clearRuntimePairingCode(code string) {
	a.pairingCodeMu.Lock()
	defer a.pairingCodeMu.Unlock()
	if a.activePlainCode != nil && a.activePlainCode.code == code {
		a.activePlainCode = nil
	}
}

func printPairingCode(code string, expiresAt int64) {
	fmt.Printf("PAIRING CODE: %s (expires_at=%d)\n", code, expiresAt)
}

func (a *App) handlePairConfirm(w http.ResponseWriter, r *http.Request) {
	var req struct {
		PairingCode string `json:"pairing_code"`
		DeviceName  string `json:"device_name"`
		Platform    string `json:"platform"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "invalid JSON request")
		return
	}
	if req.PairingCode == "" || req.DeviceName == "" || !validPlatform(req.Platform) {
		writeError(w, http.StatusBadRequest, "validation_error", "pairing_code, device_name and platform are required")
		return
	}

	tx, err := a.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to start pairing")
		return
	}
	defer tx.Rollback()

	var pairID string
	var expiresAt int64
	var usedAt sql.NullInt64
	codeHash := hmacHex(a.secret, req.PairingCode)
	err = tx.QueryRowContext(r.Context(), `SELECT id, expires_at, used_at FROM pairing_codes WHERE code_hash = ?`, codeHash).Scan(&pairID, &expiresAt, &usedAt)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusBadRequest, "validation_error", "pairing code is invalid")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to verify pairing code")
		return
	}
	now := unixNow()
	if usedAt.Valid || expiresAt < now {
		writeError(w, http.StatusBadRequest, "validation_error", "pairing code is expired or already used")
		return
	}

	adminCount, err := activeAdminCountTx(r.Context(), tx)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to inspect devices")
		return
	}
	deviceID, err := randomID("dev")
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to create device")
		return
	}
	token, err := randomToken()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to create device token")
		return
	}
	isAdmin := adminCount == 0
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO devices(id, name, platform, token_hash, is_admin, active, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?, 1, ?, ?)`,
		deviceID, req.DeviceName, req.Platform, hmacHex(a.secret, token), intFromBool(isAdmin), now, now); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to save device")
		return
	}
	if _, err := tx.ExecContext(r.Context(), `UPDATE pairing_codes SET used_at = ? WHERE id = ?`, now, pairID); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to mark pairing code used")
		return
	}
	if err := tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to complete pairing")
		return
	}
	a.clearRuntimePairingCode(req.PairingCode)

	writeJSON(w, http.StatusOK, map[string]any{
		"device_id":    deviceID,
		"device_token": token,
		"is_admin":     isAdmin,
		"server_time":  now,
	})
}

func (a *App) handleBootstrap(w http.ResponseWriter, r *http.Request, device Device) {
	categories, err := a.listCategories(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to load categories")
		return
	}
	members, err := a.listMembers(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to load members")
		return
	}
	accounts, err := a.listAccounts(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to load accounts")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"device":     device,
		"categories": categories,
		"members":    members,
		"accounts":   accounts,
		"features": map[string]bool{
			"sms":    device.Platform == "android",
			"photos": false,
		},
		"config": map[string]any{
			"currency":              "CNY",
			"default_page_size":     50,
			"max_upload_size_bytes": 20 * 1024 * 1024,
		},
		"server_time": unixNow(),
	})
}

func validPlatform(platform string) bool {
	return platform == "android" || platform == "web"
}
