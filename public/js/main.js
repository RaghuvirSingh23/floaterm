import { Canvas } from './canvas.js';
import { BoxStore } from './box.js';
import { TerminalManager } from './terminal-manager.js';
import { InputHandler } from './input.js';

const canvasEl = document.getElementById('canvas');
const containerEl = document.getElementById('terminal-container');

const canvas = new Canvas(canvasEl);
const boxStore = new BoxStore();
const terminalManager = new TerminalManager(containerEl);

function render() {
  canvas.render(boxStore.boxes, inputHandler?.drawPreview);
}

const inputHandler = new InputHandler(canvasEl, canvas, boxStore, terminalManager, render);

render();
