package ledger

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"sort"
	"strings"
	"unicode"
)

const (
	categorySuggestionMaxItems = 100
	nbAlpha                    = 1.0
	nbMinDocs                  = 3
	nbMinClasses               = 2
	nbMinL2Docs                = 5
)

type categorySuggestionsRequest struct {
	Items []categorySuggestionInput `json:"items"`
}

type categorySuggestionInput struct {
	ClientRef       string `json:"client_ref"`
	Direction       string `json:"direction"`
	AmountCent      *int64 `json:"amount_cent"`
	TransactionTime *int64 `json:"transaction_time"`
	AccountID       string `json:"account_id"`
	Counterparty    string `json:"counterparty"`
	Description     string `json:"description"`
}

type categorySuggestionsResponse struct {
	Items []categorySuggestionResult `json:"items"`
}

type categorySuggestionResult struct {
	ClientRef    string                          `json:"client_ref"`
	CategoryL1ID string                          `json:"category_l1_id"`
	CategoryL2ID *string                         `json:"category_l2_id"`
	Confidence   float64                         `json:"confidence"`
	Method       string                          `json:"method"`
	Alternatives []categorySuggestionAlternative `json:"alternatives"`
}

type categorySuggestionAlternative struct {
	CategoryL1ID string  `json:"category_l1_id"`
	CategoryL2ID *string `json:"category_l2_id"`
	Confidence   float64 `json:"confidence"`
}

type categoryTrainingRow struct {
	CategoryL1ID    string
	CategoryL2ID    string
	AccountID       string
	AmountCent      int64
	TransactionTime int64
	Counterparty    string
	Description     string
}

type categoryModels struct {
	rows []categoryTrainingRow
	l1   *nbModel
}

type nbModel struct {
	totalDocs        int
	classDocs        map[string]int
	classTokenCounts map[string]map[string]int
	classTokenTotals map[string]int
	vocabulary       map[string]struct{}
}

type scoredClass struct {
	label      string
	score      float64
	confidence float64
}

func (a *App) handleCategorySuggestions(w http.ResponseWriter, r *http.Request, device Device) {
	data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 64*1024))
	_ = r.Body.Close()
	if err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "invalid JSON request")
		return
	}
	var raw any
	if err := json.Unmarshal(data, &raw); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "invalid JSON request")
		return
	}
	if containsRawSMSField(raw) {
		writeError(w, http.StatusBadRequest, "validation_error", "SMS raw body must not be uploaded")
		return
	}
	var req categorySuggestionsRequest
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "invalid category suggestions request")
		return
	}
	if len(req.Items) > categorySuggestionMaxItems {
		writeError(w, http.StatusBadRequest, "validation_error", fmt.Sprintf("items must contain at most %d entries", categorySuggestionMaxItems))
		return
	}
	modelsByDirection := map[string]*categoryModels{}
	out := make([]categorySuggestionResult, 0, len(req.Items))
	for i := range req.Items {
		item := normalizeCategorySuggestionInput(req.Items[i])
		if err := validateCategorySuggestionInput(item); err != nil {
			writeError(w, http.StatusBadRequest, "validation_error", err.Error())
			return
		}
		models, ok := modelsByDirection[item.Direction]
		if !ok {
			models, err = a.buildCategoryModels(r.Context(), item.Direction)
			if err != nil {
				writeError(w, http.StatusInternalServerError, "internal_error", "failed to train category suggestions")
				return
			}
			modelsByDirection[item.Direction] = models
		}
		out = append(out, models.suggest(item))
	}
	writeJSON(w, http.StatusOK, categorySuggestionsResponse{Items: out})
}

func containsRawSMSField(value any) bool {
	switch v := value.(type) {
	case map[string]any:
		for key, child := range v {
			if isRawSMSField(key) {
				return true
			}
			if containsRawSMSField(child) {
				return true
			}
		}
	case []any:
		for _, child := range v {
			if containsRawSMSField(child) {
				return true
			}
		}
	}
	return false
}

func normalizeCategorySuggestionInput(item categorySuggestionInput) categorySuggestionInput {
	item.ClientRef = strings.TrimSpace(item.ClientRef)
	item.Direction = strings.TrimSpace(item.Direction)
	item.AccountID = strings.TrimSpace(item.AccountID)
	item.Counterparty = strings.TrimSpace(item.Counterparty)
	item.Description = strings.TrimSpace(item.Description)
	return item
}

