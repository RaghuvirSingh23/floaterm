import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

// Canvas uses window/devicePixelRatio in constructor — mock minimally
globalThis.window = { innerWidth: 1024, innerHeight: 768, addEventListener: () => {} };
globalThis.devicePixelRatio = 1;

const { Canvas } = await import('../public/js/canvas.js');

function makeCanvas() {
  const el = {
    width: 0, height: 0,
    style: {},
    getContext: () => ({ setTransform: () => {} }),
  };
  return new Canvas(el);
}

describe('Canvas coordinate transforms', () => {
  let c;
  beforeEach(() => { c = makeCanvas(); });

  it('screenToWorld at identity transform', () => {
    const p = c.screenToWorld(100, 200);
    assert.equal(p.x, 100);
    assert.equal(p.y, 200);
  });

  it('screenToWorld with offset', () => {
    c.offsetX = 50;
    c.offsetY = -30;
    const p = c.screenToWorld(150, 70);
    assert.equal(p.x, 100); // (150 - 50) / 1
    assert.equal(p.y, 100); // (70 - (-30)) / 1
  });

  it('screenToWorld with scale', () => {
    c.scale = 2;
    const p = c.screenToWorld(200, 100);
    assert.equal(p.x, 100); // 200 / 2
    assert.equal(p.y, 50);  // 100 / 2
  });

  it('screenToWorld with offset and scale', () => {
    c.offsetX = 40;
    c.offsetY = 20;
    c.scale = 0.5;
    const p = c.screenToWorld(90, 70);
    assert.equal(p.x, 100); // (90 - 40) / 0.5
    assert.equal(p.y, 100); // (70 - 20) / 0.5
  });

  it('worldToScreen at identity', () => {
    const p = c.worldToScreen(100, 200);
    assert.equal(p.x, 100);
    assert.equal(p.y, 200);
  });

  it('worldToScreen with offset and scale', () => {
    c.offsetX = 40;
    c.offsetY = 20;
    c.scale = 0.5;
    const p = c.worldToScreen(100, 100);
    assert.equal(p.x, 90);  // 100 * 0.5 + 40
    assert.equal(p.y, 70);  // 100 * 0.5 + 20
  });

  it('round-trips screenToWorld -> worldToScreen', () => {
    c.offsetX = 123;
    c.offsetY = -456;
    c.scale = 1.7;
    const sx = 500, sy = 300;
    const world = c.screenToWorld(sx, sy);
    const screen = c.worldToScreen(world.x, world.y);
    assert.ok(Math.abs(screen.x - sx) < 1e-10);
    assert.ok(Math.abs(screen.y - sy) < 1e-10);
  });
});

describe('Canvas pan', () => {
  it('accumulates offset', () => {
    const c = makeCanvas();
    c.pan(10, -5);
    assert.equal(c.offsetX, 10);
    assert.equal(c.offsetY, -5);
    c.pan(20, 30);
    assert.equal(c.offsetX, 30);
    assert.equal(c.offsetY, 25);
  });
});

describe('Canvas zoom', () => {
  it('scales by factor', () => {
    const c = makeCanvas();
    c.zoom(2, 0, 0);
    assert.equal(c.scale, 2);
  });

  it('clamps to minimum 0.05', () => {
    const c = makeCanvas();
    c.zoom(0.01, 0, 0);
    assert.equal(c.scale, 0.05);
  });

  it('clamps to maximum 5', () => {
    const c = makeCanvas();
    c.zoom(100, 0, 0);
    assert.equal(c.scale, 5);
  });

  it('preserves world point under cursor', () => {
    const c = makeCanvas();
    c.offsetX = 100;
    c.offsetY = 100;
    const cx = 500, cy = 400;
    const beforeWorld = c.screenToWorld(cx, cy);
    c.zoom(1.5, cx, cy);
    const afterWorld = c.screenToWorld(cx, cy);
    assert.ok(Math.abs(afterWorld.x - beforeWorld.x) < 1e-10);
    assert.ok(Math.abs(afterWorld.y - beforeWorld.y) < 1e-10);
  });
});
