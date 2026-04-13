import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { Box, BoxStore, updateNextId } from '../public/js/box.js';

describe('Box', () => {
  it('creates with correct defaults', () => {
    const b = new Box(10, 20, 500, 400);
    assert.equal(b.x, 10);
    assert.equal(b.y, 20);
    assert.equal(b.w, 500);
    assert.equal(b.h, 400);
    assert.match(b.id, /^t\d+$/);
    assert.equal(b.label, `terminal-${b.id}`);
    assert.equal(b.focused, false);
  });

  it('enforces minimum width of 300', () => {
    const b = new Box(0, 0, 100, 400);
    assert.equal(b.w, 300);
  });

  it('enforces minimum height of 200', () => {
    const b = new Box(0, 0, 500, 50);
    assert.equal(b.h, 200);
  });

  it('accepts custom id and label', () => {
    const b = new Box(0, 0, 400, 300, 'custom-1', 'my-term');
    assert.equal(b.id, 'custom-1');
    assert.equal(b.label, 'my-term');
  });

  it('auto-increments id across instances', () => {
    const a = new Box(0, 0, 400, 300);
    const b = new Box(0, 0, 400, 300);
    assert.notEqual(a.id, b.id);
  });

  describe('toJSON / fromJSON', () => {
    it('serializes to plain object', () => {
      const b = new Box(10, 20, 500, 400, 't99', 'hello');
      const json = b.toJSON();
      assert.deepEqual(json, { id: 't99', x: 10, y: 20, w: 500, h: 400, label: 'hello' });
    });

    it('does not include runtime state', () => {
      const b = new Box(0, 0, 400, 300);
      const json = b.toJSON();
      assert.equal(json.terminal, undefined);
      assert.equal(json.ws, undefined);
      assert.equal(json.focused, undefined);
      assert.equal(json.domEl, undefined);
    });

    it('round-trips through JSON', () => {
      const original = new Box(55, 77, 600, 450, 't10', 'ssh:myhost');
      const restored = Box.fromJSON(original.toJSON());
      assert.equal(restored.id, original.id);
      assert.equal(restored.x, original.x);
      assert.equal(restored.y, original.y);
      assert.equal(restored.w, original.w);
      assert.equal(restored.h, original.h);
      assert.equal(restored.label, original.label);
    });
  });
});

describe('BoxStore', () => {
  let store;

  beforeEach(() => {
    store = new BoxStore();
  });

  it('starts empty', () => {
    assert.equal(store.boxes.length, 0);
  });

  it('add() appends and returns the box', () => {
    const b = new Box(0, 0, 400, 300);
    const ret = store.add(b);
    assert.equal(ret, b);
    assert.equal(store.boxes.length, 1);
  });

  it('get() finds by id', () => {
    const b = new Box(0, 0, 400, 300, 'find-me');
    store.add(b);
    assert.equal(store.get('find-me'), b);
  });

  it('get() returns null for unknown id', () => {
    assert.equal(store.get('nope'), null);
  });

  it('remove() splices and returns the box', () => {
    const a = new Box(0, 0, 400, 300, 'a');
    const b = new Box(0, 0, 400, 300, 'b');
    store.add(a);
    store.add(b);
    const removed = store.remove('a');
    assert.equal(removed, a);
    assert.equal(store.boxes.length, 1);
    assert.equal(store.boxes[0], b);
  });

  it('remove() returns null for unknown id', () => {
    assert.equal(store.remove('nope'), null);
  });

  it('focusBox() sets focused on target, clears others', () => {
    const a = new Box(0, 0, 400, 300, 'a');
    const b = new Box(0, 0, 400, 300, 'b');
    store.add(a);
    store.add(b);
    store.focusBox('b');
    assert.equal(a.focused, false);
    assert.equal(b.focused, true);
    store.focusBox('a');
    assert.equal(a.focused, true);
    assert.equal(b.focused, false);
  });
});

describe('updateNextId', () => {
  it('advances nextId past restored ids', () => {
    // After calling updateNextId with t50, new boxes should get t51+
    updateNextId([{ id: 't50' }, { id: 't30' }]);
    const b = new Box(0, 0, 400, 300);
    const num = parseInt(b.id.slice(1));
    assert.ok(num >= 51, `expected id >= t51, got ${b.id}`);
  });

  it('ignores non-matching ids', () => {
    // Should not throw on custom ids
    updateNextId([{ id: 'custom-1' }, { id: 'ssh:host' }]);
  });
});
