package ledger

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
)

type transactionRequest struct {
	AmountCent      *int64  `json:"amount_cent"`
	Currency        string  `json:"currency"`
	Direction       string  `json:"direction"`
	TransactionTime *int64  `json:"transaction_time"`
	CategoryL1ID    string  `json:"category_l1_id"`
	CategoryL2ID    *string `json:"category_l2_id"`
	MemberID        string  `json:"member_id"`
	AccountID       string  `json:"account_id"`
	Counterparty    *string `json:"counterparty"`
	Description     *string `json:"description"`
}

func (a *App) handleCreateTransaction(w http.ResponseWriter, r *http.Request, device Device) {
	var req transactionRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "invalid JSON request")
		return
	}
	txObj, err := a.transactionFromCreateRequest(r.Context(), req, device)
	if err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	if err := a.insertTransaction(r.Context(), txObj, device.ID); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to create transaction")
		return
	}
	writeJSON(w, http.StatusCreated, txObj)
}

func (a *App) handleListTransactions(w http.ResponseWriter, r *http.Request, device Device) {
	list, err := a.listTransactions(r.Context(), r)
	if err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	writeJSON(w, http.StatusOK, list)
}

func (a *App) handleGetTransaction(w http.ResponseWriter, r *http.Request, device Device) {
	id := r.PathValue("id")
	txObj, err := a.getTransaction(r.Context(), id, false)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "not_found", "transaction not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to load transaction")
		return
	}
	writeJSON(w, http.StatusOK, txObj)
}

func (a *App) handlePatchTransaction(w http.ResponseWriter, r *http.Request, device Device) {
	id := r.PathValue("id")
	current, err := a.getTransaction(r.Context(), id, false)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "not_found", "transaction not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to load transaction")
		return
	}
	var req transactionRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "invalid JSON request")
		return
	}
	updated, err := a.transactionFromPatchRequest(r.Context(), current, req)
	if err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	if err := a.updateTransaction(r.Context(), updated, device.ID); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to update transaction")
		return
	}
	writeJSON(w, http.StatusOK, updated)
}

func (a *App) handleDeleteTransaction(w http.ResponseWriter, r *http.Request, device Device) {
	id := r.PathValue("id")
	now := unixNow()
	res, err := a.db.ExecContext(r.Context(), `UPDATE transactions SET deleted_at = ?, updated_at = ?, version = version + 1 WHERE id = ? AND deleted_at IS NULL`, now, now, id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to delete transaction")
		return
	}
	affected, _ := res.RowsAffected()
	if affected == 0 {
		writeError(w, http.StatusNotFound, "not_found", "transaction not found")
		return
	}
	_ = a.writeAudit(r.Context(), "transaction", id, "delete", device.ID, nil)
	writeJSON(w, http.StatusOK, map[string]any{"deleted": true, "id": id, "deleted_at": now})
}

func (a *App) transactionFromCreateRequest(ctx context.Context, req transactionRequest, device Device) (Transaction, error) {
	if req.AmountCent == nil || req.TransactionTime == nil {
		return Transaction{}, fmt.Errorf("amount_cent and transaction_time are required")
	}
	if *req.AmountCent <= 0 {
		return Transaction{}, fmt.Errorf("amount_cent must be a positive integer")
	}
	if req.Currency == "" {
		req.Currency = "CNY"
	}
	if req.Currency != "CNY" {
		return Transaction{}, fmt.Errorf("only CNY is supported in phase 1")
	}
	if err := a.validateTransactionRefs(ctx, req.Direction, req.CategoryL1ID, stringPtrValue(req.CategoryL2ID), req.MemberID, req.AccountID); err != nil {
		return Transaction{}, err
	}
	id, err := randomID("txn")
	if err != nil {
		return Transaction{}, err
	}
	now := unixNow()
	source := "manual"
	if device.Platform == "web" {
		source = "web"
	}
	return Transaction{
		ID:                id,
		AmountCent:        *req.AmountCent,
		Currency:          req.Currency,
		Direction:         req.Direction,
		TransactionTime:   *req.TransactionTime,
		CategoryL1ID:      req.CategoryL1ID,
		CategoryL2ID:      stringPtrValue(req.CategoryL2ID),
		MemberID:          req.MemberID,
		AccountID:         req.AccountID,
		Counterparty:      trimmedPtr(req.Counterparty),
		Description:       trimmedPtr(req.Description),
		Source:            source,
		CreatedByDeviceID: device.ID,
		CreatedAt:         now,
		UpdatedAt:         now,
		Version:           1,
	}, nil
}

