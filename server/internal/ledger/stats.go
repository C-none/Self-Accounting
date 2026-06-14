package ledger

import (
	"fmt"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
)

func (a *App) handleStatsCategory(w http.ResponseWriter, r *http.Request, device Device) {
	values := r.URL.Query()
	level := values.Get("level")
	if level == "" {
		level = "l1"
	}
	if level != "l1" && level != "l2" {
		writeError(w, http.StatusBadRequest, "validation_error", "level must be l1 or l2")
		return
	}
	compareBy := values.Get("compare_by")
	hasCompareBy := compareBy != ""
	if compareBy == "" {
		compareBy = "category_l1"
		if level == "l2" {
			compareBy = "category_l2"
		}
	}
	spec, err := statsGroupSpec(compareBy)
	if err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	if hasCompareBy {
		if err := validateStatsCompareFilters(values, compareBy); err != nil {
			writeError(w, http.StatusBadRequest, "validation_error", err.Error())
			return
		}
	}
	direction := values.Get("direction")
	if direction == "" {
		direction = "expense"
	}
	if !validDirection(direction) {
		writeError(w, http.StatusBadRequest, "validation_error", "direction must be income, expense or transfer")
		return
	}
	conditions, args, err := statsConditions(r, direction, "t")
	if err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	where := " WHERE " + strings.Join(conditions, " AND ")
	query := fmt.Sprintf(`SELECT %s AS group_id, %s AS group_name, SUM(t.amount_cent) FROM transactions t %s%s GROUP BY group_id, group_name ORDER BY SUM(t.amount_cent) DESC`, spec.IDExpr, spec.NameExpr, spec.Join, where)
	rows, err := a.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to aggregate category statistics")
		return
	}
	defer rows.Close()
	type item struct {
		GroupID      string  `json:"group_id"`
		GroupName    string  `json:"group_name"`
		CategoryID   string  `json:"category_id"`
		CategoryName string  `json:"category_name"`
		AmountCent   int64   `json:"amount_cent"`
		Percent      float64 `json:"percent"`
	}
	items := []item{}
	var total int64
	for rows.Next() {
		var it item
		if err := rows.Scan(&it.GroupID, &it.GroupName, &it.AmountCent); err != nil {
			writeError(w, http.StatusInternalServerError, "internal_error", "failed to read category statistics")
			return
		}
		it.CategoryID = it.GroupID
		it.CategoryName = it.GroupName
		total += it.AmountCent
		items = append(items, it)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to read category statistics")
		return
	}
	for i := range items {
		if total > 0 {
			items[i].Percent = float64(items[i].AmountCent) * 100 / float64(total)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"currency":   "CNY",
		"level":      level,
		"compare_by": compareBy,
		"items":      items,
	})
}

func (a *App) handleStatsTimeline(w http.ResponseWriter, r *http.Request, device Device) {
	values := r.URL.Query()
	bucket := values.Get("bucket")
	if bucket == "" {
		bucket = "day"
	}
	if bucket != "day" && bucket != "week" && bucket != "month" {
		writeError(w, http.StatusBadRequest, "validation_error", "bucket must be day, week or month")
		return
	}
	direction := values.Get("direction")
	if direction == "" {
		direction = "expense"
	}
	if !validDirection(direction) {
		writeError(w, http.StatusBadRequest, "validation_error", "direction must be income, expense or transfer")
		return
	}
	compareBy := values.Get("compare_by")
	var spec statsGroup
	if compareBy != "" {
		var err error
		spec, err = statsGroupSpec(compareBy)
		if err != nil {
			writeError(w, http.StatusBadRequest, "validation_error", err.Error())
			return
		}
		if err := validateStatsCompareFilters(values, compareBy); err != nil {
			writeError(w, http.StatusBadRequest, "validation_error", err.Error())
			return
		}
	}
	conditions, args, err := statsConditions(r, direction, "t")
	if err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	bucketExpr := `strftime('%Y-%m-%d', datetime(t.transaction_time, 'unixepoch'))`
	if bucket == "week" {
		bucketExpr = `date(datetime(t.transaction_time, 'unixepoch'), '-' || ((CAST(strftime('%w', datetime(t.transaction_time, 'unixepoch')) AS INTEGER) + 6) % 7) || ' days')`
	}
	if bucket == "month" {
		bucketExpr = `strftime('%Y-%m', datetime(t.transaction_time, 'unixepoch'))`
	}
	where := " WHERE " + strings.Join(conditions, " AND ")
	if compareBy == "" {
		a.writeLegacyTimelineStats(w, r, bucket, bucketExpr, where, args)
		return
	}
	query := fmt.Sprintf(`SELECT %s AS bucket_date, %s AS group_id, %s AS group_name, SUM(t.amount_cent) FROM transactions t %s%s GROUP BY bucket_date, group_id, group_name ORDER BY bucket_date, group_name`, bucketExpr, spec.IDExpr, spec.NameExpr, spec.Join, where)
	rows, err := a.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to aggregate timeline statistics")
		return
	}
	defer rows.Close()
	type point struct {
		Date       string `json:"date"`
		AmountCent int64  `json:"amount_cent"`
	}
	type series struct {
		GroupID    string  `json:"group_id"`
		GroupName  string  `json:"group_name"`
		Points     []point `json:"points"`
		AmountCent int64   `json:"-"`
	}
	seriesByID := map[string]*series{}
	seriesList := []*series{}
	totalsByDate := map[string]int64{}
	for rows.Next() {
		var date string
		var groupID string
		var groupName string
		var amountCent int64
		if err := rows.Scan(&date, &groupID, &groupName, &amountCent); err != nil {
			writeError(w, http.StatusInternalServerError, "internal_error", "failed to read timeline statistics")
			return
		}
		current := seriesByID[groupID]
		if current == nil {
			current = &series{GroupID: groupID, GroupName: groupName, Points: []point{}}
			seriesByID[groupID] = current
			seriesList = append(seriesList, current)
		}
		current.Points = append(current.Points, point{Date: date, AmountCent: amountCent})
		current.AmountCent += amountCent
		totalsByDate[date] += amountCent
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to read timeline statistics")
		return
	}
	sort.Slice(seriesList, func(i, j int) bool {
		if seriesList[i].AmountCent == seriesList[j].AmountCent {
			return seriesList[i].GroupName < seriesList[j].GroupName
		}
		return seriesList[i].AmountCent > seriesList[j].AmountCent
	})
	seriesItems := make([]series, 0, len(seriesList))
	for _, item := range seriesList {
		seriesItems = append(seriesItems, *item)
	}
	dates := make([]string, 0, len(totalsByDate))
	for date := range totalsByDate {
		dates = append(dates, date)
	}
	sort.Strings(dates)
	points := make([]point, 0, len(dates))
	for _, date := range dates {
		points = append(points, point{Date: date, AmountCent: totalsByDate[date]})
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"currency":   "CNY",
		"bucket":     bucket,
		"compare_by": compareBy,
		"points":     points,
		"series":     seriesItems,
	})
}

