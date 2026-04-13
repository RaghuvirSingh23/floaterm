export class Canvas {
  constructor(canvasEl) {
    this.el = canvasEl;
    this.ctx = canvasEl.getContext('2d');
    this.offsetX = 0;
    this.offsetY = 0;
    this.scale = 1;
    this.gridSize = 40;
    this._resize();
    window.addEventListener('resize', () => this._resize());
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
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, w, h);

    // Draw dot grid
    ctx.fillStyle = '#d0d0d0';
    const gridSize = this.gridSize * this.scale;
    if (gridSize > 8) {
      const startX = this.offsetX % gridSize;
      const startY = this.offsetY % gridSize;
      for (let x = startX; x < w; x += gridSize) {
        for (let y = startY; y < h; y += gridSize) {
          ctx.beginPath();
          ctx.arc(x, y, 1, 0, Math.PI * 2);
          ctx.fill();
        }
      }
    }

    // Draw preview rect while drawing
    if (drawPreview) {
      const { x, y, w: pw, h: ph } = drawPreview;
      ctx.strokeStyle = '#22C55E';
      ctx.lineWidth = 2;
      ctx.setLineDash([6, 4]);
      ctx.strokeRect(x, y, pw, ph);
      ctx.setLineDash([]);
    }
  }
}
