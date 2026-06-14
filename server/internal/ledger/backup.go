package ledger

import (
	"archive/zip"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

func (a *App) handleAdminCheckpoint(w http.ResponseWriter, r *http.Request, device Device) {
	result, err := a.checkpoint(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to checkpoint database")
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (a *App) handleAdminBackup(w http.ResponseWriter, r *http.Request, device Device) {
	if !a.backupMu.TryLock() {
		writeError(w, http.StatusConflict, "backup_in_progress", "backup is already running")
		return
	}
	defer a.backupMu.Unlock()
	a.storageMu.Lock()
	defer a.storageMu.Unlock()

	if _, err := a.checkpoint(r.Context()); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to checkpoint database")
		return
	}
	now := time.Now().UTC()
	name := fmt.Sprintf("ledger-backup-%s.zip", now.Format("20060102-150405"))
	tmpDir := filepath.Join(a.cfg.Backup.Dir, strings.TrimSuffix(name, ".zip")+".tmp")
	_ = os.RemoveAll(tmpDir)
	if err := os.MkdirAll(tmpDir, 0o755); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to prepare backup")
		return
	}
	defer os.RemoveAll(tmpDir)

	dbCopy := filepath.Join(tmpDir, "app.db")
	if err := a.backupDatabase(r.Context(), dbCopy); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to backup database")
		return
	}
	manifest := map[string]any{
		"format_version": 1,
		"created_at":     now.Format(time.RFC3339),
		"source_os":      runtime.GOOS,
		"app_version":    "0.1.0",
		"database_file":  "app.db",
		"photos_dir":     "photos",
		"thumbnails_dir": "thumbnails",
		"currency":       "CNY",
		"amount_unit":    "cent",
		"config_file":    "config.export.json",
	}
	if err := writeJSONFile(filepath.Join(tmpDir, "manifest.json"), manifest); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to write backup manifest")
		return
	}
	if err := writeJSONFile(filepath.Join(tmpDir, "config.export.json"), a.configExport()); err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to write backup config")
		return
	}
	target := filepath.Join(a.cfg.Backup.Dir, name)
	if err := a.writeBackupZip(target, tmpDir); err != nil {
		_ = os.Remove(target)
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to write backup zip")
		return
	}
	info, err := os.Stat(target)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal_error", "failed to inspect backup")
		return
	}
	_ = a.writeAudit(r.Context(), "backup", name, "create", device.ID, nil)
	writeJSON(w, http.StatusOK, map[string]any{
		"file_name":  name,
		"size_bytes": info.Size(),
		"created_at": now.Unix(),
	})
}

func (a *App) checkpoint(ctx context.Context) (map[string]any, error) {
	var busy, logFrames, checkpointedFrames int
	err := a.db.QueryRowContext(ctx, `PRAGMA wal_checkpoint(TRUNCATE)`).Scan(&busy, &logFrames, &checkpointedFrames)
	if err != nil {
		return nil, err
	}
	return map[string]any{
		"busy":                busy,
		"log_frames":          logFrames,
		"checkpointed_frames": checkpointedFrames,
	}, nil
}

func (a *App) backupDatabase(ctx context.Context, target string) error {
	if err := ensureDirForFile(target); err != nil {
		return err
	}
	_ = os.Remove(target)
	_, err := a.db.ExecContext(ctx, `VACUUM INTO ?`, target)
	return err
}

func (a *App) writeBackupZip(target, tmpDir string) error {
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return err
	}
	file, err := os.Create(target)
	if err != nil {
		return err
	}
	defer file.Close()
	zw := zip.NewWriter(file)
	defer zw.Close()

	for _, name := range []string{"manifest.json", "app.db", "config.export.json"} {
		if err := addFileToZip(zw, filepath.Join(tmpDir, name), name); err != nil {
			return err
		}
	}
	for _, dir := range []struct {
		source string
		prefix string
	}{
		{a.cfg.Storage.PhotosDir, "photos"},
		{a.cfg.Storage.ThumbnailsDir, "thumbnails"},
	} {
		if err := addDirToZip(zw, dir.source, dir.prefix); err != nil {
			return err
		}
	}
	return nil
}

func (a *App) configExport() map[string]any {
	return map[string]any{
		"server": map[string]any{
			"public_base_url": a.cfg.Server.PublicBaseURL,
			"require_https":   a.cfg.Server.RequireHTTPS,
			"web_dir":         a.cfg.Server.WebDir,
		},
		"database": map[string]any{
			"busy_timeout_ms": a.cfg.Database.BusyTimeout,
			"synchronous":     a.cfg.Database.Synchronous,
		},
		"storage": map[string]any{
			"photos_dir":     "photos",
			"thumbnails_dir": "thumbnails",
			"tmp_dir":        "tmp",
		},
		"ffmpeg": map[string]any{
			"path":        a.cfg.FFmpeg.Path,
			"jpg_quality": a.cfg.FFmpeg.JPGQuality,
			"max_width":   a.cfg.FFmpeg.MaxWidth,
			"max_height":  a.cfg.FFmpeg.MaxHeight,
		},
	}
}

func writeJSONFile(path string, payload any) error {
	if err := ensureDirForFile(path); err != nil {
		return err
	}
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()
	enc := json.NewEncoder(file)
	enc.SetIndent("", "  ")
	return enc.Encode(payload)
}

func addFileToZip(zw *zip.Writer, sourcePath, archiveName string) error {
	info, err := os.Stat(sourcePath)
	if err != nil {
		return err
	}
	header, err := zip.FileInfoHeader(info)
	if err != nil {
		return err
	}
	header.Name = filepath.ToSlash(archiveName)
	header.Method = zip.Deflate
	writer, err := zw.CreateHeader(header)
	if err != nil {
		return err
	}
	file, err := os.Open(sourcePath)
	if err != nil {
		return err
	}
	defer file.Close()
	_, err = io.Copy(writer, file)
	return err
}

func addDirToZip(zw *zip.Writer, sourceDir, prefix string) error {
	if _, err := os.Stat(sourceDir); os.IsNotExist(err) {
		header := &zip.FileHeader{Name: filepath.ToSlash(prefix) + "/", Method: zip.Store}
		_, err := zw.CreateHeader(header)
		return err
	}
	return filepath.WalkDir(sourceDir, func(filePath string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(sourceDir, filePath)
		if err != nil {
			return err
		}
		if rel == "." {
			header := &zip.FileHeader{Name: filepath.ToSlash(prefix) + "/", Method: zip.Store}
			_, err := zw.CreateHeader(header)
			return err
		}
		archiveName := filepath.Join(prefix, rel)
		if d.IsDir() {
			header := &zip.FileHeader{Name: filepath.ToSlash(archiveName) + "/", Method: zip.Store}
			_, err := zw.CreateHeader(header)
			return err
		}
		return addFileToZip(zw, filePath, archiveName)
	})
}
