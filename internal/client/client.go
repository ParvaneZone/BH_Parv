package client

import (
	"context"
	"time"

	"github.com/ParvaneZone/BH_Parv/internal/utils"
	"github.com/ParvaneZone/BH_Parv/internal/utils/network"

	"github.com/ParvaneZone/BH_Parv/config"

	"github.com/ParvaneZone/BH_Parv/internal/client/transport"

	"net/http"
	_ "net/http/pprof"

	"github.com/sirupsen/logrus"
)

// Client encapsulates the client configuration and state
type Client struct {
	config *config.ClientConfig
	ctx    context.Context
	cancel context.CancelFunc
	logger *logrus.Logger
}

func NewClient(cfg *config.ClientConfig, parentCtx context.Context) *Client {
	ctx, cancel := context.WithCancel(parentCtx)
	return &Client{
		config: cfg,
		ctx:    ctx,
		cancel: cancel,
		logger: utils.NewLogger(cfg.LogLevel),
	}
}

// Run starts the client and begins dialing the tunnel server
func (c *Client) Start() {
	// for pprof
	if c.config.PPROF {
		go func() {
			c.logger.Info("pprof started at port 6061")
			http.ListenAndServe("127.0.0.1:6061", nil)
		}()
	}

	network.SetTLSOptions(network.TLSOptions{
		Verify: c.config.TLSVerify,
		Pin:    c.config.TLSPin,
		SNI:    c.config.TLSSNI,
	})
	if (c.config.Transport == config.WSS || c.config.Transport == config.WSSMUX) && !c.config.TLSVerify && c.config.TLSPin == "" {
		c.logger.Warn("wss without tls_verify or tls_pin: the server certificate is NOT validated (MITM possible). Set tls_pin to the server certificate sha256 fingerprint.")
	}

	c.logger.Infof("client with remote address %s started successfully", c.config.RemoteAddr)

	switch c.config.Transport {
	case config.TCP:
		tcpConfig := &transport.TcpConfig{
			RemoteAddr:     c.config.RemoteAddr,
			Nodelay:        c.config.Nodelay,
			KeepAlive:      time.Duration(c.config.Keepalive) * time.Second,
			RetryInterval:  time.Duration(c.config.RetryInterval) * time.Second,
			DialTimeOut:    time.Duration(c.config.DialTimeout) * time.Second,
			ConnPoolSize:   c.config.ConnectionPool,
			Token:          c.config.Token,
			Sniffer:        c.config.Sniffer,
			WebPort:        c.config.WebPort,
			SnifferLog:     c.config.SnifferLog,
			AggressivePool: c.config.AggressivePool,
			MSS:            c.config.MSS,
			SO_RCVBUF:      c.config.SO_RCVBUF,
			SO_SNDBUF:      c.config.SO_SNDBUF,
		}
		tcpClient := transport.NewTCPClient(c.ctx, tcpConfig, c.logger)
		go tcpClient.Start()

	case config.TCPMUX:
		tcpMuxConfig := &transport.TcpMuxConfig{
			RemoteAddr:       c.config.RemoteAddr,
			Nodelay:          c.config.Nodelay,
			KeepAlive:        time.Duration(c.config.Keepalive) * time.Second,
			RetryInterval:    time.Duration(c.config.RetryInterval) * time.Second,
			DialTimeOut:      time.Duration(c.config.DialTimeout) * time.Second,
			ConnPoolSize:     c.config.ConnectionPool,
			Token:            c.config.Token,
			MuxVersion:       c.config.MuxVersion,
			MaxFrameSize:     c.config.MaxFrameSize,
			MaxReceiveBuffer: c.config.MaxReceiveBuffer,
			MaxStreamBuffer:  c.config.MaxStreamBuffer,
			Sniffer:          c.config.Sniffer,
			WebPort:          c.config.WebPort,
			SnifferLog:       c.config.SnifferLog,
			AggressivePool:   c.config.AggressivePool,
			MSS:              c.config.MSS,
			SO_RCVBUF:        c.config.SO_RCVBUF,
			SO_SNDBUF:        c.config.SO_SNDBUF,
		}
		tcpMuxClient := transport.NewMuxClient(c.ctx, tcpMuxConfig, c.logger)
		go tcpMuxClient.Start()

	case config.WS, config.WSS:
		WsConfig := &transport.WsConfig{
			RemoteAddr:     c.config.RemoteAddr,
			Nodelay:        c.config.Nodelay,
			KeepAlive:      time.Duration(c.config.Keepalive) * time.Second,
			RetryInterval:  time.Duration(c.config.RetryInterval) * time.Second,
			DialTimeOut:    time.Duration(c.config.DialTimeout) * time.Second,
			ConnPoolSize:   c.config.ConnectionPool,
			Token:          c.config.Token,
			Sniffer:        c.config.Sniffer,
			WebPort:        c.config.WebPort,
			SnifferLog:     c.config.SnifferLog,
			Mode:           c.config.Transport,
			AggressivePool: c.config.AggressivePool,
			EdgeIP:         c.config.EdgeIP,
		}
		WsClient := transport.NewWSClient(c.ctx, WsConfig, c.logger)
		go WsClient.Start()

	case config.WSMUX, config.WSSMUX:
		wsMuxConfig := &transport.WsMuxConfig{
			RemoteAddr:       c.config.RemoteAddr,
			Nodelay:          c.config.Nodelay,
			KeepAlive:        time.Duration(c.config.Keepalive) * time.Second,
			RetryInterval:    time.Duration(c.config.RetryInterval) * time.Second,
			DialTimeOut:      time.Duration(c.config.DialTimeout) * time.Second,
			ConnPoolSize:     c.config.ConnectionPool,
			Token:            c.config.Token,
			MuxVersion:       c.config.MuxVersion,
			MaxFrameSize:     c.config.MaxFrameSize,
			MaxReceiveBuffer: c.config.MaxReceiveBuffer,
			MaxStreamBuffer:  c.config.MaxStreamBuffer,
			Sniffer:          c.config.Sniffer,
			WebPort:          c.config.WebPort,
			SnifferLog:       c.config.SnifferLog,
			Mode:             c.config.Transport,
			AggressivePool:   c.config.AggressivePool,
			EdgeIP:           c.config.EdgeIP,
		}
		wsMuxClient := transport.NewWSMuxClient(c.ctx, wsMuxConfig, c.logger)
		go wsMuxClient.Start()

	case config.KCPMUX:
		kcpMuxConfig := &transport.KcpMuxConfig{
			RemoteAddr:       c.config.RemoteAddr,
			Nodelay:          c.config.Nodelay,
			KeepAlive:        time.Duration(c.config.Keepalive) * time.Second,
			RetryInterval:    time.Duration(c.config.RetryInterval) * time.Second,
			DialTimeOut:      time.Duration(c.config.DialTimeout) * time.Second,
			ConnPoolSize:     c.config.ConnectionPool,
			Token:            c.config.Token,
			MuxVersion:       c.config.MuxVersion,
			MaxFrameSize:     c.config.MaxFrameSize,
			MaxReceiveBuffer: c.config.MaxReceiveBuffer,
			MaxStreamBuffer:  c.config.MaxStreamBuffer,
			Sniffer:          c.config.Sniffer,
			WebPort:          c.config.WebPort,
			SnifferLog:       c.config.SnifferLog,
			AggressivePool:   c.config.AggressivePool,
			MSS:              c.config.MSS,
			SO_RCVBUF:        c.config.SO_RCVBUF,
			SO_SNDBUF:        c.config.SO_SNDBUF,
			KCP: network.KCPOptions{
				Mode: c.config.KCPMode, MTU: c.config.KCPMTU, SndWnd: c.config.KCPSndWnd, RcvWnd: c.config.KCPRcvWnd,
				DataShard: c.config.KCPDataShard, ParityShard: c.config.KCPParityShard, SockBuf: c.config.KCPSockBuf,
			},
		}
		kcpMuxClient := transport.NewKcpMuxClient(c.ctx, kcpMuxConfig, c.logger)
		go kcpMuxClient.Start()

	case config.UDP:
		udpConfig := &transport.UdpConfig{
			RemoteAddr:     c.config.RemoteAddr,
			RetryInterval:  time.Duration(c.config.RetryInterval) * time.Second,
			DialTimeOut:    time.Duration(c.config.DialTimeout) * time.Second,
			ConnPoolSize:   c.config.ConnectionPool,
			Token:          c.config.Token,
			Sniffer:        c.config.Sniffer,
			WebPort:        c.config.WebPort,
			SnifferLog:     c.config.SnifferLog,
			AggressivePool: c.config.AggressivePool,
		}
		udpClient := transport.NewUDPClient(c.ctx, udpConfig, c.logger)
		go udpClient.Start()

	default:
		c.logger.Fatal("invalid transport type: ", c.config.Transport)
	}

	<-c.ctx.Done()

	c.logger.Info("all workers stopped successfully")

	// suppress other logs
	c.logger.SetLevel(logrus.FatalLevel)
}
func (c *Client) Stop() {
	if c.cancel != nil {
		c.cancel()
	}
}
