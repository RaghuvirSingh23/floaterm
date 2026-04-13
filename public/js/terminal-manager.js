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

    const resizeHandle = document.createElement('div');
    resizeHandle.className = 'resize-handle';

    el.appendChild(labelBar);
    el.appendChild(termContent);
    el.appendChild(resizeHandle);
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

    fitAddon.fit();
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

    box.ws = ws;

    return { el, term, labelBar, resizeHandle };
  }

  updatePosition(box, canvas) {
    if (!box.domEl) return;
    const screen = canvas.worldToScreen(box.x, box.y);
    const el = box.domEl;
    // Position at screen coords, but keep DOM size at world size (unscaled).
    // Use CSS transform to apply zoom so xterm doesn't re-fit.
    el.style.left = screen.x + 'px';
    el.style.top = screen.y + 'px';
    el.style.width = box.w + 'px';
    el.style.height = box.h + 'px';
    el.style.transformOrigin = '0 0';
    el.style.transform = `scale(${canvas.scale})`;
  }

  updateAllPositions(boxes, canvas) {
    boxes.forEach(box => this.updatePosition(box, canvas));
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
