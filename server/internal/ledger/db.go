package ledger

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	_ "modernc.org/sqlite"
)

type App struct {
	cfg             Config
	db              *sql.DB
	secret          []byte
	backupMu        sync.Mutex
	storageMu       sync.Mutex
	pairingCodeMu   sync.Mutex
	activePlainCode *runtimePairingCode
}

type runtimePairingCode struct {
	id        string
	code      string
	expiresAt int64
}

func NewApp(cfg Config) (*App, error) {
	if cfg.Server.RequireHTTPS && !strings.HasPrefix(cfg.Server.PublicBaseURL, "https://") {
		return nil, fmt.Errorf("production HTTPS is required")
	}
	if err := ensureRuntimeDirs(cfg); err != nil {
		return nil, err
	}
	secret, err := loadOrCreateSecret(cfg.Security.SecretPath)
	if err != nil {
		return nil, fmt.Errorf("load server secret: %w", err)
	}
	db, err := openSQLite(cfg)
	if err != nil {
		return nil, err
	}
	app := &App{cfg: cfg, db: db, secret: secret}
	if err := app.migrate(context.Background()); err != nil {
		db.Close()
		return nil, err
	}
	return app, nil
}

func (a *App) Close() error {
	if a.db == nil {
		return nil
	}
	return a.db.Close()
}

func ensureRuntimeDirs(cfg Config) error {
	paths := []string{
		filepath.Dir(cfg.Database.Path),
		cfg.Storage.PhotosDir,
		cfg.Storage.ThumbnailsDir,
		cfg.Storage.TmpDir,
		cfg.Backup.Dir,
	}
	for _, path := range paths {
		if path == "." || path == "" {
			continue
		}
		if err := os.MkdirAll(path, 0o755); err != nil {
			return err
		}
	}
	return nil
}

func openSQLite(cfg Config) (*sql.DB, error) {
	if err := ensureDirForFile(cfg.Database.Path); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", cfg.Database.Path)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	pragmas := []string{
		"PRAGMA foreign_keys = ON",
		"PRAGMA journal_mode = WAL",
		fmt.Sprintf("PRAGMA busy_timeout = %d", cfg.Database.BusyTimeout),
		fmt.Sprintf("PRAGMA synchronous = %s", cfg.Database.Synchronous),
	}
	for _, pragma := range pragmas {
		if _, err := db.Exec(pragma); err != nil {
			db.Close()
			return nil, fmt.Errorf("%s: %w", pragma, err)
		}
	}
	return db, nil
}

func (a *App) migrate(ctx context.Context) error {
	if _, err := a.db.ExecContext(ctx, `
CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  applied_at INTEGER NOT NULL
)`); err != nil {
		return err
	}

	var version int
	err := a.db.QueryRowContext(ctx, `SELECT COALESCE(MAX(version), 0) FROM schema_migrations`).Scan(&version)
	if err != nil {
		return err
	}
	if version < 1 {
		if err := a.applyMigration(ctx, 1, "initial_schema", func(tx *sql.Tx) error {
			for _, stmt := range migrationV1Statements {
				if _, err := tx.ExecContext(ctx, stmt); err != nil {
					return fmt.Errorf("statement: %s: %w", stmt, err)
				}
			}
			return seedV1(ctx, tx)
		}); err != nil {
			return err
		}
		version = 1
	}
	if version < 2 {
		if err := a.applyMigration(ctx, 2, "sms_received_at_ms", func(tx *sql.Tx) error {
			for _, stmt := range migrationV2Statements {
				if _, err := tx.ExecContext(ctx, stmt); err != nil {
					return fmt.Errorf("statement: %s: %w", stmt, err)
				}
			}
			return nil
		}); err != nil {
			return err
		}
		version = 2
	}
	return nil
}

