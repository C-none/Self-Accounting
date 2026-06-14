package ledger

import (
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"strings"
)

type categoryRequest struct {
	Name     string  `json:"name"`
	Type     string  `json:"type"`
	ParentID *string `json:"parent_id"`
}

type memberRequest struct {
	Name string `json:"name"`
}

type accountRequest struct {
	Name             string `json:"name"`
	Type             string `json:"type"`
	MaskedIdentifier string `json:"masked_identifier"`
}

func (a *App) handleCreateCategory(w http.ResponseWriter, r *http.Request, device Device) {
	var req categoryRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "invalid JSON request")
		return
	}
	cat, err := a.categoryFromRequest(r, "", req)
	if err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	id, err := randomID("cat")
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to create category")
		return
	}
	cat.ID = id
	if err := a.insertCategory(r, cat); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to save category")
		return
	}
	_ = a.writeAudit(r.Context(), "category", cat.ID, "create", device.ID, nil)
	writeJSON(w, http.StatusCreated, cat)
}

func (a *App) handlePatchCategory(w http.ResponseWriter, r *http.Request, device Device) {
	id := r.PathValue("id")
	current, err := a.getCategory(r, id)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "not_found", "category not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to load category")
		return
	}
	var req categoryRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "invalid JSON request")
		return
	}
	next, err := a.categoryFromRequest(r, id, req)
	if err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	if current.ParentID == "" && next.ParentID != "" {
		if ok, err := a.categoryHasActiveChildren(r, id); err != nil {
			writeError(w, http.StatusInternalServerError, "internal_error", "failed to inspect category")
			return
		} else if ok {
			writeError(w, http.StatusBadRequest, "validation_error", "category with child categories cannot become a child category")
			return
		}
	}
	if current.Type != next.Type {
		if ok, err := a.categoryIsReferenced(r, id); err != nil {
			writeError(w, http.StatusInternalServerError, "internal_error", "failed to inspect category usage")
			return
		} else if ok {
			writeError(w, http.StatusBadRequest, "validation_error", "category used by transactions cannot change direction")
			return
		}
	}
	next.ID = id
	next.SortOrder = current.SortOrder
	next.Active = true
	if err := a.updateCategory(r, next); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to update category")
		return
	}
	_ = a.writeAudit(r.Context(), "category", id, "update", device.ID, nil)
	writeJSON(w, http.StatusOK, next)
}

func (a *App) handleDeleteCategory(w http.ResponseWriter, r *http.Request, device Device) {
	id := r.PathValue("id")
	if _, err := a.getCategory(r, id); errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "not_found", "category not found")
		return
	} else if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to load category")
		return
	}
	if ok, err := a.categoryIsReferenced(r, id); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to inspect category usage")
		return
	} else if ok {
		writeError(w, http.StatusBadRequest, "validation_error", "category is used by transactions and cannot be deleted")
		return
	}
	if ok, err := a.categoryHasActiveChildren(r, id); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to inspect category")
		return
	} else if ok {
		writeError(w, http.StatusBadRequest, "validation_error", "delete child categories first")
		return
	}
	if err := a.softDeleteRow(r, "categories", id); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to delete category")
		return
	}
	_ = a.writeAudit(r.Context(), "category", id, "delete", device.ID, nil)
	writeJSON(w, http.StatusOK, map[string]any{"deleted": true, "id": id})
}

func (a *App) handleCreateMember(w http.ResponseWriter, r *http.Request, device Device) {
	var req memberRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "invalid JSON request")
		return
	}
	name := strings.TrimSpace(req.Name)
	if name == "" {
		writeError(w, http.StatusBadRequest, "validation_error", "name is required")
		return
	}
	id, err := randomID("member")
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to create member")
		return
	}
	now := unixNow()
	m := Member{ID: id, Name: name, SortOrder: 100, Active: true}
	if _, err := a.db.ExecContext(r.Context(), `INSERT INTO members(id, name, sort_order, active, created_at, updated_at) VALUES (?, ?, ?, 1, ?, ?)`, id, name, m.SortOrder, now, now); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to save member")
		return
	}
	_ = a.writeAudit(r.Context(), "member", id, "create", device.ID, nil)
	writeJSON(w, http.StatusCreated, m)
}

