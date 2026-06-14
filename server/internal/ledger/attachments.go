package ledger

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strings"
	"time"
)

const maxUploadSizeBytes int64 = 20 * 1024 * 1024
const defaultPhotoJPGQuality = 18
const defaultThumbnailJPGQuality = 24

func (a *App) handleUploadAttachment(w http.ResponseWriter, r *http.Request, device Device) {
	r.Body = http.MaxBytesReader(w, r.Body, maxUploadSizeBytes+1024*1024)
	if err := r.ParseMultipartForm(maxUploadSizeBytes); err != nil {
		writeError(w, http.StatusBadRequest, "payload_too_large", "photo upload is too large or invalid")
		return
	}
	transactionID := strings.TrimSpace(r.FormValue("transaction_id"))
	if transactionID == "" {
		writeError(w, http.StatusBadRequest, "validation_error", "transaction_id is required")
		return
	}
	if _, err := a.getTransaction(r.Context(), transactionID, false); errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "not_found", "transaction not found")
		return
	} else if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to load transaction")
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "validation_error", "file is required")
		return
	}
	defer file.Close()
	if header.Size > maxUploadSizeBytes {
		writeError(w, http.StatusBadRequest, "payload_too_large", "photo upload exceeds 20 MB")
		return
	}
	prefix := make([]byte, 512)
	n, _ := file.Read(prefix)
	prefix = prefix[:n]
	contentType := http.DetectContentType(prefix)
	if !isSupportedImageType(contentType) {
		writeError(w, http.StatusBadRequest, "validation_error", "file must be an image")
		return
	}
	ffmpeg, err := a.ffmpegPath()
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, "ffmpeg_unavailable", "FFmpeg is not available")
		return
	}
	attachmentID, err := randomID("att")
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to create attachment")
		return
	}
	tmpInput := filepath.Join(a.cfg.Storage.TmpDir, attachmentID+".upload")
	tmp, err := os.Create(tmpInput)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to save upload")
		return
	}
	if _, err := io.Copy(tmp, io.MultiReader(bytes.NewReader(prefix), file)); err != nil {
		tmp.Close()
		_ = os.Remove(tmpInput)
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to save upload")
		return
	}
	if err := tmp.Close(); err != nil {
		_ = os.Remove(tmpInput)
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to save upload")
		return
	}
	defer os.Remove(tmpInput)

	storedName := attachmentID + ".jpg"
	thumbName := attachmentID + ".jpg"
	outputPath := filepath.Join(a.cfg.Storage.PhotosDir, storedName)
	thumbPath := filepath.Join(a.cfg.Storage.ThumbnailsDir, thumbName)
	a.storageMu.Lock()
	defer a.storageMu.Unlock()
	if err := a.compressImage(r.Context(), ffmpeg, tmpInput, outputPath, maxPositive(a.cfg.FFmpeg.MaxWidth, 1600), maxPositive(a.cfg.FFmpeg.MaxHeight, 1600), maxPositive(a.cfg.FFmpeg.JPGQuality, defaultPhotoJPGQuality)); err != nil {
		_ = os.Remove(outputPath)
		writeError(w, http.StatusServiceUnavailable, "ffmpeg_unavailable", "FFmpeg failed to compress photo")
		return
	}
	if err := a.compressImage(r.Context(), ffmpeg, outputPath, thumbPath, 480, 480, defaultThumbnailJPGQuality); err != nil {
		_ = os.Remove(outputPath)
		_ = os.Remove(thumbPath)
		writeError(w, http.StatusServiceUnavailable, "ffmpeg_unavailable", "FFmpeg failed to create thumbnail")
		return
	}
	hash, size, err := fileHashAndSize(outputPath)
	if err != nil {
		_ = os.Remove(outputPath)
		_ = os.Remove(thumbPath)
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to inspect compressed photo")
		return
	}
	now := unixNow()
	att := Attachment{
		ID:                attachmentID,
		TransactionID:     transactionID,
		OriginalFileName:  sanitizeUploadName(header.Filename),
		StoredFileName:    storedName,
		ThumbnailFileName: thumbName,
		SHA256:            hash,
		MimeType:          "image/jpeg",
		SizeBytes:         size,
		CompressionStatus: "done",
		CreatedAt:         now,
	}
	if err := a.insertAttachment(r.Context(), att); err != nil {
		_ = os.Remove(outputPath)
		_ = os.Remove(thumbPath)
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to save attachment")
		return
	}
	_ = a.writeAudit(r.Context(), "attachment", att.ID, "create", device.ID, nil)
	writeJSON(w, http.StatusCreated, att)
}

func (a *App) handleListAttachments(w http.ResponseWriter, r *http.Request, device Device) {
	transactionID := r.PathValue("id")
	if _, err := a.getTransaction(r.Context(), transactionID, false); err != nil {
		writeError(w, http.StatusNotFound, "not_found", "transaction not found")
		return
	}
	items, err := a.listAttachments(r.Context(), transactionID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to load attachments")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (a *App) handleGetAttachmentFile(w http.ResponseWriter, r *http.Request, device Device) {
	a.serveAttachmentFile(w, r, false)
}

func (a *App) handleGetAttachmentThumbnail(w http.ResponseWriter, r *http.Request, device Device) {
	a.serveAttachmentFile(w, r, true)
}

func (a *App) handleDeleteAttachment(w http.ResponseWriter, r *http.Request, device Device) {
	id := r.PathValue("id")
	if _, err := a.getAttachment(r.Context(), id); errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "not_found", "attachment not found")
		return
	} else if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to load attachment")
		return
	}
	if err := a.softDeleteAttachment(r.Context(), id); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to delete attachment")
		return
	}
	_ = a.writeAudit(r.Context(), "attachment", id, "delete", device.ID, nil)
	writeJSON(w, http.StatusOK, map[string]any{"deleted": true, "id": id})
}

