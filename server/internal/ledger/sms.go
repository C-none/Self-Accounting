package ledger

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
)

type smsImportRequest struct {
	SMSHash         string  `json:"sms_hash"`
	SenderMasked    string  `json:"sender_masked"`
	SMSReceivedAtMS *int64  `json:"sms_received_at_ms"`
	SMSTime         *int64  `json:"sms_time"`
	AmountCent      *int64  `json:"amount_cent"`
	Direction       string  `json:"direction"`
	Counterparty    string  `json:"counterparty"`
	AccountHint     string  `json:"account_hint"`
	AccountID       string  `json:"account_id"`
	CategoryL1ID    string  `json:"category_l1_id"`
	CategoryL2ID    *string `json:"category_l2_id"`
	MemberID        string  `json:"member_id"`
	Description     string  `json:"description"`
}

func (a *App) handleSMSImport(w http.ResponseWriter, r *http.Request, device Device) {
	if device.Platform != "android" {
		writeError(w, http.StatusForbidden, "forbidden", "SMS import is only available for Android devices")
		return
	}
	data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 64*1024))
	_ = r.Body.Close()
	if err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "invalid JSON request")
		return
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "invalid JSON request")
		return
	}
	for key := range raw {
		if isRawSMSField(key) {
			writeError(w, http.StatusBadRequest, "validation_error", "SMS raw body must not be uploaded")
			return
		}
	}
	var req smsImportRequest
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "invalid SMS import request")
		return
	}
	req.SMSHash = strings.TrimSpace(req.SMSHash)
	req.SenderMasked = strings.TrimSpace(req.SenderMasked)
	req.Counterparty = strings.TrimSpace(req.Counterparty)
	req.AccountHint = strings.TrimSpace(req.AccountHint)
	req.Description = strings.TrimSpace(req.Description)
	txObj, err := a.transactionFromSMSImportRequest(r.Context(), req, device)
	if err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	importID, err := randomID("sms")
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to create SMS import")
		return
	}
	txObj.Source = "sms"
	txObj.SourceRef = importID

	var existingID string
	err = a.db.QueryRowContext(r.Context(), `SELECT id FROM sms_imports WHERE sms_hash = ?`, req.SMSHash).Scan(&existingID)
	if err == nil {
		writeError(w, http.StatusConflict, "duplicate_sms_import", "SMS import already exists")
		return
	}
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to check SMS import")
		return
	}

	tx, err := a.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to start SMS import")
		return
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO transactions(id, amount_cent, currency, direction, transaction_time, category_l1_id, category_l2_id, member_id, account_id, counterparty, description, source, source_ref, created_by_device_id, created_at, updated_at, version) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		txObj.ID, txObj.AmountCent, txObj.Currency, txObj.Direction, txObj.TransactionTime, txObj.CategoryL1ID, nullString(txObj.CategoryL2ID), txObj.MemberID, txObj.AccountID, nullString(txObj.Counterparty), nullString(txObj.Description), txObj.Source, nullString(txObj.SourceRef), txObj.CreatedByDeviceID, txObj.CreatedAt, txObj.UpdatedAt, txObj.Version); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to create SMS transaction")
		return
	}
	now := unixNow()
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO sms_imports(id, sms_hash, sender_masked, sms_received_at_ms, sms_time, parsed_amount_cent, parsed_direction, parsed_counterparty, parsed_account_hint, parsed_category_l1_id, parsed_category_l2_id, status, transaction_id, device_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'confirmed', ?, ?, ?, ?)`,
		importID, req.SMSHash, nullString(req.SenderMasked), *req.SMSReceivedAtMS, *req.SMSTime, *req.AmountCent, req.Direction, nullString(req.Counterparty), nullString(req.AccountHint), req.CategoryL1ID, nullString(stringPtrValue(req.CategoryL2ID)), txObj.ID, device.ID, now, now); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to save SMS import")
		return
	}
	if err := tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to finish SMS import")
		return
	}
	_ = a.writeAudit(r.Context(), "transaction", txObj.ID, "create_sms", device.ID, nil)
	writeJSON(w, http.StatusCreated, map[string]any{
		"import_id":   importID,
		"duplicate":   false,
		"transaction": txObj,
	})
}

func (a *App) transactionFromSMSImportRequest(ctx context.Context, req smsImportRequest, device Device) (Transaction, error) {
	if strings.TrimSpace(req.SMSHash) == "" {
		return Transaction{}, fmt.Errorf("sms_hash is required")
	}
	if req.SMSReceivedAtMS == nil {
		return Transaction{}, fmt.Errorf("sms_received_at_ms is required")
	}
	if *req.SMSReceivedAtMS <= 0 {
		return Transaction{}, fmt.Errorf("sms_received_at_ms must be a positive integer")
	}
	if req.SMSTime == nil || req.AmountCent == nil {
		return Transaction{}, fmt.Errorf("sms_time and amount_cent are required")
	}
	if *req.AmountCent <= 0 {
		return Transaction{}, fmt.Errorf("amount_cent must be a positive integer")
	}
	if err := a.validateTransactionRefs(ctx, req.Direction, req.CategoryL1ID, stringPtrValue(req.CategoryL2ID), req.MemberID, req.AccountID); err != nil {
		return Transaction{}, err
	}
	id, err := randomID("txn")
	if err != nil {
		return Transaction{}, err
	}
	now := unixNow()
	return Transaction{
		ID:                id,
		AmountCent:        *req.AmountCent,
		Currency:          "CNY",
		Direction:         req.Direction,
		TransactionTime:   *req.SMSTime,
		CategoryL1ID:      req.CategoryL1ID,
		CategoryL2ID:      stringPtrValue(req.CategoryL2ID),
		MemberID:          req.MemberID,
		AccountID:         req.AccountID,
		Counterparty:      strings.TrimSpace(req.Counterparty),
		Description:       strings.TrimSpace(req.Description),
		CreatedByDeviceID: device.ID,
		CreatedAt:         now,
		UpdatedAt:         now,
		Version:           1,
	}, nil
}

func isRawSMSField(key string) bool {
	switch strings.ToLower(strings.TrimSpace(key)) {
	case "raw_body", "raw_sms", "sms_body", "message", "body", "text", "content":
		return true
	default:
		return false
	}
}
