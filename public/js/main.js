import { Canvas } from './canvas.js';
import { Box, BoxStore, updateNextId } from './box.js';
import { TerminalManager } from './terminal-manager.js';
import { InputHandler } from './input.js';

const canvasEl = document.getElementById('canvas');
const containerEl = document.getElementById('terminal-container');

const canvas = new Canvas(canvasEl);
const boxStore = new BoxStore();
const terminalManager = new TerminalManager(containerEl);

// ── State persistence ────────────────────────────────────────────────
let saveTimeout = null;
let saveEnabled = false; // only enable after restore is fully complete

function saveState() {
  if (!saveEnabled) return;
  clearTimeout(saveTimeout);
  saveTimeout = setTimeout(() => {
    const state = {
      canvas: { offsetX: canvas.offsetX, offsetY: canvas.offsetY, scale: canvas.scale },
      boxes: boxStore.boxes.map(b => b.toJSON()),
    };
    fetch('/api/state', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(state),
    }).catch(() => {});
  }, 500);
}

const zoomIndicator = document.getElementById('zoom-indicator');

function render() {
  canvas.render(boxStore.boxes, inputHandler?.drawPreview);
  updateTerminalList();
  zoomIndicator.textContent = Math.round(canvas.scale * 100) + '%';
}

document.getElementById('zoom-reset').addEventListener('click', () => {
  canvas.scale = 1;
  canvas.offsetX = 0;
  canvas.offsetY = 0;
  terminalManager.updateAllPositions(boxStore.boxes, canvas);
  render();
  saveState();
});

// ── Theme toggle ────────────────────────────────────────────────────
const themeToggle = document.getElementById('theme-toggle');
const sunIcon = document.getElementById('theme-icon-sun');
const moonIcon = document.getElementById('theme-icon-moon');

function setThemeUI(dark) {
  document.documentElement.classList.toggle('dark', dark);
  sunIcon.style.display = dark ? 'block' : 'none';
  moonIcon.style.display = dark ? 'none' : 'block';
}

// Init from localStorage or system preference
const stored = localStorage.getItem('floaterm-theme');
if (stored === 'dark' || (!stored && window.matchMedia('(prefers-color-scheme: dark)').matches)) {
  setThemeUI(true);
}

themeToggle.addEventListener('click', (e) => {
  e.stopPropagation();
  const isDark = !document.documentElement.classList.contains('dark');
  localStorage.setItem('floaterm-theme', isDark ? 'dark' : 'light');
  setThemeUI(isDark);
  render(); // repaint canvas dots with new theme colors
});

const inputHandler = new InputHandler(canvasEl, canvas, boxStore, terminalManager, () => {
  render();
  saveState();
});

window.addEventListener('resize', () => render());

// ── Spawn terminal in center of screen ──────────────────────────────
function spawnInCenter() {
  const cx = window.innerWidth / 2;
  const cy = window.innerHeight / 2;
  const w = 500;
  const h = 350;
  const offset = boxStore.boxes.length * 30;
  const world = canvas.screenToWorld(cx - w / 2 + offset, cy - h / 2 + offset);
  const box = new Box(world.x, world.y, w / canvas.scale, h / canvas.scale);
  boxStore.add(box);
  boxStore.focusBox(box.id);
  terminalManager.spawn(box, canvas).then(({ el }) => {
    el.classList.add('focused');
    document.querySelectorAll('.terminal-box').forEach(e => {
      if (e !== el) e.classList.remove('focused');
    });
    if (box.terminal) box.terminal.focus();
  });
  render();
  saveState();
}

document.getElementById('tool-spawn').addEventListener('click', spawnInCenter);

