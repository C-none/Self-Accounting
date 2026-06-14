package main

import (
	"context"
	"errors"
	"flag"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"accounting/server/internal/ledger"
)

func main() {
	configPath := flag.String("config", "./config.json", "path to JSON config")
	flag.Parse()

	cfg, err := ledger.LoadConfig(*configPath)
	if err != nil {
		log.Fatalf("load config: %v", err)
	}

	app, err := ledger.NewApp(cfg)
	if err != nil {
		log.Fatalf("initialize app: %v", err)
	}
	defer app.Close()

	server := &http.Server{
		Addr:              cfg.Server.ListenAddr,
		Handler:           app.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		log.Printf("ledger server listening on %s", cfg.Server.ListenAddr)
		for _, url := range displayURLs(cfg.Server.ListenAddr, cfg.Server.PublicBaseURL) {
			log.Printf("ledger web/API URL: %s", url)
		}
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("serve: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(ctx); err != nil {
		log.Printf("shutdown: %v", err)
	}
}

func displayURLs(listenAddr, publicBaseURL string) []string {
	seen := map[string]bool{}
	out := []string{}
	add := func(url string) {
		if url == "" || seen[url] {
			return
		}
		seen[url] = true
		out = append(out, url)
	}
	add(strings.TrimRight(publicBaseURL, "/"))

	host, port, err := net.SplitHostPort(listenAddr)
	if err != nil || port == "" {
		return out
	}
	scheme := "http"
	if strings.HasPrefix(publicBaseURL, "https://") {
		scheme = "https"
	}
	if host == "" || host == "0.0.0.0" || host == "::" {
		add(scheme + "://127.0.0.1:" + port)
		for _, ip := range localIPv4s() {
			add(scheme + "://" + ip + ":" + port)
		}
		return out
	}
	add(scheme + "://" + host + ":" + port)
	return out
}

func localIPv4s() []string {
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil
	}
	out := []string{}
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			var ip net.IP
			switch v := addr.(type) {
			case *net.IPNet:
				ip = v.IP
			case *net.IPAddr:
				ip = v.IP
			}
			if ip4 := ip.To4(); ip4 != nil {
				out = append(out, ip4.String())
			}
		}
	}
	return out
}
