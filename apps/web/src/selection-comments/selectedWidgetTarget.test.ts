import assert from 'node:assert/strict';
import test from 'node:test';

import {
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