// ── Quick spawn (green button) ──────────────────────────────────────
function spawnWithCommand(label, cmd) {
  // Deduplicate label if one with the same name exists
  const existing = boxStore.boxes.filter(b => b.label === label || b.label.match(new RegExp(`^${label}-\\d+$`)));
  const finalLabel = existing.length > 0 ? `${label}-${existing.length + 1}` : label;

  const cx = window.innerWidth / 2;
  const cy = window.innerHeight / 2;
  const w = 600;
  const h = 420;
  const offset = boxStore.boxes.length * 30;
  const world = canvas.screenToWorld(cx - w / 2 + offset, cy - h / 2 + offset);
  const box = new Box(world.x, world.y, w / canvas.scale, h / canvas.scale, null, finalLabel);
  boxStore.add(box);
  boxStore.focusBox(box.id);
  terminalManager.spawn(box, canvas).then(({ el }) => {
    el.classList.add('focused');
    document.querySelectorAll('.terminal-box').forEach(e => {
      if (e !== el) e.classList.remove('focused');
    });
    // Send the command after shell is ready
    if (cmd) {
      setTimeout(() => {
        if (box.ws && box.ws.readyState === WebSocket.OPEN) {
          box.ws.send(cmd + '\r');
        } else if (box.ws) {
          box.ws.addEventListener('open', () => box.ws.send(cmd + '\r'), { once: true });
        }
      }, 300);
    }
    if (box.terminal) box.terminal.focus();
  });
  render();
  saveState();
}

const qsBtn = document.getElementById('quick-spawn-btn');
const qsMenu = document.getElementById('quick-spawn-menu');
const qsSshHosts = document.getElementById('qs-ssh-hosts');

qsBtn.addEventListener('click', (e) => {
  e.stopPropagation();
  qsMenu.classList.toggle('hidden');
  if (!qsMenu.classList.contains('hidden')) loadSshHosts();
});

document.addEventListener('click', (e) => {
  if (!e.target.closest('#quick-spawn-wrapper')) qsMenu.classList.add('hidden');
});

// SSH hosts
let sshHostsLoaded = false;

function addHostItem(host, container) {
  const item = document.createElement('div');
  item.className = 'qs-item';
  item.innerHTML = `<span class="qs-icon">&#8594;</span> ${host}`;
  item.addEventListener('click', () => {
    spawnWithCommand(`ssh:${host}`, `ssh ${host}`);
    qsMenu.classList.add('hidden');
  });
  container.appendChild(item);
}

async function loadSshHosts() {
  if (sshHostsLoaded) return;
  try {
    const res = await fetch('/api/ssh-hosts');
    const hosts = await res.json();
    qsSshHosts.innerHTML = '';

    if (hosts.length === 0) {
      qsSshHosts.innerHTML = '<span class="qs-empty">No SSH hosts found</span>';
    } else {
      hosts.forEach(h => addHostItem(h, qsSshHosts));
    }
    sshHostsLoaded = true;
  } catch {
    qsSshHosts.innerHTML = '<span class="qs-empty">Failed to load hosts</span>';
  }
}

document.getElementById('qs-claude').addEventListener('click', () => {
  spawnWithCommand('claude', 'claude');
  qsMenu.classList.add('hidden');
});
document.getElementById('qs-codex').addEventListener('click', () => {
  spawnWithCommand('codex', 'codex');
  qsMenu.classList.add('hidden');
});

document.getElementById('qs-add-host').addEventListener('click', (e) => {
  e.stopPropagation();
  const host = prompt('Enter SSH host (e.g. user@hostname or IP):');
  if (host && host.trim()) {
    spawnWithCommand(`ssh:${host.trim()}`, `ssh ${host.trim()}`);
    qsMenu.classList.add('hidden');
  }
});

// ── Terminal list dropdown ───────────────────────────────────────────
const listToggle = document.getElementById('terminal-list-toggle');
const listPanel = document.getElementById('terminal-list');
const listItems = document.getElementById('terminal-list-items');
const countBadge = document.getElementById('terminal-count');

listToggle.addEventListener('click', (e) => {
  e.stopPropagation();
  listPanel.classList.toggle('hidden');
  if (!listPanel.classList.contains('hidden')) updateTerminalList();
});

