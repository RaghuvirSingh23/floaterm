import { Box } from './box.js';

export class InputHandler {
  constructor(canvasEl, canvas, boxStore, terminalManager, onRender) {
    this.canvasEl = canvasEl;
    this.canvas = canvas;
    this.boxStore = boxStore;
    this.tm = terminalManager;
    this.onRender = onRender;

    this.tool = 'draw'; // 'draw' | 'hand'
    this.mode = 'idle'; // idle | drawing | dragging | resizing | panning
    this.drawStart = null;
    this.drawPreview = null;
    this.dragOffset = null;
    this.dragBox = null;
    this.resizeBox = null;
    this.resizeStart = null;
    this.resizeDir = null;
    this.panStart = null;

    this._bind();
    this._bindToolbar();
  }

  setTool(tool) {
    this.tool = tool;
    document.querySelectorAll('.tool-btn').forEach(btn => btn.classList.remove('active'));
    document.getElementById(`tool-${tool}`).classList.add('active');
    this.canvasEl.classList.toggle('hand-mode', tool === 'hand');
  }

  _bindToolbar() {
    document.getElementById('tool-draw').addEventListener('click', () => this.setTool('draw'));
    document.getElementById('tool-hand').addEventListener('click', () => this.setTool('hand'));

    // Keyboard shortcuts
    window.addEventListener('keydown', (e) => {
      // Don't intercept when typing in a terminal or label
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

    // Terminal container events (drag, resize, focus, close)
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

    // Focus this terminal and bring to front
    this.boxStore.focusBox(boxId);
    document.querySelectorAll('.terminal-box').forEach(el => {
      el.classList.toggle('focused', el === boxEl);
    });
    // Move to end of DOM so it renders on top of siblings
    boxEl.parentElement.appendChild(boxEl);
    if (box.terminal) box.terminal.focus();
    this.onRender();

    // Close button
    if (e.target.classList.contains('close-btn')) {
      this.tm.destroy(box);
      this.boxStore.remove(boxId);
      this.onRender();
      return;
    }

    // Resize handle
    if (e.target.classList.contains('resize-handle')) {
      e.preventDefault();
      this.mode = 'resizing';
      this.resizeBox = box;
      this.resizeDir = e.target.dataset.dir || 'se';
      this.resizeStart = { mx: e.clientX, my: e.clientY, x: box.x, y: box.y, w: box.w, h: box.h };
      return;
    }

    // Label bar drag (but not the editable text itself)
    if (e.target.closest('.label-bar') && !e.target.classList.contains('label-text')) {
      e.preventDefault();
      this.mode = 'dragging';
      this.dragBox = box;
      const screen = this.canvas.worldToScreen(box.x, box.y);
      this.dragOffset = { x: e.clientX - screen.x, y: e.clientY - screen.y };
      return;
    }
  }

  _onCanvasMouseDown(e) {
    // Middle mouse or Alt+left always pans regardless of tool
    if (e.button === 1 || (e.button === 0 && e.altKey)) {
      this.mode = 'panning';
      this.panStart = { x: e.clientX, y: e.clientY };
      this.canvasEl.classList.add('grabbing');
      e.preventDefault();
      return;
    }

    if (e.button === 0) {
      // Unfocus all terminals
      this.boxStore.focusBox(-1);
      document.querySelectorAll('.terminal-box').forEach(el => el.classList.remove('focused'));

      if (this.tool === 'hand') {
        // Hand tool: pan
        this.mode = 'panning';
        this.panStart = { x: e.clientX, y: e.clientY };
        this.canvasEl.classList.add('grabbing');
        e.preventDefault();
      } else {
        // Draw tool: draw a new terminal box
        this.mode = 'drawing';
        this.drawStart = { x: e.clientX, y: e.clientY };
        this.drawPreview = null;
      }
      this.onRender();
    }
  }

  _onMouseMove(e) {
    if (this.mode === 'drawing' && this.drawStart) {
      const x = Math.min(this.drawStart.x, e.clientX);
      const y = Math.min(this.drawStart.y, e.clientY);
      const w = Math.abs(e.clientX - this.drawStart.x);
      const h = Math.abs(e.clientY - this.drawStart.y);
      this.drawPreview = { x, y, w, h };
      this.onRender();
    }

    if (this.mode === 'dragging' && this.dragBox) {
      const world = this.canvas.screenToWorld(
        e.clientX - this.dragOffset.x,
        e.clientY - this.dragOffset.y
      );
      this.dragBox.x = world.x;
      this.dragBox.y = world.y;
      this.tm.updatePosition(this.dragBox, this.canvas);
      this.onRender();
    }

    if (this.mode === 'resizing' && this.resizeBox) {
      const dx = (e.clientX - this.resizeStart.mx) / this.canvas.scale;
      const dy = (e.clientY - this.resizeStart.my) / this.canvas.scale;
      const dir = this.resizeDir;
      const s = this.resizeStart;
      const MIN_W = 300, MIN_H = 200;

      if (dir.includes('e')) {
        this.resizeBox.w = Math.max(MIN_W, s.w + dx);
      }
      if (dir.includes('w')) {
        const newW = Math.max(MIN_W, s.w - dx);
        this.resizeBox.x = s.x + (s.w - newW);
        this.resizeBox.w = newW;
      }
      if (dir.includes('s')) {
        this.resizeBox.h = Math.max(MIN_H, s.h + dy);
      }
      if (dir.includes('n')) {
        const newH = Math.max(MIN_H, s.h - dy);
        this.resizeBox.y = s.y + (s.h - newH);
        this.resizeBox.h = newH;
      }

      this.tm.updatePosition(this.resizeBox, this.canvas);
      if (this.resizeBox._fitAddon) {
        try { this.resizeBox._fitAddon.fit(); } catch {}
      }
      this.onRender();
    }

    if (this.mode === 'panning' && this.panStart) {
      const dx = e.clientX - this.panStart.x;
      const dy = e.clientY - this.panStart.y;
      this.panStart = { x: e.clientX, y: e.clientY };
      this.canvas.pan(dx, dy);
      this.tm.updateAllPositions(this.boxStore.boxes, this.canvas);
    }
  }

  _onMouseUp(e) {
    if (this.mode === 'drawing' && this.drawPreview) {
      const { x, y, w, h } = this.drawPreview;
      // Only spawn if box is big enough
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
      this.onRender();
    }

    if (this.mode === 'resizing' && this.resizeBox) {
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
    this.tm.updateAllPositions(this.boxStore.boxes, this.canvas);
    this.onRender();
  }
}
