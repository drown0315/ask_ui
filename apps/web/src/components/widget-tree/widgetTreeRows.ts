import type { WidgetTreeNode } from '../../types/bridgeSession';

export type WidgetTreeRow = {
  id: string;
  depth: number;
  node: WidgetTreeNode;
  hasChildren: boolean;
};

export function collectExpandableNodeIds(root: WidgetTreeNode): string[] {
  const ids: string[] = [];

  visitWidgetTree(root, (node) => {
    if (node.children.length > 0) {
      ids.push(node.id);
    }
  });

  return ids;
}

export function buildVisibleWidgetTreeRows({
  root,
  expandedNodeIds,
}: {
  root: WidgetTreeNode;
  expandedNodeIds: ReadonlySet<string>;
}): WidgetTreeRow[] {
  const rows: WidgetTreeRow[] = [];

  appendRows({
    node: root,
    depth: 0,
    expandedNodeIds,
    rows,
  });

  return rows;
}

function appendRows({
  node,
  depth,
  expandedNodeIds,
  rows,
}: {
  node: WidgetTreeNode;
  depth: number;
  expandedNodeIds: ReadonlySet<string>;
  rows: WidgetTreeRow[];
}) {
  const hasChildren = node.children.length > 0;

  rows.push({
    id: node.id,
    depth,
    node,
    hasChildren,
  });

  if (!hasChildren || !expandedNodeIds.has(node.id)) {
    return;
  }

  const childDepth = node.children.length === 1 ? depth : depth + 1;

  for (const child of node.children) {
    appendRows({
      node: child,
      depth: childDepth,
      expandedNodeIds,
      rows,
    });
  }
}

function visitWidgetTree(
  node: WidgetTreeNode,
  visit: (node: WidgetTreeNode) => void,
) {
  visit(node);

  for (const child of node.children) {
    visitWidgetTree(child, visit);
  }
}