func (a *App) transactionFromPatchRequest(ctx context.Context, current Transaction, req transactionRequest) (Transaction, error) {
	out := current
	if req.AmountCent != nil {
		if *req.AmountCent <= 0 {
			return Transaction{}, fmt.Errorf("amount_cent must be a positive integer")
		}
		out.AmountCent = *req.AmountCent
	}
	if req.Currency != "" {
		if req.Currency != "CNY" {
			return Transaction{}, fmt.Errorf("only CNY is supported in phase 1")
		}
		out.Currency = req.Currency
	}
	if req.Direction != "" {
		out.Direction = req.Direction
	}
	if req.TransactionTime != nil {
		out.TransactionTime = *req.TransactionTime
	}
	if req.CategoryL1ID != "" {
		out.CategoryL1ID = req.CategoryL1ID
	}
	if req.CategoryL2ID != nil {
		out.CategoryL2ID = strings.TrimSpace(*req.CategoryL2ID)
	}
	if req.MemberID != "" {
		out.MemberID = req.MemberID
	}
	if req.AccountID != "" {
		out.AccountID = req.AccountID
	}
	if req.Counterparty != nil {
		out.Counterparty = trimmedPtr(req.Counterparty)
	}
	if req.Description != nil {
		out.Description = trimmedPtr(req.Description)
	}
	if err := a.validateTransactionRefs(ctx, out.Direction, out.CategoryL1ID, out.CategoryL2ID, out.MemberID, out.AccountID); err != nil {
		return Transaction{}, err
	}
	out.UpdatedAt = unixNow()
	out.Version = current.Version + 1
	return out, nil
}

func (a *App) validateTransactionRefs(ctx context.Context, direction, categoryL1ID, categoryL2ID, memberID, accountID string) error {
	if !validDirection(direction) {
		return fmt.Errorf("direction must be income, expense or transfer")
	}
	if categoryL1ID == "" || memberID == "" || accountID == "" {
		return fmt.Errorf("category_l1_id, member_id and account_id are required")
	}
	var count int
	err := a.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM categories WHERE id = ? AND parent_id IS NULL AND type = ? AND active = 1 AND deleted_at IS NULL`, categoryL1ID, direction).Scan(&count)
	if err != nil || count == 0 {
		return fmt.Errorf("category_l1_id is invalid")
	}
	if categoryL2ID != "" {
		err := a.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM categories WHERE id = ? AND parent_id = ? AND type = ? AND active = 1 AND deleted_at IS NULL`, categoryL2ID, categoryL1ID, direction).Scan(&count)
		if err != nil || count == 0 {
			return fmt.Errorf("category_l2_id is invalid")
		}
	}
	err = a.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM members WHERE id = ? AND active = 1 AND deleted_at IS NULL`, memberID).Scan(&count)
	if err != nil || count == 0 {
		return fmt.Errorf("member_id is invalid")
	}
	err = a.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM accounts WHERE id = ? AND active = 1 AND deleted_at IS NULL`, accountID).Scan(&count)
	if err != nil || count == 0 {
		return fmt.Errorf("account_id is invalid")
	}
	return nil
}

