let nextId = 1;

export class Box {
  constructor(x, y, w, h) {
    this.id = nextId++;
    this.x = x;
    this.y = y;
    this.w = Math.max(w, 300);
    this.h = Math.max(h, 200);
    this.label = `terminal-${this.id}`;
    this.focused = false;
    this.terminal = null;
    this.ws = null;
    this.domEl = null;
    this._fitAddon = null;
  }
}

export class BoxStore {
  constructor() {
    this.boxes = [];
  }

  add(box) {
    this.boxes.push(box);
    return box;
  }

  remove(id) {
    const idx = this.boxes.findIndex(b => b.id === id);
    if (idx !== -1) return this.boxes.splice(idx, 1)[0];
    return null;
  }

  get(id) {
    return this.boxes.find(b => b.id === id) || null;
  }

  focusBox(id) {
    this.boxes.forEach(b => b.focused = b.id === id);
  }
}