func (a *App) handlePatchMember(w http.ResponseWriter, r *http.Request, device Device) {
	id := r.PathValue("id")
	var req memberRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "invalid JSON request")
		return
	}
	name := strings.TrimSpace(req.Name)
	if name == "" {
		writeError(w, http.StatusBadRequest, "validation_error", "name is required")
		return
	}
	result, err := a.db.ExecContext(r.Context(), `UPDATE members SET name = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL AND active = 1`, name, unixNow(), id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to update member")
		return
	}
	if affected, _ := result.RowsAffected(); affected == 0 {
		writeError(w, http.StatusNotFound, "not_found", "member not found")
		return
	}
	_ = a.writeAudit(r.Context(), "member", id, "update", device.ID, nil)
	writeJSON(w, http.StatusOK, Member{ID: id, Name: name, Active: true})
}

func (a *App) handleDeleteMember(w http.ResponseWriter, r *http.Request, device Device) {
	id := r.PathValue("id")
	if ok, err := a.rowIsReferenced(r, "transactions", "member_id", id); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to inspect member usage")
		return
	} else if ok {
		writeError(w, http.StatusBadRequest, "validation_error", "member is used by transactions and cannot be deleted")
		return
	}
	if err := a.softDeleteRow(r, "members", id); errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "not_found", "member not found")
		return
	} else if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to delete member")
		return
	}
	_ = a.writeAudit(r.Context(), "member", id, "delete", device.ID, nil)
	writeJSON(w, http.StatusOK, map[string]any{"deleted": true, "id": id})
}

func (a *App) handleCreateAccount(w http.ResponseWriter, r *http.Request, device Device) {
	var req accountRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "invalid JSON request")
		return
	}
	acc, err := accountFromRequest(req)
	if err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	id, err := randomID("account")
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to create account")
		return
	}
	now := unixNow()
	acc.ID = id
	acc.SortOrder = 100
	acc.Active = true
	if _, err := a.db.ExecContext(r.Context(), `INSERT INTO accounts(id, name, type, masked_identifier, sort_order, active, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 1, ?, ?)`, acc.ID, acc.Name, acc.Type, nullString(acc.MaskedIdentifier), acc.SortOrder, now, now); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to save account")
		return
	}
	_ = a.writeAudit(r.Context(), "account", id, "create", device.ID, nil)
	writeJSON(w, http.StatusCreated, acc)
}

func (a *App) handlePatchAccount(w http.ResponseWriter, r *http.Request, device Device) {
	id := r.PathValue("id")
	var req accountRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "invalid JSON request")
		return
	}
	acc, err := accountFromRequest(req)
	if err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	result, err := a.db.ExecContext(r.Context(), `UPDATE accounts SET name = ?, type = ?, masked_identifier = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL AND active = 1`, acc.Name, acc.Type, nullString(acc.MaskedIdentifier), unixNow(), id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to update account")
		return
	}
	if affected, _ := result.RowsAffected(); affected == 0 {
		writeError(w, http.StatusNotFound, "not_found", "account not found")
		return
	}
	acc.ID = id
	acc.Active = true
	_ = a.writeAudit(r.Context(), "account", id, "update", device.ID, nil)
	writeJSON(w, http.StatusOK, acc)
}

func (a *App) handleDeleteAccount(w http.ResponseWriter, r *http.Request, device Device) {
	id := r.PathValue("id")
	if ok, err := a.rowIsReferenced(r, "transactions", "account_id", id); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to inspect account usage")
		return
	} else if ok {
		writeError(w, http.StatusBadRequest, "validation_error", "account is used by transactions and cannot be deleted")
		return
	}
	if err := a.softDeleteRow(r, "accounts", id); errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "not_found", "account not found")
		return
	} else if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to delete account")
		return
	}
	_ = a.writeAudit(r.Context(), "account", id, "delete", device.ID, nil)
	writeJSON(w, http.StatusOK, map[string]any{"deleted": true, "id": id})
}

