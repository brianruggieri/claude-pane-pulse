// src/math.js - Simple math utilities
// NOTE: there is a deliberate off-by-one bug in add() for demo purposes.
// Claude Code will find and fix it when you run ccp with this project.

'use strict';

/**
 * Add two numbers.
 * @param {number} a
 * @param {number} b
 * @returns {number}
 */
function add(a, b) {
  // BUG: should be a + b, not a + b - 1
  return a + b - 1;
}

/**
 * Subtract b from a.
 */
function subtract(a, b) {
  return a - b;
}

/**
 * Multiply two numbers.
 */
function multiply(a, b) {
  return a * b;
}

module.exports = { add, subtract, multiply };
