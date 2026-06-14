package ledger

import (
	"context"
	"database/sql"
)

func (a *App) activeAdminCount(ctx context.Context) (int, error) {
	var count int
	err := a.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM devices WHERE active = 1 AND is_admin = 1 AND revoked_at IS NULL`).Scan(&count)
	return count, err
}

func activeAdminCountTx(ctx context.Context, tx *sql.Tx) (int, error) {
	var count int
	err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM devices WHERE active = 1 AND is_admin = 1 AND revoked_at IS NULL`).Scan(&count)
	return count, err
}

func (a *App) listCategories(ctx context.Context) ([]Category, error) {
	rows, err := a.db.QueryContext(ctx, `SELECT id, COALESCE(parent_id, ''), name, type, sort_order, active FROM categories WHERE deleted_at IS NULL AND active = 1 ORDER BY type, sort_order, name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Category
	for rows.Next() {
		var c Category
		var active int
		if err := rows.Scan(&c.ID, &c.ParentID, &c.Name, &c.Type, &c.SortOrder, &active); err != nil {
			return nil, err
		}
		c.Active = boolFromInt(active)
		out = append(out, c)
	}
	return out, rows.Err()
}

func (a *App) listMembers(ctx context.Context) ([]Member, error) {
	rows, err := a.db.QueryContext(ctx, `SELECT id, name, sort_order, active FROM members WHERE deleted_at IS NULL AND active = 1 ORDER BY sort_order, name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Member
	for rows.Next() {
		var m Member
		var active int
		if err := rows.Scan(&m.ID, &m.Name, &m.SortOrder, &active); err != nil {
			return nil, err
		}
		m.Active = boolFromInt(active)
		out = append(out, m)
	}
	return out, rows.Err()
}

func (a *App) listAccounts(ctx context.Context) ([]Account, error) {
	rows, err := a.db.QueryContext(ctx, `SELECT id, name, type, COALESCE(masked_identifier, ''), sort_order, active FROM accounts WHERE deleted_at IS NULL AND active = 1 ORDER BY sort_order, name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Account
	for rows.Next() {
		var acc Account
		var active int
		if err := rows.Scan(&acc.ID, &acc.Name, &acc.Type, &acc.MaskedIdentifier, &acc.SortOrder, &active); err != nil {
			return nil, err
		}
		acc.Active = boolFromInt(active)
		out = append(out, acc)
	}
	return out, rows.Err()
}
