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

type categoryReorderRequest struct {
	Type       string   `json:"type"`
	ParentID   *string  `json:"parent_id"`
	OrderedIDs []string `json:"ordered_ids"`
}

type memberRequest struct {
	Name string `json:"name"`
}

type reorderRequest struct {
	OrderedIDs []string `json:"ordered_ids"`
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
	sortOrder, err := a.nextCategorySortOrder(r, cat.Type, cat.ParentID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to inspect category order")
		return
	}
	cat.SortOrder = sortOrder
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

func (a *App) handleReorderCategories(w http.ResponseWriter, r *http.Request, device Device) {
	var req categoryReorderRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "invalid JSON request")
		return
	}
	typ := strings.TrimSpace(req.Type)
	if !validCategoryType(typ) {
		writeError(w, http.StatusBadRequest, "validation_error", "type must be income, expense or transfer")
		return
	}
	parentID := ""
	if req.ParentID != nil {
		parentID = strings.TrimSpace(*req.ParentID)
	}
	if parentID != "" {
		var count int
		err := a.db.QueryRowContext(r.Context(), `SELECT COUNT(*) FROM categories WHERE id = ? AND parent_id IS NULL AND type = ? AND active = 1 AND deleted_at IS NULL`, parentID, typ).Scan(&count)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "internal_error", "failed to inspect parent category")
			return
		}
		if count == 0 {
			writeError(w, http.StatusBadRequest, "validation_error", "parent category is invalid")
			return
		}
	}
	existing, err := a.categoryIDsForScope(r, typ, parentID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to load category order")
		return
	}
	if err := validateOrderedIDs(existing, req.OrderedIDs); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	if err := a.reorderRows(r, "categories", req.OrderedIDs); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to update category order")
		return
	}
	_ = a.writeAudit(r.Context(), "category", typ+":"+parentID, "reorder", device.ID, nil)
	writeJSON(w, http.StatusOK, map[string]any{"reordered": true, "ordered_ids": req.OrderedIDs})
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
	sortOrder, err := a.nextTableSortOrder(r, "members")
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to inspect member order")
		return
	}
	m := Member{ID: id, Name: name, SortOrder: sortOrder, Active: true}
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

func (a *App) handleReorderMembers(w http.ResponseWriter, r *http.Request, device Device) {
	var req reorderRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "invalid JSON request")
		return
	}
	existing, err := a.activeIDsForTable(r, "members")
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to load member order")
		return
	}
	if err := validateOrderedIDs(existing, req.OrderedIDs); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	if err := a.reorderRows(r, "members", req.OrderedIDs); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to update member order")
		return
	}
	_ = a.writeAudit(r.Context(), "member", "all", "reorder", device.ID, nil)
	writeJSON(w, http.StatusOK, map[string]any{"reordered": true, "ordered_ids": req.OrderedIDs})
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
	sortOrder, err := a.nextTableSortOrder(r, "accounts")
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to inspect account order")
		return
	}
	acc.SortOrder = sortOrder
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

func (a *App) handleReorderAccounts(w http.ResponseWriter, r *http.Request, device Device) {
	var req reorderRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "invalid JSON request")
		return
	}
	existing, err := a.activeIDsForTable(r, "accounts")
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to load account order")
		return
	}
	if err := validateOrderedIDs(existing, req.OrderedIDs); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	if err := a.reorderRows(r, "accounts", req.OrderedIDs); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to update account order")
		return
	}
	_ = a.writeAudit(r.Context(), "account", "all", "reorder", device.ID, nil)
	writeJSON(w, http.StatusOK, map[string]any{"reordered": true, "ordered_ids": req.OrderedIDs})
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

func (a *App) nextCategorySortOrder(r *http.Request, typ, parentID string) (int, error) {
	var query string
	var args []any
	if parentID == "" {
		query = `SELECT COALESCE(MAX(sort_order), 0) + 10 FROM categories WHERE type = ? AND parent_id IS NULL AND active = 1 AND deleted_at IS NULL`
		args = []any{typ}
	} else {
		query = `SELECT COALESCE(MAX(sort_order), 0) + 10 FROM categories WHERE type = ? AND parent_id = ? AND active = 1 AND deleted_at IS NULL`
		args = []any{typ, parentID}
	}
	var next int
	err := a.db.QueryRowContext(r.Context(), query, args...).Scan(&next)
	return next, err
}

func (a *App) nextTableSortOrder(r *http.Request, table string) (int, error) {
	var next int
	err := a.db.QueryRowContext(r.Context(), fmt.Sprintf(`SELECT COALESCE(MAX(sort_order), 0) + 10 FROM %s WHERE active = 1 AND deleted_at IS NULL`, table)).Scan(&next)
	return next, err
}

func (a *App) categoryIDsForScope(r *http.Request, typ, parentID string) ([]string, error) {
	var rows *sql.Rows
	var err error
	if parentID == "" {
		rows, err = a.db.QueryContext(r.Context(), `SELECT id FROM categories WHERE type = ? AND parent_id IS NULL AND active = 1 AND deleted_at IS NULL ORDER BY sort_order, name`, typ)
	} else {
		rows, err = a.db.QueryContext(r.Context(), `SELECT id FROM categories WHERE type = ? AND parent_id = ? AND active = 1 AND deleted_at IS NULL ORDER BY sort_order, name`, typ, parentID)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanIDRows(rows)
}

func (a *App) activeIDsForTable(r *http.Request, table string) ([]string, error) {
	rows, err := a.db.QueryContext(r.Context(), fmt.Sprintf(`SELECT id FROM %s WHERE active = 1 AND deleted_at IS NULL ORDER BY sort_order, name`, table))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanIDRows(rows)
}

func scanIDRows(rows *sql.Rows) ([]string, error) {
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func validateOrderedIDs(existing, ordered []string) error {
	if len(existing) != len(ordered) {
		return fmt.Errorf("ordered_ids must include every item in scope")
	}
	existingSet := make(map[string]bool, len(existing))
	for _, id := range existing {
		existingSet[id] = true
	}
	seen := make(map[string]bool, len(ordered))
	for _, id := range ordered {
		if strings.TrimSpace(id) == "" {
			return fmt.Errorf("ordered_ids must not contain empty id")
		}
		if seen[id] {
			return fmt.Errorf("ordered_ids must not contain duplicate id")
		}
		seen[id] = true
		if !existingSet[id] {
			return fmt.Errorf("ordered_ids contains id outside the requested scope")
		}
	}
	return nil
}

func (a *App) reorderRows(r *http.Request, table string, orderedIDs []string) error {
	tx, err := a.db.BeginTx(r.Context(), nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	now := unixNow()
	query := fmt.Sprintf(`UPDATE %s SET sort_order = ?, updated_at = ? WHERE id = ? AND active = 1 AND deleted_at IS NULL`, table)
	for i, id := range orderedIDs {
		result, err := tx.ExecContext(r.Context(), query, (i+1)*10, now, id)
		if err != nil {
			return err
		}
		if affected, err := result.RowsAffected(); err != nil {
			return err
		} else if affected != 1 {
			return sql.ErrNoRows
		}
	}
	return tx.Commit()
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
