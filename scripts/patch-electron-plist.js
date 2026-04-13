// Patches Electron's Info.plist so macOS shows "floaterm" in the menu bar during dev.
const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const plist = path.join(__dirname, '..', 'node_modules', 'electron', 'dist', 'Electron.app', 'Contents', 'Info.plist');
if (!fs.existsSync(plist)) process.exit(0);

execSync(`plutil -replace CFBundleName -string floaterm "${plist}"`);
execSync(`plutil -replace CFBundleDisplayName -string floaterm "${plist}"`);
console.log('Patched Electron plist → floaterm');
