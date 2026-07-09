import type { WidgetBounds, WidgetTreeNode } from '../types/bridgeSession.ts';
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

export function getLocatableWidgetBoundsById(
  root: WidgetTreeNode,
): Map<string, WidgetBounds> {
  const boundsById = new Map<string, WidgetBounds>();

  collectLocatableWidgetBounds(root, boundsById);

  return boundsById;
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

function collectLocatableWidgetBounds(
  node: WidgetTreeNode,
  boundsById: Map<string, WidgetBounds>,
) {
  if (isValidWidgetBounds(node.bounds)) {
    boundsById.set(node.id, node.bounds);
  }

  const children = Array.isArray(node.children) ? node.children : [];

  for (const child of children) {
    collectLocatableWidgetBounds(child, boundsById);
  }
}

function isValidWidgetBounds(
  bounds: WidgetTreeNode['bounds'],
): bounds is WidgetBounds {
  return (
    bounds !== undefined &&
    Number.isFinite(bounds.x) &&
    Number.isFinite(bounds.y) &&
    Number.isFinite(bounds.width) &&
    Number.isFinite(bounds.height) &&
    bounds.width > 0 &&
    bounds.height > 0
  );
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
