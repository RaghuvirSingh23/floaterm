import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import http from 'node:http';
import { WebSocket } from 'ws';

const PORT = 9876 + Math.floor(Math.random() * 100);
let server;

function fetch(path, opts = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({
      hostname: '127.0.0.1', port: PORT,
      path, method: opts.method || 'GET',
      headers: opts.headers || {},
    }, (res) => {
      let body = '';
      res.on('data', (d) => body += d);
      res.on('end', () => resolve({ status: res.statusCode, body, headers: res.headers }));
    });
    req.on('error', reject);
    if (opts.body) req.write(opts.body);
    req.end();
  });
}

function waitForServer() {
  return new Promise((resolve) => {
    const check = () => {
      http.get(`http://127.0.0.1:${PORT}`, () => resolve())
        .on('error', () => setTimeout(check, 50));
    };
    check();
  });
}

before(async () => {
  server = spawn(process.execPath, ['server.js'], {
    cwd: new URL('..', import.meta.url).pathname,
    env: { ...process.env, PORT: String(PORT) },
    stdio: 'pipe',
  });
  server.stderr.on('data', (d) => process.stderr.write(d));
  await waitForServer();
});

after(() => {
  server?.kill();
});

describe('Static file serving', () => {
  it('GET / returns index.html', async () => {
    const res = await fetch('/');
    assert.equal(res.status, 200);
    assert.ok(res.body.includes('<!DOCTYPE html>'));
    assert.equal(res.headers['content-type'], 'text/html');
  });

  it('GET /js/main.js returns JavaScript', async () => {
    const res = await fetch('/js/main.js');
    assert.equal(res.status, 200);
    assert.equal(res.headers['content-type'], 'application/javascript');
  });

  it('GET /css/style.css returns CSS', async () => {
    const res = await fetch('/css/style.css');
    assert.equal(res.status, 200);
    assert.equal(res.headers['content-type'], 'text/css');
  });

  it('GET /manifest.json returns JSON', async () => {
    const res = await fetch('/manifest.json');
    assert.equal(res.status, 200);
    assert.equal(res.headers['content-type'], 'application/json');
    const data = JSON.parse(res.body);
    assert.equal(data.name, 'floaterm');
  });

  it('GET /icon.svg returns SVG', async () => {
    const res = await fetch('/icon.svg');
    assert.equal(res.status, 200);
    assert.equal(res.headers['content-type'], 'image/svg+xml');
  });

  it('GET /nonexistent returns 404', async () => {
    const res = await fetch('/no-such-file');
    assert.equal(res.status, 404);
  });
});

describe('REST API', () => {
  it('GET /api/state returns JSON', async () => {
    const res = await fetch('/api/state');
    assert.equal(res.status, 200);
    JSON.parse(res.body); // should not throw
  });

  it('POST /api/state accepts valid JSON', async () => {
    const payload = JSON.stringify({ canvas: { offsetX: 0, offsetY: 0, scale: 1 }, boxes: [] });
    const res = await fetch('/api/state', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: payload,
    });
    assert.equal(res.status, 200);
  });

  it('POST /api/state rejects invalid JSON', async () => {
    const res = await fetch('/api/state', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{broken',
    });
    assert.equal(res.status, 400);
  });

  it('GET /api/sessions returns array', async () => {
    const res = await fetch('/api/sessions');
    assert.equal(res.status, 200);
    const sessions = JSON.parse(res.body);
    assert.ok(Array.isArray(sessions));
  });

  it('GET /api/ssh-hosts returns array', async () => {
    const res = await fetch('/api/ssh-hosts');
    assert.equal(res.status, 200);
    const hosts = JSON.parse(res.body);
    assert.ok(Array.isArray(hosts));
  });

  it('DELETE /api/session/:id succeeds for unknown id', async () => {
    const res = await fetch('/api/session/nonexistent', { method: 'DELETE' });
    assert.equal(res.status, 200);
  });
});

describe('WebSocket terminal', () => {
  it('connects and receives data from PTY', async () => {
    const ws = new WebSocket(`ws://127.0.0.1:${PORT}/ws/terminal/test-ws?cols=80&rows=24`);
    const data = await new Promise((resolve, reject) => {
      let buf = '';
      ws.on('message', (msg) => {
        buf += msg.toString();
        // Shell prompt usually arrives quickly — resolve after first chunk
        if (buf.length > 0) resolve(buf);
      });
      ws.on('error', reject);
      setTimeout(() => resolve(buf), 3000);
    });
    assert.ok(data.length > 0, 'expected some PTY output');
    ws.close();
    // Clean up the session
    await fetch('/api/session/test-ws', { method: 'DELETE' });
  });

  it('rejects upgrade for invalid path', async () => {
    const ws = new WebSocket(`ws://127.0.0.1:${PORT}/ws/invalid`);
    await new Promise((resolve) => {
      ws.on('error', () => resolve());
      ws.on('close', () => resolve());
    });
  });

  it('handles resize control message', async () => {
    const ws = new WebSocket(`ws://127.0.0.1:${PORT}/ws/terminal/test-resize?cols=80&rows=24`);
    await new Promise((resolve) => ws.on('open', resolve));

    // Send resize message (prefix byte 0x01 + JSON)
    const resizeMsg = '\x01' + JSON.stringify({ cols: 120, rows: 40 });
    ws.send(resizeMsg);

    // If it didn't crash, resize was handled. Wait briefly then verify session is alive.
    await new Promise((r) => setTimeout(r, 200));
    const res = await fetch('/api/sessions');
    const sessions = JSON.parse(res.body);
    assert.ok(sessions.includes('test-resize'), 'session should still be alive after resize');

    ws.close();
    await fetch('/api/session/test-resize', { method: 'DELETE' });
  });
});
