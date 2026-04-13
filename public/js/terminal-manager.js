export class TerminalManager {
  constructor(containerEl) {
    this.container = containerEl;
    this._loaded = false;
    this.Terminal = null;
    this.WebglAddon = null;
    this.FitAddon = null;
  }

  async loadXterm() {
    if (this._loaded) return;
    const [xtermModule, webglModule, fitModule] = await Promise.all([
      import('https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/+esm'),
      import('https://cdn.jsdelivr.net/npm/@xterm/addon-webgl@0.18.0/+esm'),
      import('https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10.0/+esm'),
    ]);
    this.Terminal = xtermModule.Terminal;
    this.WebglAddon = webglModule.WebglAddon;
    this.FitAddon = fitModule.FitAddon;
    this._loaded = true;
  }

  async spawn(box, canvas) {
    await this.loadXterm();

    // Create DOM element
    const el = document.createElement('div');
    el.className = 'terminal-box';
    el.dataset.boxId = box.id;

    const labelBar = document.createElement('div');
    labelBar.className = 'label-bar';

    const labelText = document.createElement('span');
    labelText.className = 'label-text';
    labelText.contentEditable = 'true';
    labelText.textContent = box.label;

    const closeBtn = document.createElement('span');
    closeBtn.className = 'close-btn';
    closeBtn.textContent = '\u00d7';

    labelBar.appendChild(labelText);
    labelBar.appendChild(closeBtn);

    const termContent = document.createElement('div');
    termContent.className = 'term-content';

    el.appendChild(labelBar);
    el.appendChild(termContent);

    // Resize handles: 4 edges + 4 corners
    const edges = ['n', 's', 'e', 'w', 'ne', 'nw', 'se', 'sw'];
    for (const dir of edges) {
      const handle = document.createElement('div');
      handle.className = `resize-handle rh-${dir}`;
      handle.dataset.dir = dir;
      el.appendChild(handle);
    }
    this.container.appendChild(el);

    box.domEl = el;

    // Label editing
    labelText.addEventListener('blur', () => {
      box.label = labelText.textContent.trim() || box.label;
    });
    labelText.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') { e.preventDefault(); labelText.blur(); }
    });

    // Position the DOM element
    this.updatePosition(box, canvas);

    // Create xterm instance
    const term = new this.Terminal({
      cursorBlink: true,
      fontSize: 14,
      fontFamily: 'Menlo, Monaco, "Courier New", monospace',
      macOptionIsMeta: true,
      theme: {
        background: '#0f0f23',
        foreground: '#e0e0e0',
        cursor: '#22C55E',
        selectionBackground: '#3a3a6a',
      },
      allowProposedApi: true,
    });

    const fitAddon = new this.FitAddon();
    term.loadAddon(fitAddon);
    term.open(termContent);

    try {
      const webglAddon = new this.WebglAddon();
      term.loadAddon(webglAddon);
    } catch (e) {
      console.warn('WebGL addon failed, falling back to canvas renderer');
    }

    // Fit at world-space size (temporarily remove scale so fit calculates correct cols/rows)
    const screen = canvas.worldToScreen(box.x, box.y);
    el.style.transform = `translate(${screen.x}px, ${screen.y}px)`;
    fitAddon.fit();
    el.style.transform = `translate(${screen.x}px, ${screen.y}px) scale(${canvas.scale})`;

    // Fix mouse coords for text selection under transform: scale().
    // xterm maps mouse position using the scaled bounding rect but its cell grid
    // is unscaled, so we adjust event coords to unscaled space.
    // Cache scale on box for mouse adjustment (avoid parsing transform string)
    box._cachedScale = canvas.scale;

    const screenEl = termContent.querySelector('.xterm-screen');
    if (screenEl) {
      const adjustMouse = (e) => {
        const s = box._cachedScale || 1;
        if (s === 1) return;
        const rect = screenEl.getBoundingClientRect();
        const adjX = rect.left + (e.clientX - rect.left) / s;
        const adjY = rect.top + (e.clientY - rect.top) / s;
        Object.defineProperties(e, {
          clientX: { value: adjX },
          clientY: { value: adjY },
        });
      };
      for (const evt of ['mousedown', 'mousemove', 'mouseup']) {
        screenEl.addEventListener(evt, adjustMouse, { capture: true });
      }
    }
    box.terminal = term;
    box._fitAddon = fitAddon;

    // WebSocket connection
    const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const ws = new WebSocket(`${protocol}//${location.host}/ws/terminal/${encodeURIComponent(box.id)}?cols=${term.cols}&rows=${term.rows}`);
    ws.binaryType = 'arraybuffer';

    ws.addEventListener('open', () => {
      term.onData(data => ws.send(data));
      term.onResize(({ cols, rows }) => {
        ws.send(`\x01${JSON.stringify({ cols, rows })}`);
      });
    });

    ws.addEventListener('message', (evt) => {
      if (evt.data instanceof ArrayBuffer) {
        term.write(new Uint8Array(evt.data));
      } else {
        term.write(evt.data);
      }
    });

    ws.addEventListener('close', () => {
      term.write('\r\n\x1b[90m[session ended]\x1b[0m\r\n');
    });

    // Cmd+Backspace: delete to beginning of line (like native macOS).
    // Option+Backspace is handled generically by macOptionIsMeta above.
    term.attachCustomKeyEventHandler((e) => {
      if (e.type !== 'keydown' || e.key !== 'Backspace') return true;
      if (e.metaKey) {
        e.preventDefault();
        if (ws.readyState === WebSocket.OPEN) ws.send('\x15'); // Ctrl+U: kill line
        return false;
      }
      return true;
    });

    box.ws = ws;

    return { el };
  }

  updatePosition(box, canvas) {
    if (!box.domEl) return;
    const screen = canvas.worldToScreen(box.x, box.y);
    const el = box.domEl;
    // Single transform for position + scale — GPU composited, no layout thrashing
    el.style.transform = `translate(${screen.x}px, ${screen.y}px) scale(${canvas.scale})`;
    el.style.width = box.w + 'px';
    el.style.height = box.h + 'px';
    box._cachedScale = canvas.scale;
  }

  updateAllPositions(boxes, canvas) {
    for (let i = 0; i < boxes.length; i++) {
      this.updatePosition(boxes[i], canvas);
    }
  }

  destroy(box) {
    if (box.ws) { box.ws.close(); box.ws = null; }
    if (box.terminal) { box.terminal.dispose(); box.terminal = null; }
    if (box.domEl) { box.domEl.remove(); box.domEl = null; }
    box._fitAddon = null;
    // Kill server-side session
    fetch(`/api/session/${encodeURIComponent(box.id)}`, { method: 'DELETE' }).catch(() => {});
  }
}