func (a *App) applyMigration(ctx context.Context, version int, name string, apply func(*sql.Tx) error) error {
	tx, err := a.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := apply(tx); err != nil {
		return fmt.Errorf("migration v%d %s: %w", version, name, err)
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO schema_migrations(version, name, applied_at) VALUES (?, ?, ?)`, version, name, unixNow()); err != nil {
		return fmt.Errorf("migration v%d %s: record migration: %w", version, name, err)
	}
	return tx.Commit()
}

var migrationV1Statements = []string{
	`CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('android', 'web')),
  token_hash TEXT NOT NULL UNIQUE,
  is_admin INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER,
  revoked_at INTEGER
)`,
	`CREATE TABLE pairing_codes (
  id TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL UNIQUE,
  expires_at INTEGER NOT NULL,
  used_at INTEGER,
  created_at INTEGER NOT NULL
)`,
	`CREATE TABLE categories (
  id TEXT PRIMARY KEY,
  parent_id TEXT,
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('income', 'expense', 'transfer')),
  sort_order INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
)`,
	`CREATE TABLE members (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
)`,
	`CREATE TABLE accounts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  masked_identifier TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
)`,
	`CREATE TABLE transactions (
  id TEXT PRIMARY KEY,
  amount_cent INTEGER NOT NULL,
  currency TEXT NOT NULL DEFAULT 'CNY',
  direction TEXT NOT NULL CHECK (direction IN ('income', 'expense', 'transfer')),
  transaction_time INTEGER NOT NULL,
  category_l1_id TEXT NOT NULL,
  category_l2_id TEXT,
  member_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  counterparty TEXT,
  description TEXT,
  source TEXT NOT NULL CHECK (source IN ('manual', 'sms', 'web')),
  source_ref TEXT,
  created_by_device_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  version INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY(category_l1_id) REFERENCES categories(id),
  FOREIGN KEY(category_l2_id) REFERENCES categories(id),
  FOREIGN KEY(member_id) REFERENCES members(id),
  FOREIGN KEY(account_id) REFERENCES accounts(id),
  FOREIGN KEY(created_by_device_id) REFERENCES devices(id)
)`,
	`CREATE INDEX idx_transactions_time ON transactions(transaction_time DESC)`,
	`CREATE INDEX idx_transactions_member ON transactions(member_id)`,
	`CREATE INDEX idx_transactions_account ON transactions(account_id)`,
	`CREATE INDEX idx_transactions_category_l1 ON transactions(category_l1_id)`,
	`CREATE INDEX idx_transactions_category_l2 ON transactions(category_l2_id)`,
	`CREATE INDEX idx_transactions_deleted ON transactions(deleted_at)`,
	`CREATE INDEX idx_transactions_source_ref ON transactions(source, source_ref)`,
	`CREATE TABLE attachments (
  id TEXT PRIMARY KEY,
  transaction_id TEXT NOT NULL,
  original_file_name TEXT,
  stored_file_name TEXT NOT NULL,
  thumbnail_file_name TEXT,
  sha256 TEXT NOT NULL,
  mime_type TEXT NOT NULL DEFAULT 'image/jpeg',
  size_bytes INTEGER NOT NULL,
  width INTEGER,
  height INTEGER,
  compression_status TEXT NOT NULL CHECK (compression_status IN ('pending', 'done', 'failed')),
  created_at INTEGER NOT NULL,
  deleted_at INTEGER,
  FOREIGN KEY(transaction_id) REFERENCES transactions(id)
)`,
	`CREATE TABLE sms_imports (
  id TEXT PRIMARY KEY,
  sms_hash TEXT NOT NULL UNIQUE,
  sender_masked TEXT,
  sms_time INTEGER NOT NULL,
  parsed_amount_cent INTEGER,
  parsed_direction TEXT,
  parsed_counterparty TEXT,
  parsed_account_hint TEXT,
  parsed_category_l1_id TEXT,
  parsed_category_l2_id TEXT,
  status TEXT NOT NULL CHECK (status IN ('candidate', 'confirmed', 'ignored')),
  transaction_id TEXT,
  device_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY(transaction_id) REFERENCES transactions(id),
  FOREIGN KEY(device_id) REFERENCES devices(id)
)`,
	`CREATE TABLE audit_logs (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  action TEXT NOT NULL,
  device_id TEXT NOT NULL,
  payload_json TEXT,
  created_at INTEGER NOT NULL,
  FOREIGN KEY(device_id) REFERENCES devices(id)
)`,
}

var migrationV2Statements = []string{
	`ALTER TABLE sms_imports ADD COLUMN sms_received_at_ms INTEGER NOT NULL DEFAULT 0`,
	`UPDATE sms_imports SET sms_received_at_ms = sms_time * 1000 WHERE sms_received_at_ms = 0`,
}

func seedV1(ctx context.Context, tx *sql.Tx) error {
	now := unixNow()
	if _, err := tx.ExecContext(ctx, `INSERT INTO members(id, name, sort_order, active, created_at, updated_at) VALUES ('member_self', '本人', 10, 1, ?, ?)`, now, now); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO accounts(id, name, type, masked_identifier, sort_order, active, created_at, updated_at) VALUES ('account_cash', '现金', 'cash', NULL, 10, 1, ?, ?)`, now, now); err != nil {
		return err
	}
	categories := []Category{
		{ID: "expense_food", Name: "餐饮", Type: "expense", SortOrder: 10, Active: true},
		{ID: "expense_food_meal", ParentID: "expense_food", Name: "正餐", Type: "expense", SortOrder: 11, Active: true},
		{ID: "expense_food_drink", ParentID: "expense_food", Name: "饮品", Type: "expense", SortOrder: 12, Active: true},
		{ID: "expense_transport", Name: "交通", Type: "expense", SortOrder: 20, Active: true},
		{ID: "expense_shopping", Name: "购物", Type: "expense", SortOrder: 30, Active: true},
		{ID: "expense_home", Name: "居家", Type: "expense", SortOrder: 40, Active: true},
		{ID: "expense_other", Name: "其他支出", Type: "expense", SortOrder: 90, Active: true},
		{ID: "income_salary", Name: "工资", Type: "income", SortOrder: 10, Active: true},
		{ID: "income_other", Name: "其他收入", Type: "income", SortOrder: 90, Active: true},
		{ID: "transfer_account", Name: "账户转账", Type: "transfer", SortOrder: 10, Active: true},
	}
	for _, c := range categories {
		var parent any
		if c.ParentID != "" {
			parent = c.ParentID
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO categories(id, parent_id, name, type, sort_order, active, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
			c.ID, parent, c.Name, c.Type, c.SortOrder, intFromBool(c.Active), now, now); err != nil {
			return err
		}
	}
	return nil
}
