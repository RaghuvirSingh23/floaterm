import { Box } from './box.js';

export class InputHandler {
  constructor(canvasEl, canvas, boxStore, terminalManager, onRender) {
    this.canvasEl = canvasEl;
    this.canvas = canvas;
    this.boxStore = boxStore;
    this.tm = terminalManager;
    this._onRender = onRender;

    this.tool = 'draw';
    this.mode = 'idle';
    this.drawStart = null;
    this.drawPreview = null;
    this.dragOffset = null;
    this.dragBox = null;
    this.resizeBox = null;
    this.resizeStart = null;
    this.resizeDir = null;
    this.panStart = null;

    // RAF batching — coalesce all renders to next animation frame
    this._rafPending = false;

    // Cached DOM references
    this._toolBtns = null;

    this._bind();
    this._bindToolbar();
  }

  _scheduleRender() {
    if (this._rafPending) return;
    this._rafPending = true;
    requestAnimationFrame(() => {
      this._rafPending = false;
      this._onRender();
    });
  }

  setTool(tool) {
    this.tool = tool;
    if (!this._toolBtns) {
      this._toolBtns = Array.from(document.querySelectorAll('.tool-btn'));
    }
    this._toolBtns.forEach(btn => btn.classList.remove('active'));
    document.getElementById(`tool-${tool}`)?.classList.add('active');
    this.canvasEl.classList.toggle('hand-mode', tool === 'hand');
  }

  _bindToolbar() {
    document.getElementById('tool-draw').addEventListener('click', () => this.setTool('draw'));
    document.getElementById('tool-hand').addEventListener('click', () => this.setTool('hand'));

    window.addEventListener('keydown', (e) => {
      if (e.target.closest('.term-content') || e.target.closest('.label-text') ||
          e.target.closest('.xterm')) return;
      if (e.key === 'd' || e.key === 'D') this.setTool('draw');
      if (e.key === 'h' || e.key === 'H') this.setTool('hand');
    });
  }

  _bind() {
    const el = this.canvasEl;
    el.addEventListener('mousedown', (e) => this._onCanvasMouseDown(e));
    window.addEventListener('mousemove', (e) => this._onMouseMove(e));
    window.addEventListener('mouseup', (e) => this._onMouseUp(e));
    el.addEventListener('wheel', (e) => this._onWheel(e), { passive: false });

    document.getElementById('terminal-container').addEventListener('mousedown', (e) => {
      this._onTerminalContainerMouseDown(e);
    });
  }

  _onTerminalContainerMouseDown(e) {
    const boxEl = e.target.closest('.terminal-box');
    if (!boxEl) return;

    const boxId = boxEl.dataset.boxId;
    const box = this.boxStore.get(boxId);
    if (!box) return;

    // Focus + bring to front
    this.boxStore.focusBox(boxId);
    document.querySelectorAll('.terminal-box').forEach(el => {
      el.classList.toggle('focused', el === boxEl);
    });
    boxEl.parentElement.appendChild(boxEl);
    if (box.terminal) box.terminal.focus();
    this._onRender();

    if (e.target.classList.contains('close-btn')) {
      this.tm.destroy(box);
      this.boxStore.remove(boxId);
      this._onRender();
      return;
    }

    if (e.target.classList.contains('resize-handle')) {
      e.preventDefault();
      this.mode = 'resizing';
      this.resizeBox = box;
      this.resizeDir = e.target.dataset.dir || 'se';
      const mouseWorld = this.canvas.screenToWorld(e.clientX, e.clientY);
      this.resizeStart = { wx: mouseWorld.x, wy: mouseWorld.y, x: box.x, y: box.y, w: box.w, h: box.h };
      return;
    }

    if (e.target.closest('.label-bar') && !e.target.classList.contains('label-text')) {
      e.preventDefault();
      this.mode = 'dragging';
      this.dragBox = box;
      this._dragLogCount = 0;
      const mouseWorld = this.canvas.screenToWorld(e.clientX, e.clientY);
      this.dragOffset = { x: mouseWorld.x - box.x, y: mouseWorld.y - box.y };
      console.log(`[drag START] mouse=(${e.clientX},${e.clientY}) mouseWorld=(${mouseWorld.x.toFixed(1)},${mouseWorld.y.toFixed(1)}) box=(${box.x.toFixed(1)},${box.y.toFixed(1)}) offset=(${this.dragOffset.x.toFixed(1)},${this.dragOffset.y.toFixed(1)}) scale=${this.canvas.scale}`);
      return;
    }
  }

