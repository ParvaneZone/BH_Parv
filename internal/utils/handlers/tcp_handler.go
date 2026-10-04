package handlers

import (
	"context"
	"errors"
	"io"
	"net"
	"sync"

	"github.com/ParvaneZone/BH_Parv/internal/web"
	"github.com/sirupsen/logrus"
)

// bufPool reuses 32KB copy buffers instead of allocating one per direction per connection.
var bufPool = sync.Pool{
	New: func() any {
		b := make([]byte, 32*1024)
		return &b
	},
}

func TCPConnectionHandler(ctx context.Context, proxyProtocol bool, from net.Conn, to net.Conn, logger *logrus.Logger, usage *web.Usage, remotePort int, sniffer bool) {
	done := make(chan struct{})

	// Write Proxy Protocol V2 Header
	if proxyProtocol {
		err := WriteProxyProtocol(from, to)
		if err != nil {
			logger.Error(err)
			from.Close()
			to.Close()
			return
		}
	}

	go func() {
		defer close(done)
		transferData(from, to, logger, usage, remotePort, sniffer)
	}()

	transferData(to, from, logger, usage, remotePort, sniffer)

	select {
	case <-ctx.Done():
		from.Close()
		to.Close()
		return
	case <-done:
	}
}

// Using direct Read and Write for transferring data
func transferData(from net.Conn, to net.Conn, logger *logrus.Logger, usage *web.Usage, remotePort int, sniffer bool) {
	bp := bufPool.Get().(*[]byte)
	defer bufPool.Put(bp)
	buf := *bp
	for {
		// Read data from the source connection
		r, err := from.Read(buf)
		if err != nil {
			if errors.Is(err, io.EOF) || errors.Is(err, net.ErrClosed) {
				logger.Trace("reader stream closed or EOF received")
			} else {
				logger.Trace("unable to read from the connection: ", err)
			}
			from.Close()
			to.Close()
			return
		}

		totalWritten := 0
		for totalWritten < r {
			// Write data to the destination connection
			w, err := to.Write(buf[totalWritten:r])
			if err != nil {
				if errors.Is(err, net.ErrClosed) {
					logger.Trace("writer stream closed or EOF received")
				} else {
					logger.Trace("unable to write to the connection: ", err)
				}
				from.Close()
				to.Close()
				return

			}
			totalWritten += w
		}

		logger.Tracef("read data: %d bytes, written data: %d bytes", r, totalWritten)
		if sniffer {
			usage.AddOrUpdatePort(remotePort, uint64(totalWritten))
		}
	}

}
