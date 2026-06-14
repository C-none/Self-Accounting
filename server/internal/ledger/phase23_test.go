package ledger

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/color"
	"image/jpeg"
	"io"
	"mime/multipart"
	"net/http"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestAttachmentUploadCompressAndRead(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg is not available")
	}
	ts := newTestServer(t)
	token, _ := ts.pairDevice(t, "", "web", "web-admin")
	var txObj Transaction
	ts.request(t, http.MethodPost, "/api/transactions", token, testTxnBody(990, "expense"), http.StatusCreated, &txObj)

	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	if err := writer.WriteField("transaction_id", txObj.ID); err != nil {
		t.Fatalf("WriteField() error = %v", err)
	}
	part, err := writer.CreateFormFile("file", "receipt.jpg")
	if err != nil {
		t.Fatalf("CreateFormFile() error = %v", err)
	}
	if _, err := part.Write(testJPEG(t)); err != nil {
		t.Fatalf("write image part error = %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("multipart close error = %v", err)
	}

	req, err := http.NewRequest(http.MethodPost, ts.server.URL+"/api/attachments", &body)
	if err != nil {
		t.Fatalf("NewRequest() error = %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	resp, err := ts.server.Client().Do(req)
	if err != nil {
		t.Fatalf("upload attachment error = %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		data, _ := io.ReadAll(resp.Body)
		t.Fatalf("upload status = %d, body = %s", resp.StatusCode, data)
	}
	var att Attachment
	if err := json.NewDecoder(resp.Body).Decode(&att); err != nil {
		t.Fatalf("decode attachment error = %v", err)
	}
	if att.ID == "" || att.TransactionID != txObj.ID || att.CompressionStatus != "done" || att.SizeBytes <= 0 {
		t.Fatalf("attachment = %+v", att)
	}
	if filepath.IsAbs(att.StoredFileName) || strings.ContainsAny(att.StoredFileName, `/\`) {
		t.Fatalf("stored file name should be relative base name: %q", att.StoredFileName)
	}

	var listed struct {
		Items []Attachment `json:"items"`
	}
	ts.request(t, http.MethodGet, "/api/transactions/"+txObj.ID+"/attachments", token, nil, http.StatusOK, &listed)
	if len(listed.Items) != 1 || listed.Items[0].ID != att.ID {
		t.Fatalf("listed attachments = %+v", listed.Items)
	}
	assertImageResponse(t, ts, token, "/api/attachments/"+att.ID)
	assertImageResponse(t, ts, token, "/api/attachments/"+att.ID+"/thumbnail")
}

func TestAdminCheckpointAndBackup(t *testing.T) {
	ts := newTestServer(t)
	adminToken, _ := ts.pairDevice(t, "", "web", "web-admin")
	androidToken, isAdmin := ts.pairDevice(t, adminToken, "android", "android-phone")
	if isAdmin {
		t.Fatalf("second device must not be admin")
	}

	ts.request(t, http.MethodPost, "/api/admin/checkpoint", androidToken, nil, http.StatusForbidden, nil)
	var checkpoint map[string]any
	ts.request(t, http.MethodPost, "/api/admin/checkpoint", adminToken, nil, http.StatusOK, &checkpoint)
	if _, ok := checkpoint["busy"]; !ok {
		t.Fatalf("checkpoint response = %+v", checkpoint)
	}

	var backup struct {
		FileName  string `json:"file_name"`
		SizeBytes int64  `json:"size_bytes"`
	}
	ts.request(t, http.MethodPost, "/api/admin/backup", adminToken, nil, http.StatusOK, &backup)
	if backup.FileName == "" || backup.SizeBytes <= 0 {
		t.Fatalf("backup response = %+v", backup)
	}
	zipPath := filepath.Join(ts.app.cfg.Backup.Dir, backup.FileName)
	reader, err := zip.OpenReader(zipPath)
	if err != nil {
		t.Fatalf("open backup zip error = %v", err)
	}
	defer reader.Close()
	names := map[string]bool{}
	var configExport string
	for _, file := range reader.File {
		names[file.Name] = true
		if file.Name == "config.export.json" {
			rc, err := file.Open()
			if err != nil {
				t.Fatalf("open config export error = %v", err)
			}
			data, _ := io.ReadAll(rc)
			_ = rc.Close()
			configExport = string(data)
		}
	}
	for _, want := range []string{"manifest.json", "app.db", "config.export.json", "photos/", "thumbnails/"} {
		if !names[want] {
			t.Fatalf("backup zip missing %s; names=%v", want, names)
		}
	}
	if strings.Contains(strings.ToLower(configExport), "secret") {
		t.Fatalf("config export must not contain server secret: %s", configExport)
	}
}

func TestSMSImportRejectsRawBodyAndDeduplicates(t *testing.T) {
	ts := newTestServer(t)
	adminToken, _ := ts.pairDevice(t, "", "web", "web-admin")
	androidToken, _ := ts.pairDevice(t, adminToken, "android", "android-phone")

	now := time.Date(2026, 6, 1, 18, 0, 0, 0, time.UTC).Unix()
	receivedAtMS := time.Date(2026, 6, 1, 18, 1, 2, 0, time.UTC).UnixNano() / int64(time.Millisecond)
	body := map[string]any{
		"sms_hash":           "hash-phase3-001",
		"sender_masked":      "955**",
		"sms_received_at_ms": receivedAtMS,
		"sms_time":           now,
		"amount_cent":        3210,
		"direction":          "expense",
		"counterparty":       "Coffee",
		"account_hint":       "招商尾号1234",
		"account_id":         "account_cash",
		"category_l1_id":     "expense_food",
		"category_l2_id":     "expense_food_drink",
		"member_id":          "member_self",
		"description":        "短信导入确认",
	}
	ts.request(t, http.MethodPost, "/api/sms/imports", adminToken, body, http.StatusForbidden, nil)
	missingReceivedAt := map[string]any{}
	for key, value := range body {
		if key != "sms_received_at_ms" {
			missingReceivedAt[key] = value
		}
	}
	ts.request(t, http.MethodPost, "/api/sms/imports", androidToken, missingReceivedAt, http.StatusBadRequest, nil)
	invalidReceivedAt := map[string]any{}
	for key, value := range body {
		invalidReceivedAt[key] = value
	}
	invalidReceivedAt["sms_received_at_ms"] = 0
	ts.request(t, http.MethodPost, "/api/sms/imports", androidToken, invalidReceivedAt, http.StatusBadRequest, nil)
	rawBody := map[string]any{}
	for key, value := range body {
		rawBody[key] = value
	}
	rawBody["raw_body"] = "完整短信原文不允许上传"
	ts.request(t, http.MethodPost, "/api/sms/imports", androidToken, rawBody, http.StatusBadRequest, nil)

	var created struct {
		ImportID    string      `json:"import_id"`
		Duplicate   bool        `json:"duplicate"`
		Transaction Transaction `json:"transaction"`
	}
	ts.request(t, http.MethodPost, "/api/sms/imports", androidToken, body, http.StatusCreated, &created)
	if created.ImportID == "" || created.Duplicate || created.Transaction.Source != "sms" || created.Transaction.AmountCent != 3210 {
		t.Fatalf("created SMS import = %+v", created)
	}
	ts.request(t, http.MethodPost, "/api/sms/imports", androidToken, body, http.StatusConflict, nil)

	var source string
	var amountType string
	if err := ts.app.db.QueryRowContext(context.Background(), `SELECT source, typeof(amount_cent) FROM transactions WHERE id = ?`, created.Transaction.ID).Scan(&source, &amountType); err != nil {
		t.Fatalf("read SMS transaction error = %v", err)
	}
	if source != "sms" || amountType != "integer" {
		t.Fatalf("source/type = %s/%s, want sms/integer", source, amountType)
	}
	var storedReceivedAtMS int64
	if err := ts.app.db.QueryRowContext(context.Background(), `SELECT sms_received_at_ms FROM sms_imports WHERE id = ?`, created.ImportID).Scan(&storedReceivedAtMS); err != nil {
		t.Fatalf("read SMS received time error = %v", err)
	}
	if storedReceivedAtMS != receivedAtMS {
		t.Fatalf("sms_received_at_ms = %d, want %d", storedReceivedAtMS, receivedAtMS)
	}
}

func TestMigrationV2AddsSMSReceivedAtMS(t *testing.T) {
	root := t.TempDir()
	var cfg Config
	cfg.Server.ListenAddr = "127.0.0.1:0"
	cfg.Server.WebDir = filepath.Join(root, "web")
	cfg.Database.Path = filepath.Join(root, "data", "app.db")
	cfg.Database.BusyTimeout = 5000
	cfg.Database.Synchronous = "NORMAL"
	cfg.Storage.PhotosDir = filepath.Join(root, "data", "photos")
	cfg.Storage.ThumbnailsDir = filepath.Join(root, "data", "thumbnails")
	cfg.Storage.TmpDir = filepath.Join(root, "tmp")
	cfg.Backup.Dir = filepath.Join(root, "backups")
	cfg.Security.SecretPath = filepath.Join(root, "server-secret.key")

	db, err := openSQLite(cfg)
	if err != nil {
		t.Fatalf("openSQLite() error = %v", err)
	}
	defer db.Close()
	ctx := context.Background()
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		t.Fatalf("BeginTx() error = %v", err)
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `
CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  applied_at INTEGER NOT NULL
)`); err != nil {
		t.Fatalf("create schema_migrations error = %v", err)
	}
	for _, stmt := range migrationV1Statements {
		if _, err := tx.ExecContext(ctx, stmt); err != nil {
			t.Fatalf("migration v1 setup error = %v\nstatement: %s", err, stmt)
		}
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO devices(id, name, platform, token_hash, is_admin, active, created_at) VALUES ('dev_android', 'Android', 'android', 'hash', 0, 1, 1)`); err != nil {
		t.Fatalf("insert device error = %v", err)
	}
	smsTime := time.Date(2026, 6, 2, 8, 9, 0, 0, time.UTC).Unix()
	if _, err := tx.ExecContext(ctx, `INSERT INTO sms_imports(id, sms_hash, sender_masked, sms_time, parsed_amount_cent, parsed_direction, status, device_id, created_at, updated_at) VALUES ('sms_old', 'old-hash', '955**', ?, 1200, 'expense', 'confirmed', 'dev_android', 1, 1)`, smsTime); err != nil {
		t.Fatalf("insert old SMS import error = %v", err)
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO schema_migrations(version, name, applied_at) VALUES (1, 'initial_schema', 1)`); err != nil {
		t.Fatalf("insert schema version error = %v", err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatalf("commit old schema error = %v", err)
	}
	if err := db.Close(); err != nil {
		t.Fatalf("close old db error = %v", err)
	}

	app, err := NewApp(cfg)
	if err != nil {
		t.Fatalf("NewApp() migration error = %v", err)
	}
	defer app.Close()
	var version int
	if err := app.db.QueryRowContext(ctx, `SELECT COALESCE(MAX(version), 0) FROM schema_migrations`).Scan(&version); err != nil {
		t.Fatalf("read schema version error = %v", err)
	}
	if version != 2 {
		t.Fatalf("schema version = %d, want 2", version)
	}
	var receivedAtMS int64
	if err := app.db.QueryRowContext(ctx, `SELECT sms_received_at_ms FROM sms_imports WHERE id = 'sms_old'`).Scan(&receivedAtMS); err != nil {
		t.Fatalf("read migrated SMS received time error = %v", err)
	}
	if receivedAtMS != smsTime*1000 {
		t.Fatalf("sms_received_at_ms = %d, want %d", receivedAtMS, smsTime*1000)
	}
}

func testJPEG(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 16, 16))
	for y := 0; y < 16; y++ {
		for x := 0; x < 16; x++ {
			img.Set(x, y, color.RGBA{R: uint8(12 * x), G: uint8(12 * y), B: 96, A: 255})
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 90}); err != nil {
		t.Fatalf("jpeg encode error = %v", err)
	}
	return buf.Bytes()
}

func assertImageResponse(t *testing.T, ts *testServer, token, path string) {
	t.Helper()
	req, err := http.NewRequest(http.MethodGet, ts.server.URL+path, nil)
	if err != nil {
		t.Fatalf("NewRequest() error = %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := ts.server.Client().Do(req)
	if err != nil {
		t.Fatalf("GET %s error = %v", path, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		data, _ := io.ReadAll(resp.Body)
		t.Fatalf("GET %s status = %d, body = %s", path, resp.StatusCode, data)
	}
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read %s error = %v", path, err)
	}
	if resp.Header.Get("Content-Type") != "image/jpeg" || len(data) == 0 {
		t.Fatalf("GET %s content-type=%q bytes=%d", path, resp.Header.Get("Content-Type"), len(data))
	}
}
