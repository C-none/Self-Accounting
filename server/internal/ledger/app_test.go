package ledger

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"
)

type testServer struct {
	app    *App
	server *httptest.Server
}

func newTestServer(t *testing.T) *testServer {
	t.Helper()
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
	cfg.FFmpeg.Path = "ffmpeg"
	cfg.FFmpeg.JPGQuality = 28
	cfg.FFmpeg.MaxWidth = 1600
	cfg.FFmpeg.MaxHeight = 1600

	app, err := NewApp(cfg)
	if err != nil {
		t.Fatalf("NewApp() error = %v", err)
	}
	server := httptest.NewServer(app.Handler())
	t.Cleanup(func() {
		server.Close()
		if err := app.Close(); err != nil {
			t.Fatalf("Close() error = %v", err)
		}
	})
	return &testServer{app: app, server: server}
}

func (ts *testServer) request(t *testing.T, method, path, token string, body any, wantStatus int, dst any) {
	t.Helper()
	var reader io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("json.Marshal() error = %v", err)
		}
		reader = bytes.NewReader(data)
	}
	req, err := http.NewRequest(method, ts.server.URL+path, reader)
	if err != nil {
		t.Fatalf("NewRequest() error = %v", err)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := ts.server.Client().Do(req)
	if err != nil {
		t.Fatalf("%s %s error = %v", method, path, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != wantStatus {
		data, _ := io.ReadAll(resp.Body)
		t.Fatalf("%s %s status = %d, want %d, body = %s", method, path, resp.StatusCode, wantStatus, data)
	}
	if dst != nil {
		if err := json.NewDecoder(resp.Body).Decode(dst); err != nil {
			t.Fatalf("decode %s %s response error = %v", method, path, err)
		}
	}
}

func (ts *testServer) pairDevice(t *testing.T, adminToken, platform, name string) (string, bool) {
	t.Helper()
	pairingCode := ts.startPairingCode(t, adminToken)
	var confirm struct {
		DeviceToken string `json:"device_token"`
		IsAdmin     bool   `json:"is_admin"`
	}
	ts.request(t, http.MethodPost, "/api/pair/confirm", "", map[string]any{
		"pairing_code": pairingCode,
		"device_name":  name,
		"platform":     platform,
	}, http.StatusOK, &confirm)
	if confirm.DeviceToken == "" {
		t.Fatalf("device_token is empty")
	}
	return confirm.DeviceToken, confirm.IsAdmin
}

func (ts *testServer) startPairingCode(t *testing.T, token string) string {
	t.Helper()
	var start struct {
		PairingCode string `json:"pairing_code"`
		Delivery    string `json:"delivery"`
		ExpiresAt   int64  `json:"expires_at"`
	}
	ts.request(t, http.MethodPost, "/api/pair/start", token, nil, http.StatusOK, &start)
	if start.ExpiresAt == 0 {
		t.Fatalf("expires_at is empty")
	}
	if start.PairingCode != "" {
		return start.PairingCode
	}
	if start.Delivery != "server_console" {
		t.Fatalf("delivery = %q, want server_console", start.Delivery)
	}
	ts.app.pairingCodeMu.Lock()
	defer ts.app.pairingCodeMu.Unlock()
	if ts.app.activePlainCode == nil || ts.app.activePlainCode.code == "" {
		t.Fatalf("runtime pairing code is empty")
	}
	return ts.app.activePlainCode.code
}

func (ts *testServer) bootstrap(t *testing.T, token string) map[string]any {
	t.Helper()
	var bootstrap map[string]any
	ts.request(t, http.MethodGet, "/api/bootstrap", token, nil, http.StatusOK, &bootstrap)
	return bootstrap
}

func testTxnBody(amount int64, direction string) map[string]any {
	return map[string]any{
		"amount_cent":      amount,
		"currency":         "CNY",
		"direction":        direction,
		"transaction_time": time.Date(2026, 6, 1, 10, 0, 0, 0, time.UTC).Unix(),
		"category_l1_id":   "expense_food",
		"category_l2_id":   "expense_food_meal",
		"member_id":        "member_self",
		"account_id":       "account_cash",
		"counterparty":     "早餐店",
		"description":      "验收边界样例",
	}
}

func TestPairingAuthAndTokenStorage(t *testing.T) {
	ts := newTestServer(t)

	var health map[string]any
	ts.request(t, http.MethodGet, "/api/health", "", nil, http.StatusOK, &health)
	if health["journal_mode"] != "wal" {
		t.Fatalf("journal_mode = %v, want wal", health["journal_mode"])
	}

	ts.request(t, http.MethodGet, "/api/bootstrap", "", nil, http.StatusUnauthorized, nil)
	adminToken, isAdmin := ts.pairDevice(t, "", "web", "web-admin")
	if !isAdmin {
		t.Fatalf("first paired device should be admin")
	}

	var storedHash string
	if err := ts.app.db.QueryRowContext(context.Background(), `SELECT token_hash FROM devices WHERE is_admin = 1`).Scan(&storedHash); err != nil {
		t.Fatalf("read token hash: %v", err)
	}
	if storedHash == "" || storedHash == adminToken {
		t.Fatalf("token hash should be stored and must not equal plaintext token")
	}
	if storedHash != hmacHex(ts.app.secret, adminToken) {
		t.Fatalf("stored token hash does not match server HMAC")
	}

	var unauthStart struct {
		PairingCode string `json:"pairing_code"`
		Delivery    string `json:"delivery"`
	}
	ts.request(t, http.MethodPost, "/api/pair/start", "", nil, http.StatusOK, &unauthStart)
	if unauthStart.PairingCode != "" || unauthStart.Delivery != "server_console" {
		t.Fatalf("unauthenticated start = %+v, want console-only response", unauthStart)
	}
	secondCode := ts.startPairingCode(t, adminToken)
	var firstConfirm map[string]any
	ts.request(t, http.MethodPost, "/api/pair/confirm", "", map[string]any{
		"pairing_code": secondCode,
		"device_name":  "android-phone",
		"platform":     "android",
	}, http.StatusOK, &firstConfirm)
	ts.request(t, http.MethodPost, "/api/pair/confirm", "", map[string]any{
		"pairing_code": secondCode,
		"device_name":  "replay",
		"platform":     "android",
	}, http.StatusBadRequest, nil)

	androidToken, _ := firstConfirm["device_token"].(string)
	androidPairCode := ts.startPairingCode(t, androidToken)
	if androidPairCode == "" {
		t.Fatalf("paired non-admin device should receive a pairing code")
	}

	webBootstrap := ts.bootstrap(t, adminToken)
	webFeatures := webBootstrap["features"].(map[string]any)
	if webFeatures["sms"] != false {
		t.Fatalf("web sms feature = %v, want false", webFeatures["sms"])
	}
	androidBootstrap := ts.bootstrap(t, androidToken)
	androidFeatures := androidBootstrap["features"].(map[string]any)
	if androidFeatures["sms"] != true {
		t.Fatalf("android sms feature = %v, want true", androidFeatures["sms"])
	}
}

func TestCurrentDeviceNameAndAdminAuditLogs(t *testing.T) {
	ts := newTestServer(t)
	adminToken, _ := ts.pairDevice(t, "", "web", "web-admin")
	androidToken, _ := ts.pairDevice(t, adminToken, "android", "android-phone")

	ts.request(t, http.MethodPatch, "/api/devices/current", androidToken, map[string]any{
		"name": "   ",
	}, http.StatusBadRequest, nil)

	var updated Device
	ts.request(t, http.MethodPatch, "/api/devices/current", androidToken, map[string]any{
		"name": "  安卓实机  ",
	}, http.StatusOK, &updated)
	if updated.Name != "安卓实机" || updated.Platform != "android" || updated.IsAdmin {
		t.Fatalf("updated device = %+v", updated)
	}

	androidBootstrap := ts.bootstrap(t, androidToken)
	device := androidBootstrap["device"].(map[string]any)
	if device["name"] != "安卓实机" {
		t.Fatalf("bootstrap device name = %v, want updated name", device["name"])
	}

	ts.request(t, http.MethodGet, "/api/admin/audit-logs", androidToken, nil, http.StatusForbidden, nil)

	var logs struct {
		Items []map[string]any `json:"items"`
	}
	ts.request(t, http.MethodGet, "/api/admin/audit-logs?limit=10", adminToken, nil, http.StatusOK, &logs)
	found := false
	for _, item := range logs.Items {
		if item["entity_type"] == "device" && item["action"] == "update_name" && item["device_name"] == "安卓实机" {
			found = true
		}
		if _, ok := item["payload_json"]; ok {
			t.Fatalf("audit log should not expose payload_json: %+v", item)
		}
	}
	if !found {
		t.Fatalf("audit logs did not include device update: %+v", logs.Items)
	}
}

func TestRequireHTTPSRejectsHTTPPublicBaseURL(t *testing.T) {
	var cfg Config
	cfg.Server.RequireHTTPS = true
	cfg.Server.PublicBaseURL = "http://127.0.0.1:8080"
	if app, err := NewApp(cfg); err == nil {
		_ = app.Close()
		t.Fatalf("NewApp() should reject public HTTP when require_https is true")
	}
}

func TestTransactionCRUDValidationSoftDeleteAndStats(t *testing.T) {
	ts := newTestServer(t)
	token, _ := ts.pairDevice(t, "", "web", "web-admin")

	ts.request(t, http.MethodPost, "/api/transactions", token, testTxnBody(0, "expense"), http.StatusBadRequest, nil)
	ts.request(t, http.MethodPost, "/api/transactions", token, testTxnBody(100, "invalid"), http.StatusBadRequest, nil)
	badCategory := testTxnBody(100, "expense")
	badCategory["category_l1_id"] = "income_salary"
	ts.request(t, http.MethodPost, "/api/transactions", token, badCategory, http.StatusBadRequest, nil)
	spoofedSource := testTxnBody(100, "expense")
	spoofedSource["source"] = "sms"
	ts.request(t, http.MethodPost, "/api/transactions", token, spoofedSource, http.StatusBadRequest, nil)

	var created Transaction
	ts.request(t, http.MethodPost, "/api/transactions", token, testTxnBody(1234, "expense"), http.StatusCreated, &created)
	if created.AmountCent != 1234 || created.Source != "web" || created.Version != 1 {
		t.Fatalf("created transaction = %+v", created)
	}

	var listed TransactionList
	ts.request(t, http.MethodGet, "/api/transactions?keyword=%E9%AA%8C%E6%94%B6&page_size=500", token, nil, http.StatusOK, &listed)
	if listed.Total != 1 || len(listed.Items) != 1 {
		t.Fatalf("listed = %+v, want one transaction", listed)
	}

	var emptyList TransactionList
	ts.request(t, http.MethodGet, "/api/transactions?from=1&to=2", token, nil, http.StatusOK, &emptyList)
	if emptyList.Items == nil || len(emptyList.Items) != 0 {
		t.Fatalf("empty list items = %#v, want non-nil empty slice", emptyList.Items)
	}

	patchBody := testTxnBody(4567, "expense")
	patchBody["description"] = "修改后"
	var patched Transaction
	ts.request(t, http.MethodPatch, "/api/transactions/"+created.ID, token, patchBody, http.StatusOK, &patched)
	if patched.AmountCent != 4567 || patched.Description != "修改后" || patched.Version != 2 {
		t.Fatalf("patched transaction = %+v", patched)
	}

	var categoryStats struct {
		Items []struct {
			CategoryID string `json:"category_id"`
			AmountCent int64  `json:"amount_cent"`
		} `json:"items"`
	}
	ts.request(t, http.MethodGet, "/api/stats/category?direction=expense", token, nil, http.StatusOK, &categoryStats)
	if len(categoryStats.Items) != 1 || categoryStats.Items[0].CategoryID != "expense_food" || categoryStats.Items[0].AmountCent != 4567 {
		t.Fatalf("category stats = %+v", categoryStats.Items)
	}

	var timelineStats struct {
		Bucket string `json:"bucket"`
		Points []struct {
			Date       string `json:"date"`
			AmountCent int64  `json:"amount_cent"`
		} `json:"points"`
	}
	ts.request(t, http.MethodGet, "/api/stats/timeline?direction=expense&bucket=week&member_id=member_self&category_l1_id=expense_food&bank_name=%E7%8E%B0%E9%87%91", token, nil, http.StatusOK, &timelineStats)
	if timelineStats.Bucket != "week" || len(timelineStats.Points) != 1 || timelineStats.Points[0].Date != "2026-06-01" || timelineStats.Points[0].AmountCent != 4567 {
		t.Fatalf("weekly timeline stats = %+v", timelineStats)
	}
	ts.request(t, http.MethodGet, "/api/stats/timeline?direction=expense&bucket=year", token, nil, http.StatusBadRequest, nil)

	drinkBody := testTxnBody(3333, "expense")
	drinkBody["category_l2_id"] = "expense_food_drink"
	drinkBody["transaction_time"] = time.Date(2026, 6, 2, 10, 0, 0, 0, time.UTC).Unix()
	var drink Transaction
	ts.request(t, http.MethodPost, "/api/transactions", token, drinkBody, http.StatusCreated, &drink)

	var comparisonStats struct {
		CompareBy string `json:"compare_by"`
		Items     []struct {
			GroupID    string `json:"group_id"`
			GroupName  string `json:"group_name"`
			AmountCent int64  `json:"amount_cent"`
		} `json:"items"`
	}
	ts.request(t, http.MethodGet, "/api/stats/category?direction=expense&compare_by=category_l2&category_l1_id=expense_food", token, nil, http.StatusOK, &comparisonStats)
	if comparisonStats.CompareBy != "category_l2" || len(comparisonStats.Items) != 2 || comparisonStats.Items[0].GroupID != "expense_food_meal" || comparisonStats.Items[1].GroupID != "expense_food_drink" {
		t.Fatalf("category_l2 comparison stats = %+v", comparisonStats)
	}

	var comparisonTimeline struct {
		CompareBy string `json:"compare_by"`
		Series    []struct {
			GroupID string `json:"group_id"`
			Points  []struct {
				Date       string `json:"date"`
				AmountCent int64  `json:"amount_cent"`
			} `json:"points"`
		} `json:"series"`
	}
	ts.request(t, http.MethodGet, "/api/stats/timeline?direction=expense&compare_by=category_l2&bucket=day&category_l1_id=expense_food", token, nil, http.StatusOK, &comparisonTimeline)
	if comparisonTimeline.CompareBy != "category_l2" || len(comparisonTimeline.Series) != 2 || comparisonTimeline.Series[0].GroupID != "expense_food_meal" || comparisonTimeline.Series[1].GroupID != "expense_food_drink" {
		t.Fatalf("category_l2 comparison timeline = %+v", comparisonTimeline)
	}
	ts.request(t, http.MethodGet, "/api/stats/category?direction=expense&compare_by=category_l1&category_l1_id=expense_food", token, nil, http.StatusBadRequest, nil)

	ts.request(t, http.MethodDelete, "/api/transactions/"+created.ID, token, nil, http.StatusOK, nil)
	ts.request(t, http.MethodDelete, "/api/transactions/"+drink.ID, token, nil, http.StatusOK, nil)
	ts.request(t, http.MethodGet, "/api/transactions", token, nil, http.StatusOK, &listed)
	if listed.Total != 0 || listed.Items == nil || len(listed.Items) != 0 {
		t.Fatalf("list after delete = %+v, want empty non-nil items", listed)
	}
	ts.request(t, http.MethodGet, "/api/stats/category?direction=expense", token, nil, http.StatusOK, &categoryStats)
	if categoryStats.Items == nil || len(categoryStats.Items) != 0 {
		t.Fatalf("category stats after delete = %+v, want empty non-nil items", categoryStats.Items)
	}

	var deletedAt sql.NullInt64
	if err := ts.app.db.QueryRowContext(context.Background(), `SELECT deleted_at FROM transactions WHERE id = ?`, created.ID).Scan(&deletedAt); err != nil {
		t.Fatalf("read deleted_at: %v", err)
	}
	if !deletedAt.Valid {
		t.Fatalf("deleted_at should be set")
	}
	ts.request(t, http.MethodGet, "/api/transactions/"+created.ID, token, nil, http.StatusNotFound, nil)
}

func TestMasterDataReorderAndAppend(t *testing.T) {
	ts := newTestServer(t)
	token, _ := ts.pairDevice(t, "", "web", "web-admin")

	var boot struct {
		Categories []Category `json:"categories"`
		Members    []Member   `json:"members"`
		Accounts   []Account  `json:"accounts"`
	}
	ts.request(t, http.MethodGet, "/api/bootstrap", token, nil, http.StatusOK, &boot)

	expenseTopIDs := categoryIDsForTest(boot.Categories, "expense", "")
	expenseTopIDs = moveIDFirstForTest(expenseTopIDs, "expense_transport")
	ts.request(t, http.MethodPost, "/api/categories/reorder", token, map[string]any{
		"type":        "expense",
		"parent_id":   nil,
		"ordered_ids": expenseTopIDs,
	}, http.StatusOK, nil)
	ts.request(t, http.MethodPost, "/api/categories/reorder", token, map[string]any{
		"type":        "expense",
		"parent_id":   nil,
		"ordered_ids": []string{"expense_transport", "expense_transport"},
	}, http.StatusBadRequest, nil)

	var reordered struct {
		Categories []Category `json:"categories"`
	}
	ts.request(t, http.MethodGet, "/api/bootstrap", token, nil, http.StatusOK, &reordered)
	gotExpenseTopIDs := categoryIDsForTest(reordered.Categories, "expense", "")
	if len(gotExpenseTopIDs) == 0 || gotExpenseTopIDs[0] != "expense_transport" {
		t.Fatalf("expense top order = %v, want expense_transport first", gotExpenseTopIDs)
	}

	childIDs := categoryIDsForTest(reordered.Categories, "expense", "expense_food")
	if len(childIDs) < 2 {
		t.Fatalf("seed child categories = %v, want at least two", childIDs)
	}
	reversedChildIDs := []string{childIDs[1], childIDs[0]}
	ts.request(t, http.MethodPost, "/api/categories/reorder", token, map[string]any{
		"type":        "expense",
		"parent_id":   "expense_food",
		"ordered_ids": reversedChildIDs,
	}, http.StatusOK, nil)

	var createdChild Category
	ts.request(t, http.MethodPost, "/api/categories", token, map[string]any{
		"name":      "夜宵",
		"type":      "expense",
		"parent_id": "expense_food",
	}, http.StatusCreated, &createdChild)
	ts.request(t, http.MethodGet, "/api/bootstrap", token, nil, http.StatusOK, &reordered)
	childIDs = categoryIDsForTest(reordered.Categories, "expense", "expense_food")
	if childIDs[len(childIDs)-1] != createdChild.ID {
		t.Fatalf("child order after append = %v, want new category last", childIDs)
	}

	var family Member
	ts.request(t, http.MethodPost, "/api/members", token, map[string]any{
		"name": "家人",
	}, http.StatusCreated, &family)
	ts.request(t, http.MethodPost, "/api/members/reorder", token, map[string]any{
		"ordered_ids": []string{family.ID, "member_self"},
	}, http.StatusOK, nil)
	var child Member
	ts.request(t, http.MethodPost, "/api/members", token, map[string]any{
		"name": "孩子",
	}, http.StatusCreated, &child)
	var memberBoot struct {
		Members []Member `json:"members"`
	}
	ts.request(t, http.MethodGet, "/api/bootstrap", token, nil, http.StatusOK, &memberBoot)
	memberIDs := memberIDsForTest(memberBoot.Members)
	if len(memberIDs) != 3 || memberIDs[0] != family.ID || memberIDs[2] != child.ID {
		t.Fatalf("member order = %v, want reordered family first and new child last", memberIDs)
	}

	var bank Account
	ts.request(t, http.MethodPost, "/api/accounts", token, map[string]any{
		"name":              "工商银行",
		"type":              "bank",
		"masked_identifier": "0973",
	}, http.StatusCreated, &bank)
	ts.request(t, http.MethodPost, "/api/accounts/reorder", token, map[string]any{
		"ordered_ids": []string{bank.ID, "account_cash"},
	}, http.StatusOK, nil)
	ts.request(t, http.MethodPost, "/api/accounts/reorder", token, map[string]any{
		"ordered_ids": []string{bank.ID},
	}, http.StatusBadRequest, nil)
	var wallet Account
	ts.request(t, http.MethodPost, "/api/accounts", token, map[string]any{
		"name":              "招商银行",
		"type":              "bank",
		"masked_identifier": "1234",
	}, http.StatusCreated, &wallet)
	var accountBoot struct {
		Accounts []Account `json:"accounts"`
	}
	ts.request(t, http.MethodGet, "/api/bootstrap", token, nil, http.StatusOK, &accountBoot)
	accountIDs := accountIDsForTest(accountBoot.Accounts)
	if len(accountIDs) != 3 || accountIDs[0] != bank.ID || accountIDs[2] != wallet.ID {
		t.Fatalf("account order = %v, want reordered bank first and new wallet last", accountIDs)
	}
}

func categoryIDsForTest(categories []Category, typ, parentID string) []string {
	var ids []string
	for _, category := range categories {
		if category.Type == typ && category.ParentID == parentID {
			ids = append(ids, category.ID)
		}
	}
	return ids
}

func memberIDsForTest(members []Member) []string {
	ids := make([]string, 0, len(members))
	for _, member := range members {
		ids = append(ids, member.ID)
	}
	return ids
}

func accountIDsForTest(accounts []Account) []string {
	ids := make([]string, 0, len(accounts))
	for _, account := range accounts {
		ids = append(ids, account.ID)
	}
	return ids
}

func moveIDFirstForTest(ids []string, id string) []string {
	out := []string{id}
	for _, value := range ids {
		if value != id {
			out = append(out, value)
		}
	}
	return out
}

func TestCategorySuggestionsNaiveBayes(t *testing.T) {
	ts := newTestServer(t)
	token, _ := ts.pairDevice(t, "", "web", "web-admin")

	var insufficient categorySuggestionsResponse
	ts.request(t, http.MethodPost, "/api/category-suggestions", token, map[string]any{
		"items": []map[string]any{
			categorySuggestionTestItem("empty", "expense", 2600, "星巴克咖啡", "短信导入：星巴克咖啡"),
		},
	}, http.StatusOK, &insufficient)
	if len(insufficient.Items) != 1 || insufficient.Items[0].Method != "insufficient_data" {
		t.Fatalf("insufficient suggestion = %+v", insufficient.Items)
	}

	rawBody := categorySuggestionTestItem("raw", "expense", 2600, "星巴克咖啡", "短信导入")
	rawBody["raw_body"] = "sensitive sms body"
	ts.request(t, http.MethodPost, "/api/category-suggestions", token, map[string]any{
		"items": []map[string]any{rawBody},
	}, http.StatusBadRequest, nil)

	for _, sample := range []struct {
		category     string
		counterparty string
		description  string
		amount       int64
	}{
		{"expense_food", "星巴克咖啡", "拿铁早餐", 2600},
		{"expense_food", "咖啡店", "早餐咖啡", 1800},
		{"expense_food", "美团外卖", "工作餐", 4200},
		{"expense_transport", "滴滴打车", "夜间打车", 3200},
		{"expense_transport", "地铁出行", "通勤交通", 600},
		{"expense_transport", "停车缴费", "停车场", 1200},
		{"expense_other", "物业缴费", "小区物业", 30000},
		{"expense_other", "水电账单", "居家账单", 8600},
		{"expense_other", "证件手续费", "政务手续费", 2000},
	} {
		ts.createTrainingTransaction(t, token, sample.category, sample.counterparty, sample.description, sample.amount)
	}
	for i := 0; i < 4; i++ {
		deleted := ts.createTrainingTransaction(t, token, "expense_transport", "星巴克咖啡", "软删除干扰样本", 2600)
		ts.request(t, http.MethodDelete, "/api/transactions/"+deleted.ID, token, nil, http.StatusOK, nil)
	}

	var suggested categorySuggestionsResponse
	ts.request(t, http.MethodPost, "/api/category-suggestions", token, map[string]any{
		"items": []map[string]any{
			categorySuggestionTestItem("food", "expense", 2700, "星巴克咖啡拿铁", "短信导入：星巴克咖啡拿铁"),
			categorySuggestionTestItem("unknown", "expense", 7700, "全新商户XYZ", "短信导入：全新商户XYZ"),
		},
	}, http.StatusOK, &suggested)
	if len(suggested.Items) != 2 {
		t.Fatalf("suggested items = %+v", suggested.Items)
	}
	if suggested.Items[0].CategoryL1ID != "expense_food" || suggested.Items[0].Method != "nb" {
		t.Fatalf("food suggestion = %+v", suggested.Items[0])
	}
	if len(suggested.Items[0].Alternatives) == 0 || len(suggested.Items[0].Alternatives) > 3 {
		t.Fatalf("food alternatives = %+v", suggested.Items[0].Alternatives)
	}
	if suggested.Items[1].Method != "nb" || suggested.Items[1].CategoryL1ID == "" || suggested.Items[1].Confidence <= 0 {
		t.Fatalf("unknown-token suggestion should still be smoothed: %+v", suggested.Items[1])
	}
}

func (ts *testServer) createTrainingTransaction(t *testing.T, token, category, counterparty, description string, amount int64) Transaction {
	t.Helper()
	body := map[string]any{
		"amount_cent":      amount,
		"currency":         "CNY",
		"direction":        "expense",
		"transaction_time": time.Date(2026, 6, 2, 10, 0, 0, 0, time.UTC).Unix(),
		"category_l1_id":   category,
		"category_l2_id":   nil,
		"member_id":        "member_self",
		"account_id":       "account_cash",
		"counterparty":     counterparty,
		"description":      description,
	}
	var created Transaction
	ts.request(t, http.MethodPost, "/api/transactions", token, body, http.StatusCreated, &created)
	return created
}

func categorySuggestionTestItem(ref, direction string, amount int64, counterparty, description string) map[string]any {
	return map[string]any{
		"client_ref":       ref,
		"direction":        direction,
		"amount_cent":      amount,
		"transaction_time": time.Date(2026, 6, 2, 10, 0, 0, 0, time.UTC).Unix(),
		"account_id":       "account_cash",
		"counterparty":     counterparty,
		"description":      description,
	}
}
