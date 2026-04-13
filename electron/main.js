const { app, BrowserWindow, Menu, shell } = require('electron');
const { spawn } = require('child_process');
const http = require('http');
const path = require('path');
const fs = require('fs');

app.name = 'floaterm';

const PORT = 2323;
let serverProcess;
let win;

function startServer() {
  const serverPath = path.join(__dirname, '..', 'server.js');

  serverProcess = spawn(process.execPath, [serverPath], {
    stdio: ['ignore', 'pipe', 'pipe'],
    env: {
      ...process.env,
      ELECTRON_RUN_AS_NODE: '1',
      PORT: String(PORT),
      SHELL: process.env.SHELL || '/bin/zsh',
      PATH: process.env.PATH || '/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin',
      HOME: process.env.HOME || require('os').homedir(),
    },
  });

  serverProcess.stdout.on('data', (d) => console.log('[server]', d.toString().trim()));
  serverProcess.stderr.on('data', (d) => console.error('[server]', d.toString().trim()));
  serverProcess.on('error', (e) => console.error('[server] spawn error:', e.message));
  serverProcess.on('exit', (code) => console.log('[server] exited with code', code));
}

function createWindow() {
  win = new BrowserWindow({
    width: 1200,
    height: 800,
    minWidth: 600,
    minHeight: 400,
    title: 'floaterm',
    backgroundColor: '#1a1a2e',
    webPreferences: { nodeIntegration: false, contextIsolation: true },
  });

  win.loadURL(`http://localhost:${PORT}`);

  win.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });
}

app.whenReady().then(() => {
  // Clear macOS saved window state (prevents blank window from previous crashes)
  try {
    const savedStatePath = path.join(app.getPath('userData'), '..', '..', 'Saved Application State', 'com.raghuvirsingh.floaterm.savedState');
    fs.rmSync(savedStatePath, { recursive: true, force: true });
  } catch {}

  Menu.setApplicationMenu(Menu.buildFromTemplate([
    {
      label: app.name,
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        { role: 'hide' },
        { role: 'hideOthers' },
        { role: 'unhide' },
        { type: 'separator' },
        { role: 'quit' },
      ],
    },
    { label: 'Edit', submenu: [{ role: 'undo' }, { role: 'redo' }, { type: 'separator' }, { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' }] },
    { label: 'View', submenu: [{ role: 'reload' }, { role: 'toggleDevTools' }, { type: 'separator' }, { role: 'togglefullscreen' }] },
    { label: 'Window', submenu: [{ role: 'minimize' }, { role: 'zoom' }, { role: 'close' }] },
  ]));

  startServer();

  // Poll for server with 127.0.0.1 (not localhost) and timeout
  const startTime = Date.now();
  const check = () => {
    http.get(`http://127.0.0.1:${PORT}`, (res) => {
      res.resume();
      createWindow();
    }).on('error', () => {
      if (Date.now() - startTime > 10000) {
        console.error('Server failed to start within 10s');
        app.quit();
        return;
      }
      setTimeout(check, 200);
    });
  };
  check();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  // On Mac, keep server alive so sessions persist when reopening from dock
  if (process.platform !== 'darwin') {
    if (serverProcess) serverProcess.kill();
    app.quit();
  }
});

app.on('before-quit', () => {
  if (serverProcess) serverProcess.kill();
});
