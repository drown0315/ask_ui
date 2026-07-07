import type { WidgetTreeNode } from '../types/bridgeSession.ts';
import type { SelectedWidgetTarget } from './selectionCommentTypes.ts';

export function getSelectedWidgetTarget(
  root: WidgetTreeNode,
  selectedWidgetId: string | null,
): SelectedWidgetTarget | null {
  if (selectedWidgetId === null) {
    return null;
  }

  const node = findWidgetTreeNode(root, selectedWidgetId);

  if (node === null) {
    return null;
  }

  return {
    id: stringifyWidgetContextValue(node.id) ?? '',
    displayLabel: stringifyWidgetContextValue(node.label) ?? '',
    sourceLocation: stringifyWidgetContextValue(node.sourceLocation),
    visibleText: stringifyWidgetContextValue(node.visibleText),
    semanticInfo: stringifyWidgetContextValue(node.semanticInfo),
  };
}

export function getLocatableWidgetIds(root: WidgetTreeNode): Set<string> {
  const locatableWidgetIds = new Set<string>();

  collectLocatableWidgetIds(root, locatableWidgetIds);

  return locatableWidgetIds;
}

function collectLocatableWidgetIds(
  node: WidgetTreeNode,
  locatableWidgetIds: Set<string>,
) {
  locatableWidgetIds.add(node.id);

  const children = Array.isArray(node.children) ? node.children : [];

  for (const child of children) {
    collectLocatableWidgetIds(child, locatableWidgetIds);
  }
}

function stringifyWidgetContextValue(value: unknown): string | undefined {
  if (value === null || value === undefined) {
    return undefined;
  }

  if (typeof value === 'string') {
    return value;
  }

  if (
    typeof value === 'number' ||
    typeof value === 'boolean' ||
    typeof value === 'bigint'
  ) {
    return String(value);
  }

  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function findWidgetTreeNode(
  node: WidgetTreeNode,
  selectedWidgetId: string,
): WidgetTreeNode | null {
  if (node.id === selectedWidgetId) {
    return node;
  }

  const children = Array.isArray(node.children) ? node.children : [];

  for (const child of children) {
    const found = findWidgetTreeNode(child, selectedWidgetId);

    if (found !== null) {
      return found;
    }
  }

  return null;
}