  _onCanvasMouseDown(e) {
    if (e.button === 1 || (e.button === 0 && e.altKey)) {
      this.mode = 'panning';
      this.panStart = { x: e.clientX, y: e.clientY };
      this.canvasEl.classList.add('grabbing');
      e.preventDefault();
      return;
    }

    if (e.button === 0) {
      this.boxStore.focusBox(-1);
      document.querySelectorAll('.terminal-box').forEach(el => el.classList.remove('focused'));

      if (this.tool === 'hand') {
        this.mode = 'panning';
        this.panStart = { x: e.clientX, y: e.clientY };
        this.canvasEl.classList.add('grabbing');
        e.preventDefault();
      } else {
        this.mode = 'drawing';
        this.drawStart = { x: e.clientX, y: e.clientY };
        this.drawPreview = null;
      }
      this._onRender();
    }
  }

  _onMouseMove(e) {
    if (this.mode === 'idle') return; // early exit — most common case

    if (this.mode === 'drawing' && this.drawStart) {
      const x = Math.min(this.drawStart.x, e.clientX);
      const y = Math.min(this.drawStart.y, e.clientY);
      const w = Math.abs(e.clientX - this.drawStart.x);
      const h = Math.abs(e.clientY - this.drawStart.y);
      this.drawPreview = { x, y, w, h };
      this._onRender();
      return;
    }

    if (this.mode === 'dragging' && this.dragBox) {
      const mouseWorld = this.canvas.screenToWorld(e.clientX, e.clientY);
      this.dragBox.x = mouseWorld.x - this.dragOffset.x;
      this.dragBox.y = mouseWorld.y - this.dragOffset.y;
      this.tm.updatePosition(this.dragBox);
      // NO canvas redraw during drag — grid doesn't move, only the box does
      return;
    }

    if (this.mode === 'resizing' && this.resizeBox) {
      const mouseWorld = this.canvas.screenToWorld(e.clientX, e.clientY);
      const dx = mouseWorld.x - this.resizeStart.wx;
      const dy = mouseWorld.y - this.resizeStart.wy;
      const dir = this.resizeDir;
      const s = this.resizeStart;
      const MIN_W = 300, MIN_H = 200;

      if (dir.includes('e')) this.resizeBox.w = Math.max(MIN_W, s.w + dx);
      if (dir.includes('w')) {
        const newW = Math.max(MIN_W, s.w - dx);
        this.resizeBox.x = s.x + (s.w - newW);
        this.resizeBox.w = newW;
      }
      if (dir.includes('s')) this.resizeBox.h = Math.max(MIN_H, s.h + dy);
      if (dir.includes('n')) {
        const newH = Math.max(MIN_H, s.h - dy);
        this.resizeBox.y = s.y + (s.h - newH);
        this.resizeBox.h = newH;
      }

      this.tm.updatePosition(this.resizeBox);
      // NO canvas redraw during resize — only the box changes
      return;
    }

    if (this.mode === 'panning' && this.panStart) {
      const dx = e.clientX - this.panStart.x;
      const dy = e.clientY - this.panStart.y;
      this.panStart.x = e.clientX;
      this.panStart.y = e.clientY;
      this.canvas.pan(dx, dy);
      this.tm.updateCamera(this.canvas); // instant — 1 DOM write
      // Defer canvas redraw to RAF (grid dots are expensive)
      if (!this._panRafPending) {
        this._panRafPending = true;
        requestAnimationFrame(() => {
          this._panRafPending = false;
          this._onRender();
        });
      }
    }
  }

  _onMouseUp(e) {
    if (this.mode === 'drawing' && this.drawPreview) {
      const { x, y, w, h } = this.drawPreview;
      if (w > 50 && h > 50) {
        const worldTL = this.canvas.screenToWorld(x, y);
        const worldBR = this.canvas.screenToWorld(x + w, y + h);
        const box = new Box(
          worldTL.x, worldTL.y,
          worldBR.x - worldTL.x,
          worldBR.y - worldTL.y
        );
        this.boxStore.add(box);
        this.boxStore.focusBox(box.id);
        this.tm.spawn(box, this.canvas).then(({ el }) => {
          el.classList.add('focused');
          if (box.terminal) box.terminal.focus();
        });
      }
      this.drawPreview = null;
      this._onRender();
    }

    if (this.mode === 'resizing' && this.resizeBox) {
      // Fit terminal on mouseup (reflow cols/rows to new size)
      if (this.resizeBox._fitAddon) {
        try { this.resizeBox._fitAddon.fit(); } catch {}
      }
    }

    if (this.mode === 'panning') {
      this.canvasEl.classList.remove('grabbing');
    }

    this.mode = 'idle';
    this.dragBox = null;
    this.resizeBox = null;
  }

  _onWheel(e) {
    e.preventDefault();
    if (e.ctrlKey || e.metaKey) {
      const factor = e.deltaY > 0 ? 0.97 : 1.03;
      this.canvas.zoom(factor, e.clientX, e.clientY);
    } else {
      this.canvas.pan(-e.deltaX, -e.deltaY);
    }
    this.tm.updateCamera(this.canvas); // instant
    // Defer expensive canvas redraw
    if (!this._wheelRafPending) {
      this._wheelRafPending = true;
      requestAnimationFrame(() => {
        this._wheelRafPending = false;
        this._onRender();
      });
    }
  }
}
