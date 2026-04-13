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

function saveState() {
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
  }, 300); // debounce 300ms
}

function render() {
  canvas.render(boxStore.boxes, inputHandler?.drawPreview);
}

const inputHandler = new InputHandler(canvasEl, canvas, boxStore, terminalManager, () => {
  render();
  saveState();
});

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
        await terminalManager.spawn(box, canvas);
      }
    }
  } catch (e) {
    console.log('No saved state to restore');
  }
  render();
}

restore();
