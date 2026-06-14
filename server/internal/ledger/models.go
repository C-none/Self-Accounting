package ledger

type Device struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Platform   string `json:"platform"`
	IsAdmin    bool   `json:"is_admin"`
	LastSeenAt *int64 `json:"last_seen_at,omitempty"`
}

type AuditLogEntry struct {
	ID         string `json:"id"`
	EntityType string `json:"entity_type"`
	EntityID   string `json:"entity_id"`
	Action     string `json:"action"`
	DeviceID   string `json:"device_id"`
	DeviceName string `json:"device_name,omitempty"`
	CreatedAt  int64  `json:"created_at"`
}

type Category struct {
	ID        string `json:"id"`
	ParentID  string `json:"parent_id,omitempty"`
	Name      string `json:"name"`
	Type      string `json:"type"`
	SortOrder int    `json:"sort_order"`
	Active    bool   `json:"active"`
}

type Member struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	SortOrder int    `json:"sort_order"`
	Active    bool   `json:"active"`
}

type Account struct {
	ID               string `json:"id"`
	Name             string `json:"name"`
	Type             string `json:"type"`
	MaskedIdentifier string `json:"masked_identifier,omitempty"`
	SortOrder        int    `json:"sort_order"`
	Active           bool   `json:"active"`
}

type Transaction struct {
	ID                string `json:"id"`
	AmountCent        int64  `json:"amount_cent"`
	Currency          string `json:"currency"`
	Direction         string `json:"direction"`
	TransactionTime   int64  `json:"transaction_time"`
	CategoryL1ID      string `json:"category_l1_id"`
	CategoryL2ID      string `json:"category_l2_id,omitempty"`
	MemberID          string `json:"member_id"`
	AccountID         string `json:"account_id"`
	Counterparty      string `json:"counterparty,omitempty"`
	Description       string `json:"description,omitempty"`
	Source            string `json:"source"`
	SourceRef         string `json:"source_ref,omitempty"`
	CreatedByDeviceID string `json:"created_by_device_id"`
	CreatedAt         int64  `json:"created_at"`
	UpdatedAt         int64  `json:"updated_at"`
	DeletedAt         *int64 `json:"deleted_at,omitempty"`
	Version           int64  `json:"version"`
}

type TransactionList struct {
	Items    []Transaction `json:"items"`
	Page     int           `json:"page"`
	PageSize int           `json:"page_size"`
	Total    int           `json:"total"`
}

type Attachment struct {
	ID                string `json:"id"`
	TransactionID     string `json:"transaction_id"`
	OriginalFileName  string `json:"original_file_name,omitempty"`
	StoredFileName    string `json:"stored_file_name"`
	ThumbnailFileName string `json:"thumbnail_file_name,omitempty"`
	SHA256            string `json:"sha256"`
	MimeType          string `json:"mime_type"`
	SizeBytes         int64  `json:"size_bytes"`
	Width             *int   `json:"width,omitempty"`
	Height            *int   `json:"height,omitempty"`
	CompressionStatus string `json:"compression_status"`
	CreatedAt         int64  `json:"created_at"`
	DeletedAt         *int64 `json:"deleted_at,omitempty"`
}
