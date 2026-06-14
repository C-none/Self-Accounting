package ledger

import (
	"encoding/json"
	"fmt"
	"os"
)

type Config struct {
	Server struct {
		ListenAddr    string `json:"listen_addr"`
		PublicBaseURL string `json:"public_base_url"`
		RequireHTTPS  bool   `json:"require_https"`
		WebDir        string `json:"web_dir"`
	} `json:"server"`
	Database struct {
		Path        string `json:"path"`
		BusyTimeout int    `json:"busy_timeout_ms"`
		Synchronous string `json:"synchronous"`
	} `json:"database"`
	Storage struct {
		PhotosDir     string `json:"photos_dir"`
		ThumbnailsDir string `json:"thumbnails_dir"`
		TmpDir        string `json:"tmp_dir"`
	} `json:"storage"`
	FFmpeg struct {
		Path       string `json:"path"`
		JPGQuality int    `json:"jpg_quality"`
		MaxWidth   int    `json:"max_width"`
		MaxHeight  int    `json:"max_height"`
	} `json:"ffmpeg"`
	Backup struct {
		Dir string `json:"dir"`
	} `json:"backup"`
	Security struct {
		SecretPath string `json:"secret_path"`
	} `json:"security"`
}

func LoadConfig(path string) (Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Config{}, err
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return Config{}, err
	}
	if cfg.Server.ListenAddr == "" {
		return Config{}, fmt.Errorf("server.listen_addr is required")
	}
	if cfg.Database.Path == "" {
		return Config{}, fmt.Errorf("database.path is required")
	}
	if cfg.Database.BusyTimeout <= 0 {
		cfg.Database.BusyTimeout = 5000
	}
	if cfg.Database.Synchronous == "" {
		cfg.Database.Synchronous = "NORMAL"
	}
	if cfg.Server.WebDir == "" {
		cfg.Server.WebDir = "./client/build/web"
	}
	if cfg.Security.SecretPath == "" {
		cfg.Security.SecretPath = "./var/dev/server-secret.key"
	}
	return cfg, nil
}
