import assert from 'node:assert/strict';
import test from 'node:test';

import {
  getLocatableWidgetBoundsById,
  getLocatableWidgetIds,
  getSelectedWidgetTarget,
} from './selectionCommentState.ts';
import type { WidgetTreeNode } from '../types/bridgeSession.ts';

test('builds Add comment targets from Widget Context Panel selections without ancestor path', () => {
  const root: WidgetTreeNode = {
    id: 'root',
    label: 'MaterialApp',
    children: [
      {
        id: 'button',
        label: 'PrimaryButton',
        sourceLocation: 'lib/home.dart:12',
        visibleText: 'Save',
        semanticInfo: 'button',
        children: [],
      },
    ],
  };

  assert.deepEqual(getSelectedWidgetTarget(root, 'button'), {
    id: 'button',
    displayLabel: 'PrimaryButton',
    sourceLocation: 'lib/home.dart:12',
    visibleText: 'Save',
    semanticInfo: 'button',
  });
});

test('collects locatable widget ids from the current Widget Tree', () => {
  const root = {
    id: 'root',
    label: 'MaterialApp',
    children: [
      {
        id: 'button',
        label: 'PrimaryButton',
        children: [],
      },
      {
        id: 'column',
        label: 'Column',
        children: [
          {
            id: 'text',
            label: 'Text',
            children: [],
          },
        ],
      },
    ],
  } satisfies WidgetTreeNode;

  assert.deepEqual(
    getLocatableWidgetIds(root),
    new Set(['root', 'button', 'column', 'text']),
  );
});

test('collects only valid widget bounds from the current Widget Tree', () => {
  const root = {
    id: 'root',
    label: 'MaterialApp',
    bounds: {
      x: 0,
      y: 0,
      width: 300,
      height: 600,
    },
    children: [
      {
        id: 'button',
        label: 'PrimaryButton',
        bounds: {
          x: 20,
          y: 40,
          width: 120,
          height: 44,
        },
        children: [],
      },
      {
        id: 'stale',
        label: 'StaleWidget',
        bounds: {
          x: 10,
          y: 10,
          width: 0,
          height: 20,
        },
        children: [],
      },
    ],
  } satisfies WidgetTreeNode;

  assert.deepEqual(
    getLocatableWidgetBoundsById(root),
    new Map([
      [
        'root',
        {
          x: 0,
          y: 0,
          width: 300,
          height: 600,
        },
      ],
      [
        'button',
        {
          x: 20,
          y: 40,
          width: 120,
          height: 44,
        },
      ],
    ]),
  );
});

test('normalizes optional widget context fields before rendering', () => {
  const root = {
    id: 'root',
    label: 'MaterialApp',
    children: [
      {
        id: 'button',
        label: 'PrimaryButton',
        sourceLocation: {
          file: '/Users/drown/flutter_project/app/lib/home.dart',
          line: 12,
        },
        visibleText: ['Save', 'now'],
        semanticInfo: {
          role: 'button',
        },
        children: [],
      },
    ],
  } as unknown as WidgetTreeNode;

  assert.deepEqual(getSelectedWidgetTarget(root, 'button'), {
    id: 'button',
    displayLabel: 'PrimaryButton',
    sourceLocation:
      '{"file":"/Users/drown/flutter_project/app/lib/home.dart","line":12}',
    visibleText: '["Save","now"]',
    semanticInfo: '{"role":"button"}',
  });
});

test('treats missing widget children as an empty child list while searching', () => {
  const root = {
    id: 'root',
    label: 'MaterialApp',
  } as unknown as WidgetTreeNode;

  assert.equal(getSelectedWidgetTarget(root, 'missing'), null);
});
