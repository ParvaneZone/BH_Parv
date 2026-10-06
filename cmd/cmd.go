package cmd

import (
	"context"

	"github.com/ParvaneZone/BH_Parv/config"
	"github.com/ParvaneZone/BH_Parv/internal/client"

	"github.com/ParvaneZone/BH_Parv/internal/server"
	"github.com/ParvaneZone/BH_Parv/internal/utils"

	"github.com/BurntSushi/toml"
)

var (
	logger = utils.NewLogger("info")
)

func Run(configPath string, ctx context.Context) {
	// Load and parse the configuration file
	cfg, err := loadConfig(configPath)
	if err != nil {
		logger.Fatalf("failed to load configuration: %v", err)
	}

	// Apply default values to the configuration
	applyDefaults(cfg)

	configType := ""
	if cfg.Server.BindAddr != "" {
		configType = "server"
	} else if cfg.Client.RemoteAddr != "" {
		configType = "client"
	} else {
		logger.Fatalf("neither server nor client configuration is properly set.")
	}

	// Determine whether to run as a server or client
	switch configType {
	case "server":
		// Apply temporary TCP optimizations at startup
		if !cfg.Server.SkipOptz {
			ApplyTCPTuning()
		}

		validateTokenFor("server", cfg.Server.Token, string(cfg.Server.Transport))

		srv := server.NewServer(&cfg.Server, ctx) // server
		go srv.Start()
		scheduleRestart(ctx, cfg.Server.RestartInterval, cfg.Server.RestartAt, srv.Stop)

		// Wait for shutdown signal
		<-ctx.Done()
		srv.Stop()
		logger.Println("shutting down server...")
	case "client":
		// Apply temporary TCP optimizations at startup
		if !cfg.Client.SkipOptz {
			ApplyTCPTuning()
		}

		validateTokenFor("client", cfg.Client.Token, string(cfg.Client.Transport))

		clnt := client.NewClient(&cfg.Client, ctx) // client
		go clnt.Start()
		scheduleRestart(ctx, cfg.Client.RestartInterval, cfg.Client.RestartAt, clnt.Stop)

		// Wait for shutdown signal
		<-ctx.Done()
		clnt.Stop()
		logger.Println("shutting down client...")

	default:
		logger.Fatalf("neither server nor client configuration is properly set.")

	}
}

// loadConfig loads and parses the TOML configuration file.
func loadConfig(configPath string) (*config.Config, error) {
	var cfg config.Config
	if _, err := toml.DecodeFile(configPath, &cfg); err != nil {
		return &cfg, err
	}
	return &cfg, nil
}