func validateCategorySuggestionInput(item categorySuggestionInput) error {
	if !validDirection(item.Direction) {
		return fmt.Errorf("direction must be income, expense or transfer")
	}
	if item.AmountCent == nil || *item.AmountCent <= 0 {
		return fmt.Errorf("amount_cent must be a positive integer")
	}
	if item.TransactionTime == nil || *item.TransactionTime <= 0 {
		return fmt.Errorf("transaction_time must be a positive integer")
	}
	if item.AccountID == "" {
		return fmt.Errorf("account_id is required")
	}
	return nil
}

func (a *App) buildCategoryModels(ctx context.Context, direction string) (*categoryModels, error) {
	rows, err := a.categoryTrainingRows(ctx, direction)
	if err != nil {
		return nil, err
	}
	return &categoryModels{
		rows: rows,
		l1: trainNB(rows, func(row categoryTrainingRow) string {
			return row.CategoryL1ID
		}),
	}, nil
}

func (a *App) categoryTrainingRows(ctx context.Context, direction string) ([]categoryTrainingRow, error) {
	rows, err := a.db.QueryContext(ctx, `SELECT t.category_l1_id, COALESCE(t.category_l2_id, ''), t.account_id, t.amount_cent, t.transaction_time, COALESCE(t.counterparty, ''), COALESCE(t.description, '')
FROM transactions t
JOIN categories c ON c.id = t.category_l1_id
WHERE t.deleted_at IS NULL
  AND t.direction = ?
  AND c.parent_id IS NULL
  AND c.type = ?
  AND c.active = 1
  AND c.deleted_at IS NULL`, direction, direction)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []categoryTrainingRow{}
	for rows.Next() {
		var row categoryTrainingRow
		if err := rows.Scan(&row.CategoryL1ID, &row.CategoryL2ID, &row.AccountID, &row.AmountCent, &row.TransactionTime, &row.Counterparty, &row.Description); err != nil {
			return nil, err
		}
		out = append(out, row)
	}
	return out, rows.Err()
}

func (m *categoryModels) suggest(item categorySuggestionInput) categorySuggestionResult {
	base := categorySuggestionResult{
		ClientRef:    item.ClientRef,
		Method:       "insufficient_data",
		Alternatives: []categorySuggestionAlternative{},
	}
	if !m.l1.ready(nbMinDocs, nbMinClasses) {
		return base
	}
	scored := m.l1.classify(featuresForSuggestion(item))
	if len(scored) == 0 {
		return base
	}
	top := scored[0]
	result := categorySuggestionResult{
		ClientRef:    item.ClientRef,
		CategoryL1ID: top.label,
		CategoryL2ID: nil,
		Confidence:   top.confidence,
		Method:       "nb",
		Alternatives: make([]categorySuggestionAlternative, 0, minInt(3, len(scored))),
	}
	for i := 0; i < len(scored) && i < 3; i++ {
		result.Alternatives = append(result.Alternatives, categorySuggestionAlternative{
			CategoryL1ID: scored[i].label,
			CategoryL2ID: nil,
			Confidence:   scored[i].confidence,
		})
	}
	if l2 := m.suggestL2(item, top.label); l2 != "" {
		result.CategoryL2ID = &l2
	}
	return result
}

func (m *categoryModels) suggestL2(item categorySuggestionInput, categoryL1ID string) string {
	filtered := []categoryTrainingRow{}
	for _, row := range m.rows {
		if row.CategoryL1ID == categoryL1ID && row.CategoryL2ID != "" {
			filtered = append(filtered, row)
		}
	}
	model := trainNB(filtered, func(row categoryTrainingRow) string {
		return row.CategoryL2ID
	})
	if !model.ready(nbMinL2Docs, nbMinClasses) {
		return ""
	}
	scored := model.classify(featuresForSuggestion(item))
	if len(scored) == 0 {
		return ""
	}
	return scored[0].label
}

