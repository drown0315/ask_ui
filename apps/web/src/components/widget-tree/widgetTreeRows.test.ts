import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildVisibleWidgetTreeRows,
  collectExpandableNodeIds,
} from './widgetTreeRows.ts';
import type { WidgetTreeNode } from '../../types/bridgeSession.ts';

const tree: WidgetTreeNode = {
  id: 'root',
  label: 'MaterialApp',
  children: [
    {
      id: 'padding',
      label: 'Padding',
      children: [
        {
          id: 'center',
          label: 'Center',
          children: [
            {
              id: 'column',
              label: 'Column',
              children: [
                {
                  id: 'text',
                  label: 'Text',
                  children: [],
                },
                {
                  id: 'button',
                  label: 'ElevatedButton',
                  children: [],
                },
              ],
            },
          ],
        },
      ],
    },
  ],
};

test('collects every expandable node id from the original nested tree', () => {
  assert.deepEqual(collectExpandableNodeIds(tree), [
    'root',
    'padding',
    'center',
    'column',
  ]);
});

test('keeps single-child descendants at the same visual depth', () => {
  const rows = buildVisibleWidgetTreeRows({
    root: tree,
    expandedNodeIds: new Set(['root', 'padding', 'center', 'column']),
  });

  assert.deepEqual(
    rows.map((row) => ({
      depth: row.depth,
      label: row.node.label,
      hasChildren: row.hasChildren,
    })),
    [
      {
        depth: 0,
        label: 'MaterialApp',
        hasChildren: true,
      },
      {
        depth: 0,
        label: 'Padding',
        hasChildren: true,
      },
      {
        depth: 0,
        label: 'Center',
        hasChildren: true,
      },
      {
        depth: 0,
        label: 'Column',
        hasChildren: true,
      },
      {
        depth: 1,
        label: 'Text',
        hasChildren: false,
      },
      {
        depth: 1,
        label: 'ElevatedButton',
        hasChildren: false,
      },
    ],
  );
});

test('hides descendants when a single-child ancestor is collapsed', () => {
  const rows = buildVisibleWidgetTreeRows({
    root: tree,
    expandedNodeIds: new Set(['root']),
  });

  assert.deepEqual(
    rows.map((row) => ({
      depth: row.depth,
      label: row.node.label,
    })),
    [
      {
        depth: 0,
        label: 'MaterialApp',
      },
      {
        depth: 0,
        label: 'Padding',
      },
    ],
  );
});
