const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');
const pty = require('node-pty');

const PORT = 2323;
const SHELL = process.env.SHELL || '/bin/zsh';
const STATE_DIR = path.join(process.env.HOME, '.floaterm');
const STATE_FILE = path.join(STATE_DIR, 'state.json');
const SCROLLBACK_LIMIT = 50000; // chars to buffer per session

// ── Persistent PTY sessions ──────────────────────────────────────────
// Sessions survive WebSocket disconnects. On reconnect, scrollback is replayed.
const sessions = new Map(); // id -> { pty, scrollback, alive, cols, rows }

function getOrCreateSession(id, cols, rows) {
  if (sessions.has(id)) {
    const s = sessions.get(id);
    if (s.alive) {
      // Resize to match new client dimensions
      try { s.pty.resize(cols, rows); } catch {}
      s.cols = cols;
      s.rows = rows;
      return s;
    }
    // Dead session — clean up and create fresh
    sessions.delete(id);
  }

  const ptyProcess = pty.spawn(SHELL, [], {
    name: 'xterm-256color',
    cols,
    rows,
    cwd: process.env.HOME,
    env: { ...process.env, TERM: 'xterm-256color' },
  });

  const session = { pty: ptyProcess, scrollback: '', alive: true, cols, rows, ws: null };

  ptyProcess.onData((data) => {
    // Buffer scrollback
    session.scrollback += data;
    if (session.scrollback.length > SCROLLBACK_LIMIT) {
      session.scrollback = session.scrollback.slice(-SCROLLBACK_LIMIT);
    }
    // Forward to connected client
    if (session.ws) {
      try { session.ws.send(data); } catch {}
    }
  });

  ptyProcess.onExit(() => {
    session.alive = false;
    if (session.ws) {
      try { session.ws.close(); } catch {}
    }
  });

  sessions.set(id, session);
  return session;
}

function destroySession(id) {
  const s = sessions.get(id);
  if (s) {
    if (s.alive) try { s.pty.kill(); } catch {}
    sessions.delete(id);
  }
}

// ── State persistence ────────────────────────────────────────────────
function loadState() {
  try {
    return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
  } catch { return null; }
}

function saveState(state) {
  try {
    fs.mkdirSync(STATE_DIR, { recursive: true });
    fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
  } catch (e) {
    console.error('Failed to save state:', e.message);
  }
}

// ── HTTP server ──────────────────────────────────────────────────────
const MIME = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.css': 'text/css',
};

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  // REST API: GET/POST state
  if (url.pathname === '/api/state') {
    if (req.method === 'GET') {
      const state = loadState();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(state || {}));
      return;
    }
    if (req.method === 'POST') {
      let body = '';
      req.on('data', chunk => body += chunk);
      req.on('end', () => {
        try {
          saveState(JSON.parse(body));
          res.writeHead(200);
          res.end('ok');
        } catch {
          res.writeHead(400);
          res.end('invalid json');
        }
      });
      return;
    }
  }

  // REST API: DELETE a session
  if (url.pathname.startsWith('/api/session/') && req.method === 'DELETE') {
    const id = url.pathname.split('/').pop();
    destroySession(id);
    res.writeHead(200);
    res.end('ok');
    return;
  }

  // REST API: list alive sessions
  if (url.pathname === '/api/sessions' && req.method === 'GET') {
    const alive = [];
    for (const [id, s] of sessions) {
      if (s.alive) alive.push(id);
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(alive));
    return;
  }

  // REST API: SSH hosts from ~/.ssh/config
  if (url.pathname === '/api/ssh-hosts' && req.method === 'GET') {
    let hosts = [];
    try {
      const sshConfig = fs.readFileSync(path.join(process.env.HOME, '.ssh', 'config'), 'utf8');
      const matches = sshConfig.match(/^Host\s+(.+)$/gm);
      if (matches) {
        hosts = matches.map(h => h.replace(/^Host\s+/, '').trim()).filter(h => !h.includes('*'));
      }
    } catch {}
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(hosts));
    return;
  }

  // Static files
  const filePath = path.join(__dirname, 'public', url.pathname === '/' ? 'index.html' : url.pathname);
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

// ── WebSocket ────────────────────────────────────────────────────────
const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (req, socket, head) => {
  const match = req.url.match(/^\/ws\/terminal\/([^?]+)/);
  if (!match) {
    socket.destroy();
    return;
  }

  const id = match[1];
  const url = new URL(req.url, `http://${req.headers.host}`);
  const cols = parseInt(url.searchParams.get('cols')) || 80;
  const rows = parseInt(url.searchParams.get('rows')) || 24;

  wss.handleUpgrade(req, socket, head, (ws) => {
    const session = getOrCreateSession(id, cols, rows);

    // Detach previous client if any
    if (session.ws) {
      try { session.ws.close(); } catch {}
    }
    session.ws = ws;

    // Replay scrollback to new client
    if (session.scrollback) {
      ws.send(session.scrollback);
    }

    ws.on('message', (msg) => {
      if (!session.alive) return;
      const data = typeof msg === 'string' ? msg : Buffer.from(msg).toString();
      // Control message: resize (prefix byte 0x01)
      if (data.charCodeAt(0) === 1) {
        try {
          const { cols, rows } = JSON.parse(data.slice(1));
          session.pty.resize(cols, rows);
          session.cols = cols;
          session.rows = rows;
        } catch {}
        return;
      }
      session.pty.write(data);
    });

    ws.on('close', () => {
      // Don't kill the PTY — session stays alive for reconnect
      if (session.ws === ws) {
        session.ws = null;
      }
    });

    // If session is already dead, notify client
    if (!session.alive) {
      ws.send('\r\n\x1b[90m[session ended]\x1b[0m\r\n');
      ws.close();
    }
  });
});

// ── Cleanup on exit ──────────────────────────────────────────────────
function cleanup() {
  for (const [, s] of sessions) {
    if (s.alive) try { s.pty.kill(); } catch {}
  }
  process.exit();
}
process.on('SIGINT', cleanup);
process.on('SIGTERM', cleanup);

server.listen(PORT, () => {
  console.log(`floaterm running at http://localhost:${PORT}`);
  const state = loadState();
  if (state && state.boxes && state.boxes.length > 0) {
    console.log(`  Restored layout: ${state.boxes.length} terminal(s)`);
  }
});
