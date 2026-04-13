const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');
const pty = require('node-pty');

const PORT = 2323;
const SHELL = process.env.SHELL || '/bin/zsh';

const MIME = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.css': 'text/css',
};

const server = http.createServer((req, res) => {
  const filePath = path.join(__dirname, 'public', req.url === '/' ? 'index.html' : req.url.split('?')[0]);
  const ext = path.extname(filePath);
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end('Not found');
      return;
    }
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
    res.end(data);
  });
});

const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (req, socket, head) => {
  const match = req.url.match(/^\/ws\/terminal\/(\d+)/);
  if (!match) {
    socket.destroy();
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host}`);
  const cols = parseInt(url.searchParams.get('cols')) || 80;
  const rows = parseInt(url.searchParams.get('rows')) || 24;

  wss.handleUpgrade(req, socket, head, (ws) => {
    const ptyProcess = pty.spawn(SHELL, [], {
      name: 'xterm-256color',
      cols,
      rows,
      cwd: process.env.HOME,
      env: { ...process.env, TERM: 'xterm-256color' },
    });

    ptyProcess.onData((data) => {
      try { ws.send(data); } catch {}
    });

    ws.on('message', (msg) => {
      const data = typeof msg === 'string' ? msg : Buffer.from(msg).toString();
      // Control message: resize (prefix byte 0x01)
      if (data.charCodeAt(0) === 1) {
        try {
          const { cols, rows } = JSON.parse(data.slice(1));
          ptyProcess.resize(cols, rows);
        } catch {}
        return;
      }
      ptyProcess.write(data);
    });

    ws.on('close', () => {
      ptyProcess.kill();
    });

    ptyProcess.onExit(() => {
      try { ws.close(); } catch {}
    });
  });
});

server.listen(PORT, () => {
  console.log(`floaterm running at http://localhost:${PORT}`);
});
