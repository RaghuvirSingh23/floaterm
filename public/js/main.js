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

function render() {
  canvas.render(boxStore.boxes, inputHandler?.drawPreview);
  updateTerminalList();
}

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
  const world = canvas.screenToWorld(cx - w / 2, cy - h / 2);
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
  const world = canvas.screenToWorld(cx - w / 2, cy - h / 2);
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

// Tool items (Claude, Codex, Terminal)
qsMenu.querySelectorAll('.qs-item[data-cmd]').forEach(item => {
  item.addEventListener('click', () => {
    const cmd = item.dataset.cmd;
    const label = item.dataset.label;
    if (cmd === 'claude') spawnWithCommand('claude', 'claude');
    else if (cmd === 'codex') spawnWithCommand('codex', 'codex');
    else if (cmd === 'shell') spawnInCenter();
    qsMenu.classList.add('hidden');
  });
});

// SSH hosts
let sshHostsLoaded = false;
async function loadSshHosts() {
  if (sshHostsLoaded) return;
  try {
    const res = await fetch('/api/ssh-hosts');
    const hosts = await res.json();
    qsSshHosts.innerHTML = '';

    if (hosts.config.length === 0 && hosts.knownHosts.length === 0) {
      qsSshHosts.innerHTML = '<span class="qs-empty">No SSH hosts found</span>';
      sshHostsLoaded = true;
      return;
    }

    // Config hosts first (named, cleaner)
    for (const host of hosts.config) {
      const item = document.createElement('div');
      item.className = 'qs-item';
      item.innerHTML = `<span class="qs-icon">&#8594;</span> ${host}`;
      item.addEventListener('click', () => {
        spawnWithCommand(`ssh:${host}`, `ssh ${host}`);
        qsMenu.classList.add('hidden');
      });
      qsSshHosts.appendChild(item);
    }

    // Known hosts (IPs) — show first 10 with a label separator
    if (hosts.knownHosts.length > 0 && hosts.config.length > 0) {
      const sep = document.createElement('div');
      sep.className = 'qs-section-label';
      sep.textContent = 'Known Hosts';
      sep.style.marginTop = '4px';
      qsSshHosts.appendChild(sep);
    }

    const knownSlice = hosts.knownHosts.slice(0, 15);
    for (const host of knownSlice) {
      const item = document.createElement('div');
      item.className = 'qs-item';
      item.innerHTML = `<span class="qs-icon">&#8594;</span> ${host}`;
      item.addEventListener('click', () => {
        spawnWithCommand(`ssh:${host}`, `ssh ${host}`);
        qsMenu.classList.add('hidden');
      });
      qsSshHosts.appendChild(item);
    }

    if (hosts.knownHosts.length > 15) {
      const more = document.createElement('span');
      more.className = 'qs-empty';
      more.textContent = `+${hosts.knownHosts.length - 15} more`;
      qsSshHosts.appendChild(more);
    }

    sshHostsLoaded = true;
  } catch {
    qsSshHosts.innerHTML = '<span class="qs-empty">Failed to load hosts</span>';
  }
}

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
