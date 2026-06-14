package ledger

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"strconv"
	"strings"
)

const maxDeviceNameRunes = 40

func (a *App) handlePatchCurrentDevice(w http.ResponseWriter, r *http.Request, device Device) {
	var req struct {
		Name string `json:"name"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "invalid JSON request")
		return
	}
	name := strings.TrimSpace(req.Name)
	if name == "" || len([]rune(name)) > maxDeviceNameRunes {
		writeError(w, http.StatusBadRequest, "validation_error", "device name must be 1-40 characters")
		return
	}
	if _, err := a.db.ExecContext(r.Context(), `UPDATE devices SET name = ? WHERE id = ? AND active = 1 AND revoked_at IS NULL`, name, device.ID); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to update device")
		return
	}
	_ = a.writeAudit(r.Context(), "device", device.ID, "update_name", device.ID, nil)

	updated, err := a.readDevice(r.Context(), device.ID)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "not_found", "device not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to read device")
		return
	}
	writeJSON(w, http.StatusOK, updated)
}

func (a *App) handleAdminAuditLogs(w http.ResponseWriter, r *http.Request, device Device) {
	limit := 50
	if raw := strings.TrimSpace(r.URL.Query().Get("limit")); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed <= 0 {
			writeError(w, http.StatusBadRequest, "validation_error", "limit must be a positive integer")
			return
		}
		limit = parsed
	}
	if limit > 100 {
		limit = 100
	}

	rows, err := a.db.QueryContext(r.Context(), `
SELECT l.id, l.entity_type, l.entity_id, l.action, l.device_id, COALESCE(d.name, ''), l.created_at
FROM audit_logs l
LEFT JOIN devices d ON d.id = l.device_id
ORDER BY l.created_at DESC, l.id DESC
LIMIT ?`, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to load audit logs")
		return
	}
	defer rows.Close()

	items := make([]AuditLogEntry, 0)
	for rows.Next() {
		var item AuditLogEntry
		if err := rows.Scan(&item.ID, &item.EntityType, &item.EntityID, &item.Action, &item.DeviceID, &item.DeviceName, &item.CreatedAt); err != nil {
			writeError(w, http.StatusInternalServerError, "internal_error", "failed to read audit log")
			return
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to read audit logs")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (a *App) readDevice(ctx context.Context, id string) (Device, error) {
	var d Device
	var isAdmin int
	var lastSeen sql.NullInt64
	err := a.db.QueryRowContext(ctx, `
SELECT id, name, platform, is_admin, last_seen_at
FROM devices
WHERE id = ? AND active = 1 AND revoked_at IS NULL`, id).Scan(&d.ID, &d.Name, &d.Platform, &isAdmin, &lastSeen)
	if err != nil {
		return Device{}, err
	}
	d.IsAdmin = boolFromInt(isAdmin)
	if lastSeen.Valid {
		d.LastSeenAt = &lastSeen.Int64
	}
	return d, nil
}