func (a *App) serveAttachmentFile(w http.ResponseWriter, r *http.Request, thumbnail bool) {
	att, err := a.getAttachment(r.Context(), r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusNotFound, "not_found", "attachment not found")
		return
	}
	name := att.StoredFileName
	dir := a.cfg.Storage.PhotosDir
	if thumbnail {
		name = att.ThumbnailFileName
		dir = a.cfg.Storage.ThumbnailsDir
	}
	if name == "" || name != filepath.Base(name) {
		writeError(w, http.StatusNotFound, "not_found", "attachment file not found")
		return
	}
	fullPath := filepath.Join(dir, name)
	if _, err := os.Stat(fullPath); err != nil {
		writeError(w, http.StatusNotFound, "not_found", "attachment file not found")
		return
	}
	w.Header().Set("Content-Type", "image/jpeg")
	w.Header().Set("Cache-Control", "private, max-age=3600")
	http.ServeFile(w, r, fullPath)
}

func (a *App) ffmpegPath() (string, error) {
	configured := strings.TrimSpace(a.cfg.FFmpeg.Path)
	if configured == "" {
		configured = "ffmpeg"
	}
	resolved, err := exec.LookPath(configured)
	if err != nil {
		return "", err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := exec.CommandContext(ctx, resolved, "-version").Run(); err != nil {
		return "", err
	}
	return resolved, nil
}

func (a *App) compressImage(ctx context.Context, ffmpeg, input, output string, maxWidth, maxHeight, quality int) error {
	if err := os.MkdirAll(filepath.Dir(output), 0o755); err != nil {
		return err
	}
	filter := fmt.Sprintf("scale=w='min(%d,iw)':h='min(%d,ih)':force_original_aspect_ratio=decrease", maxWidth, maxHeight)
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, ffmpeg,
		"-y",
		"-i", input,
		"-vf", filter,
		"-frames:v", "1",
		"-q:v", fmt.Sprintf("%d", quality),
		"-map_metadata", "-1",
		output,
	)
	return cmd.Run()
}

func (a *App) insertAttachment(ctx context.Context, att Attachment) error {
	_, err := a.db.ExecContext(ctx, `INSERT INTO attachments(id, transaction_id, original_file_name, stored_file_name, thumbnail_file_name, sha256, mime_type, size_bytes, width, height, compression_status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		att.ID, att.TransactionID, nullString(att.OriginalFileName), att.StoredFileName, nullString(att.ThumbnailFileName), att.SHA256, att.MimeType, att.SizeBytes, nil, nil, att.CompressionStatus, att.CreatedAt)
	return err
}

func (a *App) listAttachments(ctx context.Context, transactionID string) ([]Attachment, error) {
	rows, err := a.db.QueryContext(ctx, attachmentSelectSQL+` WHERE transaction_id = ? AND deleted_at IS NULL ORDER BY created_at`, transactionID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Attachment{}
	for rows.Next() {
		att, err := scanAttachment(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, att)
	}
	return items, rows.Err()
}

func (a *App) getAttachment(ctx context.Context, id string) (Attachment, error) {
	return scanAttachment(a.db.QueryRowContext(ctx, attachmentSelectSQL+` WHERE id = ? AND deleted_at IS NULL`, id))
}

func (a *App) softDeleteAttachment(ctx context.Context, id string) error {
	result, err := a.db.ExecContext(ctx, `UPDATE attachments SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL`, unixNow(), id)
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

const attachmentSelectSQL = `SELECT id, transaction_id, COALESCE(original_file_name, ''), stored_file_name, COALESCE(thumbnail_file_name, ''), sha256, mime_type, size_bytes, width, height, compression_status, created_at, deleted_at FROM attachments`

func scanAttachment(row scanner) (Attachment, error) {
	var att Attachment
	var width, height sql.NullInt64
	var deletedAt sql.NullInt64
	err := row.Scan(&att.ID, &att.TransactionID, &att.OriginalFileName, &att.StoredFileName, &att.ThumbnailFileName, &att.SHA256, &att.MimeType, &att.SizeBytes, &width, &height, &att.CompressionStatus, &att.CreatedAt, &deletedAt)
	if width.Valid {
		v := int(width.Int64)
		att.Width = &v
	}
	if height.Valid {
		v := int(height.Int64)
		att.Height = &v
	}
	if deletedAt.Valid {
		att.DeletedAt = &deletedAt.Int64
	}
	return att, err
}

func isSupportedImageType(contentType string) bool {
	switch strings.ToLower(contentType) {
	case "image/jpeg", "image/png", "image/webp", "image/gif":
		return true
	default:
		return false
	}
}

func sanitizeUploadName(name string) string {
	name = strings.ReplaceAll(name, "\\", "/")
	return path.Base(name)
}

func fileHashAndSize(filePath string) (string, int64, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return "", 0, err
	}
	defer file.Close()
	hash := sha256.New()
	size, err := io.Copy(hash, file)
	if err != nil {
		return "", 0, err
	}
	return hex.EncodeToString(hash.Sum(nil)), size, nil
}

func maxPositive(value, fallback int) int {
	if value <= 0 {
		return fallback
	}
	return value
}