func (a *App) writeLegacyTimelineStats(w http.ResponseWriter, r *http.Request, bucket string, bucketExpr string, where string, args []any) {
	query := `SELECT ` + bucketExpr + ` AS bucket_date, SUM(t.amount_cent) FROM transactions t` + where + ` GROUP BY bucket_date ORDER BY bucket_date`
	rows, err := a.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to aggregate timeline statistics")
		return
	}
	defer rows.Close()
	type point struct {
		Date       string `json:"date"`
		AmountCent int64  `json:"amount_cent"`
	}
	points := []point{}
	for rows.Next() {
		var p point
		if err := rows.Scan(&p.Date, &p.AmountCent); err != nil {
			writeError(w, http.StatusInternalServerError, "internal_error", "failed to read timeline statistics")
			return
		}
		points = append(points, p)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to read timeline statistics")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"currency": "CNY",
		"bucket":   bucket,
		"points":   points,
	})
}

func statsConditions(r *http.Request, direction string, tableAlias string) ([]string, []any, error) {
	values := r.URL.Query()
	col := func(name string) string {
		if tableAlias == "" {
			return name
		}
		return tableAlias + "." + name
	}
	conditions := []string{col("deleted_at") + " IS NULL", col("direction") + " = ?"}
	args := []any{direction}
	for _, item := range []struct {
		key string
		col string
	}{
		{"member_id", "member_id"},
		{"account_id", "account_id"},
		{"category_l1_id", "category_l1_id"},
		{"category_l2_id", "category_l2_id"},
	} {
		if raw := values.Get(item.key); raw != "" {
			conditions = append(conditions, col(item.col)+" = ?")
			args = append(args, raw)
		}
	}
	if raw := strings.TrimSpace(values.Get("bank_name")); raw != "" {
		conditions = append(conditions, col("account_id")+" IN (SELECT id FROM accounts WHERE deleted_at IS NULL AND name = ?)")
		args = append(args, raw)
	}
	if raw := values.Get("from"); raw != "" {
		n, err := strconv.ParseInt(raw, 10, 64)
		if err != nil {
			return nil, nil, fmt.Errorf("from must be a unix timestamp")
		}
		conditions = append(conditions, col("transaction_time")+" >= ?")
		args = append(args, n)
	}
	if raw := values.Get("to"); raw != "" {
		n, err := strconv.ParseInt(raw, 10, 64)
		if err != nil {
			return nil, nil, fmt.Errorf("to must be a unix timestamp")
		}
		conditions = append(conditions, col("transaction_time")+" <= ?")
		args = append(args, n)
	}
	return conditions, args, nil
}

type statsGroup struct {
	IDExpr   string
	NameExpr string
	Join     string
}

func statsGroupSpec(compareBy string) (statsGroup, error) {
	switch compareBy {
	case "category_l1":
		return statsGroup{
			IDExpr:   "t.category_l1_id",
			NameExpr: "c.name",
			Join:     "JOIN categories c ON c.id = t.category_l1_id",
		}, nil
	case "category_l2":
		return statsGroup{
			IDExpr:   "COALESCE(t.category_l2_id, t.category_l1_id)",
			NameExpr: "c.name",
			Join:     "JOIN categories c ON c.id = COALESCE(t.category_l2_id, t.category_l1_id)",
		}, nil
	case "member":
		return statsGroup{
			IDExpr:   "t.member_id",
			NameExpr: "m.name",
			Join:     "JOIN members m ON m.id = t.member_id",
		}, nil
	case "bank":
		return statsGroup{
			IDExpr:   "a.name",
			NameExpr: "a.name",
			Join:     "JOIN accounts a ON a.id = t.account_id",
		}, nil
	default:
		return statsGroup{}, fmt.Errorf("compare_by must be category_l1, category_l2, member or bank")
	}
}

func validateStatsCompareFilters(values url.Values, compareBy string) error {
	conflicts := map[string][]string{
		"category_l1": {"category_l1_id", "category_l2_id"},
		"category_l2": {"category_l2_id"},
		"member":      {"member_id"},
		"bank":        {"bank_name", "account_id"},
	}
	for _, key := range conflicts[compareBy] {
		if strings.TrimSpace(values.Get(key)) != "" {
			return fmt.Errorf("%s cannot be used when compare_by=%s", key, compareBy)
		}
	}
	return nil
}
