#!/usr/bin/env node
const { execSync, spawn } = require('child_process');
const path = require('path');
const os = require('os');

const PORT = process.env.FLOATERM_PORT || 2323;
const serverPath = path.join(__dirname, '..', 'server.js');

// Start server
const server = spawn(process.execPath, [serverPath], {
  stdio: 'inherit',
  env: { ...process.env, PORT },
});

// Open browser after a short delay
setTimeout(() => {
  const url = `http://localhost:${PORT}`;
  try {
    if (os.platform() === 'darwin') execSync(`open ${url}`);
    else if (os.platform() === 'win32') execSync(`start ${url}`);
    else execSync(`xdg-open ${url}`);
  } catch {}
}, 800);

// Forward signals
process.on('SIGINT', () => { server.kill('SIGINT'); process.exit(); });
process.on('SIGTERM', () => { server.kill('SIGTERM'); process.exit(); });