// Close dropdown when clicking outside
document.addEventListener('click', (e) => {
  if (!e.target.closest('#terminal-list-wrapper')) {
    listPanel.classList.add('hidden');
  }
});

function updateTerminalList() {
  countBadge.textContent = boxStore.boxes.length;

  if (listPanel.classList.contains('hidden')) return;

  listItems.innerHTML = '';
  for (const box of boxStore.boxes) {
    const item = document.createElement('div');
    item.className = 'tl-item' + (box.focused ? ' active' : '');

    const dot = document.createElement('span');
    dot.className = 'tl-dot';

    const label = document.createElement('span');
    label.className = 'tl-label';
    label.textContent = box.label;

    const rename = document.createElement('span');
    rename.className = 'tl-rename';
    rename.textContent = '\u270e';
    rename.title = 'Rename';
    rename.addEventListener('click', (e) => {
      e.stopPropagation();
      label.contentEditable = 'true';
      label.spellcheck = false;
      label.focus();
      // Select all text
      const range = document.createRange();
      range.selectNodeContents(label);
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);

      const finish = () => {
        label.contentEditable = 'false';
        const newLabel = label.textContent.trim();
        if (newLabel) {
          box.label = newLabel;
          if (box.domEl) {
            const labelEl = box.domEl.querySelector('.label-text');
            if (labelEl) labelEl.textContent = newLabel;
          }
          saveState();
        } else {
          label.textContent = box.label;
        }
        label.removeEventListener('blur', finish);
      };
      label.addEventListener('blur', finish);
      label.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') { e.preventDefault(); label.blur(); }
        if (e.key === 'Escape') { label.textContent = box.label; label.blur(); }
      });
    });

    const close = document.createElement('span');
    close.className = 'tl-close';
    close.textContent = '\u00d7';
    close.addEventListener('click', (e) => {
      e.stopPropagation();
      terminalManager.destroy(box);
      boxStore.remove(box.id);
      render();
      saveState();
    });

    item.appendChild(dot);
    item.appendChild(label);
    item.appendChild(rename);
    item.appendChild(close);

    item.addEventListener('click', () => {
      // Focus this terminal and bring to front
      boxStore.focusBox(box.id);
      document.querySelectorAll('.terminal-box').forEach(el => {
        el.classList.toggle('focused', el.dataset.boxId === String(box.id));
      });
      if (box.domEl) {
        box.domEl.parentElement.appendChild(box.domEl);
      }
      if (box.terminal) box.terminal.focus();
      render();
      listPanel.classList.add('hidden');
    });

    listItems.appendChild(item);
  }

  if (boxStore.boxes.length === 0) {
    const empty = document.createElement('div');
    empty.style.cssText = 'padding: 12px; text-align: center; color: #999; font: 12px -apple-system, sans-serif;';
    empty.textContent = 'No terminals open';
    listItems.appendChild(empty);
  }
}

// ── Restore state on load ────────────────────────────────────────────
async function restore() {
  try {
    const res = await fetch('/api/state');
    const state = await res.json();

    if (state.canvas) {
      canvas.offsetX = state.canvas.offsetX || 0;
      canvas.offsetY = state.canvas.offsetY || 0;
      canvas.scale = state.canvas.scale || 1;
    }

    if (state.boxes && state.boxes.length > 0) {
      const boxes = state.boxes.map(data => Box.fromJSON(data));
      updateNextId(boxes);

      for (const box of boxes) {
        boxStore.add(box);
        console.log(`[floaterm] restoring box ${box.id} (${box.label}), total: ${boxStore.boxes.length}`);
        await terminalManager.spawn(box, canvas);
      }
    }
  } catch (e) {
    console.log('No saved state to restore', e);
  }
  render();
  // Enable saving after a delay to ensure all async xterm/ws work has settled
  setTimeout(() => { saveEnabled = true; }, 2000);
}

restore();
