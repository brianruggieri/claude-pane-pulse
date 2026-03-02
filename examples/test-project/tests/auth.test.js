// tests/auth.test.js - Tests for src/auth.js

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { generateToken, isValidToken } = require('../src/auth');

test('generateToken › returns a non-empty string', () => {
  const token = generateToken('user123');
  assert.ok(typeof token === 'string' && token.length > 0);
});

test('generateToken › token passes isValidToken', () => {
  const token = generateToken('alice');
  assert.ok(isValidToken(token));
});

test('isValidToken › rejects empty/null', () => {
  assert.equal(isValidToken(''), false);
  assert.equal(isValidToken(null), false);
  assert.equal(isValidToken(undefined), false);
});

test('isValidToken › rejects malformed tokens', () => {
  assert.equal(isValidToken('no-dashes'), false);
  assert.equal(isValidToken('only-one-dash'), false);
});
