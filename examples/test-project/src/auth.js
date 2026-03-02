// src/auth.js - Simple auth token utilities

'use strict';

/**
 * Generate a simple session token.
 * @param {string} userId
 * @returns {string}
 */
function generateToken(userId) {
  const timestamp = Date.now().toString(36);
  const random = Math.random().toString(36).slice(2, 8);
  return `${userId}-${timestamp}-${random}`;
}

/**
 * Check if a token looks valid (non-empty, correct format).
 * @param {string} token
 * @returns {boolean}
 */
function isValidToken(token) {
  if (!token || typeof token !== 'string') return false;
  const parts = token.split('-');
  return parts.length === 3 && parts.every(p => p.length > 0);
}

module.exports = { generateToken, isValidToken };
