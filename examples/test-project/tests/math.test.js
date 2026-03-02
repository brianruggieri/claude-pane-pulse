// tests/math.test.js - Tests for src/math.js
// Uses Node.js built-in test runner (node --test), no npm deps needed.

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { add, subtract, multiply } = require('../src/math');

test('add › returns correct sum', () => {
  assert.equal(add(2, 3), 5);   // FAILS until bug is fixed: returns 4
  assert.equal(add(0, 0), 0);
  assert.equal(add(-1, 1), 0);
});

test('subtract › returns correct difference', () => {
  assert.equal(subtract(5, 3), 2);
  assert.equal(subtract(0, 0), 0);
});

test('multiply › returns correct product', () => {
  assert.equal(multiply(3, 4), 12);
  assert.equal(multiply(0, 99), 0);
});
