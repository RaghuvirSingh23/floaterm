let _boxes = []; // reference updated by BoxStore

function lowestAvailableId() {
  const used = new Set(_boxes.map(b => {
    const m = String(b.id).match(/^t(\d+)$/);
    return m ? parseInt(m[1]) : null;
  }).filter(n => n !== null));
  let i = 1;
  while (used.has(i)) i++;
  return i;
}

export class Box {
  constructor(x, y, w, h, id = null, label = null) {
    this.id = id || `t${lowestAvailableId()}`;
    this.x = x;
    this.y = y;
    this.w = Math.max(w, 300);
    this.h = Math.max(h, 200);
    this.label = label || `terminal-${this.id}`;
    this.focused = false;
    this.terminal = null;
    this.ws = null;
    this.domEl = null;
    this._fitAddon = null;
  }

  toJSON() {
    return { id: this.id, x: this.x, y: this.y, w: this.w, h: this.h, label: this.label };
  }

  static fromJSON(data) {
    return new Box(data.x, data.y, data.w, data.h, data.id, data.label);
  }
}

// kept for backward compat — no-op now since lowestAvailableId reads live box list
export function updateNextId(boxes) {}

export class BoxStore {
  constructor() {
    this.boxes = [];
    _boxes = this.boxes;
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
