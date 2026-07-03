import assert from 'node:assert/strict';
import test from 'node:test';

import {
  collectAncestorNodeIds,
  findWidgetTreeMatches,
  getNextMatchIndex,
  getPreviousMatchIndex,
} from './widgetTreeSearch.ts';
import type { WidgetTreeNode } from '../../types/bridgeSession.ts';

const tree: WidgetTreeNode = {
  id: 'material-app',
  label: 'MaterialApp',
  children: [
    {
      id: 'home-column',
      label: 'Column',
      children: [
        {
          id: 'title-text',
          label: 'Text',
          children: [],
        },
        {
          id: 'content-container',
          label: 'Container',
          children: [
            {
              id: 'nested-column',
              label: 'Column',
              children: [],
            },
          ],
        },
      ],
    },
    {
      id: 'footer-row',
      label: 'Row',
      children: [],
    },
  ],
};

test('finds widget matches by label in tree order', () => {
  const matches = findWidgetTreeMatches(tree, 'column');

  assert.deepEqual(matches, [
    {
      nodeId: 'home-column',
      label: 'Column',
      ancestorNodeIds: ['material-app'],
    },
    {
      nodeId: 'nested-column',
      label: 'Column',
      ancestorNodeIds: ['material-app', 'home-column', 'content-container'],
    },
  ]);
});

test('returns no matches for empty or whitespace search queries', () => {
  assert.deepEqual(findWidgetTreeMatches(tree, ''), []);
  assert.deepEqual(findWidgetTreeMatches(tree, '   '), []);
});

test('cycles to the next match index with wraparound', () => {
  assert.equal(getNextMatchIndex({ currentIndex: 0, total: 3 }), 1);
  assert.equal(getNextMatchIndex({ currentIndex: 2, total: 3 }), 0);
  assert.equal(getNextMatchIndex({ currentIndex: -1, total: 3 }), 0);
  assert.equal(getNextMatchIndex({ currentIndex: 0, total: 0 }), -1);
});

test('cycles to the previous match index with wraparound', () => {
  assert.equal(getPreviousMatchIndex({ currentIndex: 2, total: 3 }), 1);
  assert.equal(getPreviousMatchIndex({ currentIndex: 0, total: 3 }), 2);
  assert.equal(getPreviousMatchIndex({ currentIndex: -1, total: 3 }), 2);
  assert.equal(getPreviousMatchIndex({ currentIndex: 0, total: 0 }), -1);
});

test('collects unique ancestors for matched widget ids', () => {
  const matches = findWidgetTreeMatches(tree, 'column');

  assert.deepEqual(collectAncestorNodeIds(matches), [
    'material-app',
    'home-column',
    'content-container',
  ]);
});
