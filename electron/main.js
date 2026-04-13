const { app, BrowserWindow, Menu, shell } = require('electron');
const { spawn } = require('child_process');
const http = require('http');
const path = require('path');

app.name = 'floaterm';

const PORT = 2323;
let serverProcess;
let win;

function startServer() {
  serverProcess = spawn(process.execPath, [path.join(__dirname, '..', 'server.js')], {
    stdio: 'inherit',
    env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' },
  });
}

function waitForServer(cb) {
  const check = () => {
    http.get(`http://localhost:${PORT}`, () => cb())
      .on('error', () => setTimeout(check, 100));
  };
  check();
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

  // Open external links in browser
  win.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });
}

app.whenReady().then(() => {
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
  waitForServer(createWindow);

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (serverProcess) serverProcess.kill();
  if (process.platform !== 'darwin') app.quit();
});

app.on('before-quit', () => {
  if (serverProcess) serverProcess.kill();
});
