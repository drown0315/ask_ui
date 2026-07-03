import type { WidgetTreeNode } from '../../types/bridgeSession';

export type WidgetTreeRow = {
  id: string;
  depth: number;
  node: WidgetTreeNode;
  hasChildren: boolean;
};

/**
 * Return ids for nodes that can show or hide descendants in the tree UI.
 *
 * Args:
 * - `root`: Root node from the bridge Widget Tree response. The function reads
 *   the original nested `children` arrays and does not change the tree.
 *
 * Returns:
 * A flat list of node ids. A node is included when its `children` array is not
 * empty, because that node can be expanded or collapsed by the web panel.
 *
 * Example:
 * `MaterialApp -> Scaffold -> Stack(children: [Text, Image])` returns ids for
 * `MaterialApp`, `Scaffold`, and `Stack`, but not for `Text` or `Image`.
 */
export function collectExpandableNodeIds(root: WidgetTreeNode): string[] {
  const ids: string[] = [];

  visitWidgetTree(root, (node) => {
    if (node.children.length > 0) {
      ids.push(node.id);
    }
  });

  return ids;
}

/**
 * Convert the nested Widget Tree into rows that the panel should render.
 *
 * This method:
 * 1. keeps one row for every visible `WidgetTreeNode`
 * 2. skips descendants of collapsed nodes
 * 3. calculates visual depth separately from original Flutter tree depth
 *
 * Args:
 * - `root`: Root node from the bridge Widget Tree response.
 * - `expandedNodeIds`: Node ids currently expanded in the panel. When a node id
 *   is absent, that node remains visible but its descendants are omitted.
 *
 * Returns:
 * A flat row list. Each row contains the original node, whether it has
 * children, and the visual `depth` used by CSS indentation.
 *
 * Example:
 * `MaterialApp -> WondersApp -> Container -> Stack(children: [Text, Image])`
 * renders `MaterialApp`, `WondersApp`, `Container`, and `Stack` at the same
 * visual depth. `Text` and `Image` are indented one level because `Stack` has
 * more than one child.
 */
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

/**
 * Add one node row and recursively add its expanded descendants.
 *
 * Args:
 * - `node`: Original Widget Tree node to add as one row.
 * - `depth`: Visual depth for this row. A single-child parent passes this same
 *   depth to its child; a parent with multiple children increments child depth.
 * - `expandedNodeIds`: Node ids currently expanded in the panel.
 * - `rows`: Output list that receives rows in display order.
 *
 * Returns:
 * Nothing. The function appends rows to `rows`.
 *
 * Example:
 * If `Container` has one child `Stack`, `Stack` receives the same `depth` as
 * `Container`. If `Stack` has children `Text` and `Image`, both receive
 * `depth + 1`.
 */
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