func (a *App) insertTransaction(ctx context.Context, t Transaction, deviceID string) error {
	_, err := a.db.ExecContext(ctx, `INSERT INTO transactions(id, amount_cent, currency, direction, transaction_time, category_l1_id, category_l2_id, member_id, account_id, counterparty, description, source, source_ref, created_by_device_id, created_at, updated_at, version) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		t.ID, t.AmountCent, t.Currency, t.Direction, t.TransactionTime, t.CategoryL1ID, nullString(t.CategoryL2ID), t.MemberID, t.AccountID, nullString(t.Counterparty), nullString(t.Description), t.Source, nullString(t.SourceRef), t.CreatedByDeviceID, t.CreatedAt, t.UpdatedAt, t.Version)
	if err != nil {
		return err
	}
	return a.writeAudit(ctx, "transaction", t.ID, "create", deviceID, nil)
}

func (a *App) updateTransaction(ctx context.Context, t Transaction, deviceID string) error {
	_, err := a.db.ExecContext(ctx, `UPDATE transactions SET amount_cent = ?, currency = ?, direction = ?, transaction_time = ?, category_l1_id = ?, category_l2_id = ?, member_id = ?, account_id = ?, counterparty = ?, description = ?, updated_at = ?, version = ? WHERE id = ? AND deleted_at IS NULL`,
		t.AmountCent, t.Currency, t.Direction, t.TransactionTime, t.CategoryL1ID, nullString(t.CategoryL2ID), t.MemberID, t.AccountID, nullString(t.Counterparty), nullString(t.Description), t.UpdatedAt, t.Version, t.ID)
	if err != nil {
		return err
	}
	return a.writeAudit(ctx, "transaction", t.ID, "update", deviceID, nil)
}

func (a *App) getTransaction(ctx context.Context, id string, includeDeleted bool) (Transaction, error) {
	query := transactionSelectSQL + ` WHERE id = ?`
	if !includeDeleted {
		query += ` AND deleted_at IS NULL`
	}
	return scanTransaction(a.db.QueryRowContext(ctx, query, id))
}

func (a *App) listTransactions(ctx context.Context, r *http.Request) (TransactionList, error) {
	values := r.URL.Query()
	page := parsePositiveInt(values.Get("page"), 1, 0)
	pageSize := parsePositiveInt(values.Get("page_size"), 50, 200)
	conditions := []string{}
	args := []any{}
	if values.Get("include_deleted") != "true" {
		conditions = append(conditions, "deleted_at IS NULL")
	}
	for _, item := range []struct {
		key string
		col string
	}{
		{"direction", "direction"},
		{"category_l1_id", "category_l1_id"},
		{"category_l2_id", "category_l2_id"},
		{"member_id", "member_id"},
		{"account_id", "account_id"},
	} {
		if raw := values.Get(item.key); raw != "" {
			conditions = append(conditions, item.col+" = ?")
			args = append(args, raw)
		}
	}
	if raw := values.Get("from"); raw != "" {
		n, err := strconv.ParseInt(raw, 10, 64)
		if err != nil {
			return TransactionList{}, fmt.Errorf("from must be a unix timestamp")
		}
		conditions = append(conditions, "transaction_time >= ?")
		args = append(args, n)
	}
	if raw := values.Get("to"); raw != "" {
		n, err := strconv.ParseInt(raw, 10, 64)
		if err != nil {
			return TransactionList{}, fmt.Errorf("to must be a unix timestamp")
		}
		conditions = append(conditions, "transaction_time <= ?")
		args = append(args, n)
	}
	if raw := strings.TrimSpace(values.Get("keyword")); raw != "" {
		conditions = append(conditions, "(description LIKE ? OR counterparty LIKE ?)")
		keyword := "%" + raw + "%"
		args = append(args, keyword, keyword)
	}
	where := ""
	if len(conditions) > 0 {
		where = " WHERE " + strings.Join(conditions, " AND ")
	}
	var total int
	if err := a.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM transactions`+where, args...).Scan(&total); err != nil {
		return TransactionList{}, err
	}
	queryArgs := append([]any{}, args...)
	queryArgs = append(queryArgs, pageSize, (page-1)*pageSize)
	rows, err := a.db.QueryContext(ctx, transactionSelectSQL+where+` ORDER BY transaction_time DESC, created_at DESC LIMIT ? OFFSET ?`, queryArgs...)
	if err != nil {
		return TransactionList{}, err
	}
	defer rows.Close()
	items := []Transaction{}
	for rows.Next() {
		t, err := scanTransaction(rows)
		if err != nil {
			return TransactionList{}, err
		}
		items = append(items, t)
	}
	if err := rows.Err(); err != nil {
		return TransactionList{}, err
	}
	return TransactionList{Items: items, Page: page, PageSize: pageSize, Total: total}, nil
}

const transactionSelectSQL = `SELECT id, amount_cent, currency, direction, transaction_time, category_l1_id, COALESCE(category_l2_id, ''), member_id, account_id, COALESCE(counterparty, ''), COALESCE(description, ''), source, COALESCE(source_ref, ''), created_by_device_id, created_at, updated_at, deleted_at, version FROM transactions`

type scanner interface {
	Scan(dest ...any) error
}

func scanTransaction(row scanner) (Transaction, error) {
	var t Transaction
	var deletedAt sql.NullInt64
	err := row.Scan(&t.ID, &t.AmountCent, &t.Currency, &t.Direction, &t.TransactionTime, &t.CategoryL1ID, &t.CategoryL2ID, &t.MemberID, &t.AccountID, &t.Counterparty, &t.Description, &t.Source, &t.SourceRef, &t.CreatedByDeviceID, &t.CreatedAt, &t.UpdatedAt, &deletedAt, &t.Version)
	if deletedAt.Valid {
		t.DeletedAt = &deletedAt.Int64
	}
	return t, err
}

func validDirection(direction string) bool {
	return direction == "income" || direction == "expense" || direction == "transfer"
}

func stringPtrValue(v *string) string {
	if v == nil {
		return ""
	}
	return strings.TrimSpace(*v)
}

func trimmedPtr(v *string) string {
	if v == nil {
		return ""
	}
	return strings.TrimSpace(*v)
}

func nullString(v string) any {
	v = strings.TrimSpace(v)
	if v == "" {
		return nil
	}
	return v
}

func (a *App) writeAudit(ctx context.Context, entityType, entityID, action, deviceID string, payload *string) error {
	id, err := randomID("audit")
	if err != nil {
		return err
	}
	var p any
	if payload != nil && strings.TrimSpace(*payload) != "" {
		p = strings.TrimSpace(*payload)
	}
	_, err = a.db.ExecContext(ctx, `INSERT INTO audit_logs(id, entity_type, entity_id, action, device_id, payload_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)`,
		id, entityType, entityID, action, deviceID, p, unixNow())
	return err
}