func (a *App) categoryFromRequest(r *http.Request, id string, req categoryRequest) (Category, error) {
	name := strings.TrimSpace(req.Name)
	typ := strings.TrimSpace(req.Type)
	parentID := ""
	if req.ParentID != nil {
		parentID = strings.TrimSpace(*req.ParentID)
	}
	if name == "" {
		return Category{}, fmt.Errorf("name is required")
	}
	if !validCategoryType(typ) {
		return Category{}, fmt.Errorf("type must be income, expense or transfer")
	}
	if parentID != "" {
		if parentID == id {
			return Category{}, fmt.Errorf("category cannot be its own parent")
		}
		var count int
		err := a.db.QueryRowContext(r.Context(), `SELECT COUNT(*) FROM categories WHERE id = ? AND parent_id IS NULL AND type = ? AND active = 1 AND deleted_at IS NULL`, parentID, typ).Scan(&count)
		if err != nil {
			return Category{}, err
		}
		if count == 0 {
			return Category{}, fmt.Errorf("parent category is invalid")
		}
	}
	return Category{Name: name, Type: typ, ParentID: parentID, SortOrder: 100, Active: true}, nil
}

func accountFromRequest(req accountRequest) (Account, error) {
	name := strings.TrimSpace(req.Name)
	typ := strings.TrimSpace(req.Type)
	if name == "" {
		return Account{}, fmt.Errorf("name is required")
	}
	if typ == "" {
		typ = "bank"
	}
	return Account{
		Name:             name,
		Type:             typ,
		MaskedIdentifier: normalizeMaskedIdentifier(req.MaskedIdentifier),
	}, nil
}

func normalizeMaskedIdentifier(raw string) string {
	digits := make([]rune, 0, 4)
	for _, ch := range strings.TrimSpace(raw) {
		if ch >= '0' && ch <= '9' {
			digits = append(digits, ch)
		}
	}
	if len(digits) <= 4 {
		return string(digits)
	}
	return string(digits[len(digits)-4:])
}

func (a *App) getCategory(r *http.Request, id string) (Category, error) {
	var c Category
	var active int
	err := a.db.QueryRowContext(r.Context(), `SELECT id, COALESCE(parent_id, ''), name, type, sort_order, active FROM categories WHERE id = ? AND deleted_at IS NULL AND active = 1`, id).Scan(&c.ID, &c.ParentID, &c.Name, &c.Type, &c.SortOrder, &active)
	c.Active = boolFromInt(active)
	return c, err
}

func (a *App) insertCategory(r *http.Request, c Category) error {
	var parent any
	if c.ParentID != "" {
		parent = c.ParentID
	}
	now := unixNow()
	_, err := a.db.ExecContext(r.Context(), `INSERT INTO categories(id, parent_id, name, type, sort_order, active, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 1, ?, ?)`, c.ID, parent, c.Name, c.Type, c.SortOrder, now, now)
	return err
}

func (a *App) updateCategory(r *http.Request, c Category) error {
	var parent any
	if c.ParentID != "" {
		parent = c.ParentID
	}
	_, err := a.db.ExecContext(r.Context(), `UPDATE categories SET parent_id = ?, name = ?, type = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL AND active = 1`, parent, c.Name, c.Type, unixNow(), c.ID)
	return err
}

func (a *App) categoryIsReferenced(r *http.Request, id string) (bool, error) {
	var count int
	err := a.db.QueryRowContext(r.Context(), `SELECT COUNT(*) FROM transactions WHERE deleted_at IS NULL AND (category_l1_id = ? OR category_l2_id = ?)`, id, id).Scan(&count)
	return count > 0, err
}

func (a *App) categoryHasActiveChildren(r *http.Request, id string) (bool, error) {
	var count int
	err := a.db.QueryRowContext(r.Context(), `SELECT COUNT(*) FROM categories WHERE parent_id = ? AND active = 1 AND deleted_at IS NULL`, id).Scan(&count)
	return count > 0, err
}

func (a *App) rowIsReferenced(r *http.Request, table, column, id string) (bool, error) {
	var count int
	query := fmt.Sprintf(`SELECT COUNT(*) FROM %s WHERE deleted_at IS NULL AND %s = ?`, table, column)
	err := a.db.QueryRowContext(r.Context(), query, id).Scan(&count)
	return count > 0, err
}

func (a *App) softDeleteRow(r *http.Request, table, id string) error {
	query := fmt.Sprintf(`UPDATE %s SET deleted_at = ?, active = 0, updated_at = ? WHERE id = ? AND deleted_at IS NULL AND active = 1`, table)
	result, err := a.db.ExecContext(r.Context(), query, unixNow(), unixNow(), id)
	if err != nil {
		return err
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if affected == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func validCategoryType(value string) bool {
	return value == "income" || value == "expense" || value == "transfer"
}
