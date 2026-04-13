export class Canvas {
  constructor(canvasEl) {
    this.el = canvasEl;
    this.ctx = canvasEl.getContext('2d');
    this.offsetX = 0;
    this.offsetY = 0;
    this.scale = 1;
    this.gridSize = 40;
    this._cacheCssVars();
    this._resize();
    window.addEventListener('resize', () => this._resize());
  }

  _cacheCssVars() {
    const s = getComputedStyle(document.documentElement);
    this._bgColor = s.getPropertyValue('--canvas-bg').trim() || '#ffffff';
    this._dotColor = s.getPropertyValue('--dot-color').trim() || '#d0d0d0';
    this._previewColor = s.getPropertyValue('--draw-preview').trim() || '#22C55E';
  }

  onThemeChange() {
    this._cacheCssVars();
  }

  _resize() {
    this.el.width = window.innerWidth * devicePixelRatio;
    this.el.height = window.innerHeight * devicePixelRatio;
    this.el.style.width = window.innerWidth + 'px';
    this.el.style.height = window.innerHeight + 'px';
    this.ctx.setTransform(devicePixelRatio, 0, 0, devicePixelRatio, 0, 0);
  }

  screenToWorld(sx, sy) {
    return {
      x: (sx - this.offsetX) / this.scale,
      y: (sy - this.offsetY) / this.scale,
    };
  }

  worldToScreen(wx, wy) {
    return {
      x: wx * this.scale + this.offsetX,
      y: wy * this.scale + this.offsetY,
    };
  }

  pan(dx, dy) {
    this.offsetX += dx;
    this.offsetY += dy;
  }

  zoom(factor, cx, cy) {
    const before = this.screenToWorld(cx, cy);
    this.scale = Math.max(0.05, Math.min(5, this.scale * factor));
    const after = this.screenToWorld(cx, cy);
    this.offsetX += (after.x - before.x) * this.scale;
    this.offsetY += (after.y - before.y) * this.scale;
  }

  render(boxes = [], drawPreview = null) {
    const ctx = this.ctx;
    const w = window.innerWidth;
    const h = window.innerHeight;

    // Background (cached color — no getComputedStyle)
    ctx.fillStyle = this._bgColor;
    ctx.fillRect(0, 0, w, h);

    // Dot grid — use fillRect (1x1) instead of arc for speed
    const gridSize = this.gridSize * this.scale;
    if (gridSize > 8) {
      ctx.fillStyle = this._dotColor;
      const startX = this.offsetX % gridSize;
      const startY = this.offsetY % gridSize;
      for (let x = startX; x < w; x += gridSize) {
        for (let y = startY; y < h; y += gridSize) {
          ctx.fillRect(x - 0.5, y - 0.5, 1, 1);
        }
      }
    }

    // Draw preview rect
    if (drawPreview) {
      const { x, y, w: pw, h: ph } = drawPreview;
      ctx.strokeStyle = this._previewColor;
      ctx.lineWidth = 2;
      ctx.setLineDash([6, 4]);
      ctx.strokeRect(x, y, pw, ph);
      ctx.setLineDash([]);
    }
  }
}