func trainNB(rows []categoryTrainingRow, labelFor func(categoryTrainingRow) string) *nbModel {
	model := &nbModel{
		classDocs:        map[string]int{},
		classTokenCounts: map[string]map[string]int{},
		classTokenTotals: map[string]int{},
		vocabulary:       map[string]struct{}{},
	}
	for _, row := range rows {
		label := strings.TrimSpace(labelFor(row))
		if label == "" {
			continue
		}
		model.totalDocs++
		model.classDocs[label]++
		if model.classTokenCounts[label] == nil {
			model.classTokenCounts[label] = map[string]int{}
		}
		for _, feature := range featuresForTraining(row) {
			model.classTokenCounts[label][feature]++
			model.classTokenTotals[label]++
			model.vocabulary[feature] = struct{}{}
		}
	}
	return model
}

func (m *nbModel) ready(minDocs, minClasses int) bool {
	return m != nil && m.totalDocs >= minDocs && len(m.classDocs) >= minClasses && len(m.vocabulary) > 0
}

func (m *nbModel) classify(features []string) []scoredClass {
	if !m.ready(1, 1) {
		return nil
	}
	if len(features) == 0 {
		features = []string{"bias"}
	}
	classes := make([]scoredClass, 0, len(m.classDocs))
	vocabSize := float64(len(m.vocabulary))
	for classID, docCount := range m.classDocs {
		score := math.Log(float64(docCount) / float64(m.totalDocs))
		denom := float64(m.classTokenTotals[classID]) + nbAlpha*vocabSize
		for _, feature := range features {
			count := m.classTokenCounts[classID][feature]
			score += math.Log(float64(count)+nbAlpha) - math.Log(denom)
		}
		classes = append(classes, scoredClass{label: classID, score: score})
	}
	sort.Slice(classes, func(i, j int) bool {
		return classes[i].score > classes[j].score
	})
	maxScore := math.Inf(-1)
	for _, item := range classes {
		if item.score > maxScore {
			maxScore = item.score
		}
	}
	sum := 0.0
	for _, item := range classes {
		sum += math.Exp(item.score - maxScore)
	}
	for i := range classes {
		classes[i].confidence = math.Exp(classes[i].score-maxScore) / sum
	}
	return classes
}

func featuresForTraining(row categoryTrainingRow) []string {
	return featuresFromFields(row.AccountID, row.AmountCent, row.TransactionTime, row.Counterparty, row.Description)
}

func featuresForSuggestion(item categorySuggestionInput) []string {
	amount := int64(0)
	if item.AmountCent != nil {
		amount = *item.AmountCent
	}
	txTime := int64(0)
	if item.TransactionTime != nil {
		txTime = *item.TransactionTime
	}
	return featuresFromFields(item.AccountID, amount, txTime, item.Counterparty, item.Description)
}

func featuresFromFields(accountID string, amountCent, _ int64, counterparty, description string) []string {
	features := []string{
		"account:" + strings.TrimSpace(accountID),
		"amount:" + amountBucket(amountCent),
	}
	features = appendTextFeatures(features, "cp", counterparty)
	features = appendTextFeatures(features, "desc", description)
	return features
}

func appendTextFeatures(features []string, prefix, raw string) []string {
	runes := normalizeTextRunes(raw)
	if len(runes) == 0 {
		return features
	}
	text := string(runes)
	features = append(features, prefix+":full:"+text)
	for _, n := range []int{2, 3} {
		if len(runes) < n {
			continue
		}
		for i := 0; i+n <= len(runes); i++ {
			features = append(features, fmt.Sprintf("%s:%d:%s", prefix, n, string(runes[i:i+n])))
		}
	}
	if len(runes) == 1 {
		features = append(features, prefix+":1:"+text)
	}
	return features
}

func normalizeTextRunes(raw string) []rune {
	out := []rune{}
	for _, r := range strings.ToLower(strings.TrimSpace(raw)) {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			out = append(out, r)
		}
	}
	return out
}

func amountBucket(amountCent int64) string {
	switch {
	case amountCent <= 0:
		return "unknown"
	case amountCent < 1000:
		return "lt10"
	case amountCent < 3000:
		return "lt30"
	case amountCent < 10000:
		return "lt100"
	case amountCent < 50000:
		return "lt500"
	case amountCent < 200000:
		return "lt2000"
	default:
		return "gte2000"
	}
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}
