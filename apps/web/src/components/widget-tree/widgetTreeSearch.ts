import type { WidgetTreeNode } from '../../types/bridgeSession';

export type WidgetTreeSearchMatch = {
  nodeId: string;
  label: string;
  ancestorNodeIds: string[];
};

/**
 * Find Widget Tree nodes whose labels match a search query.
 *
 * Args:
 * - `root`: Root node from the current Widget Tree snapshot.
 * - `query`: User-entered search text. Empty or whitespace-only queries return
 *   no matches. Matching is case-insensitive and uses substring containment.
 *
 * Returns:
 * Matches in original tree traversal order. Each match contains the node id,
 * label, and ancestor ids needed to expand collapsed parents before rendering
 * the highlighted match.
 *
 * Example:
 * Searching `column` in `MaterialApp -> Column -> Container -> Column`
 * returns both Column nodes. The nested match includes `MaterialApp`, the
 * first `Column`, and `Container` as ancestors.
 */
export function findWidgetTreeMatches(
  root: WidgetTreeNode,
  query: string,
): WidgetTreeSearchMatch[] {
  const normalizedQuery = query.trim().toLowerCase();

  if (!normalizedQuery) {
    return [];
  }

  const matches: WidgetTreeSearchMatch[] = [];

  visitWidgetTreeForSearch(root, [], (node, ancestorNodeIds) => {
    if (node.label.toLowerCase().includes(normalizedQuery)) {
      matches.push({
        nodeId: node.id,
        label: node.label,
        ancestorNodeIds,
      });
    }
  });

  return matches;
}

/**
 * Return the next active match index for Enter-key navigation.
 *
 * Args:
 * - `currentIndex`: Currently highlighted match index. `-1` means no active
 *   match has been chosen yet.
 * - `total`: Number of matches for the current query.
 *
 * Returns:
 * The next match index, wrapping from the last match back to zero. Returns
 * `-1` when there are no matches.
 *
 * Example:
 * `currentIndex=2` and `total=3` returns `0`.
 */
export function getNextMatchIndex({
  currentIndex,
  total,
}: {
  currentIndex: number;
  total: number;
}) {
  if (total <= 0) {
    return -1;
  }

  return (currentIndex + 1) % total;
}

/**
 * Return the previous active match index for search navigation.
 *
 * Args:
 * - `currentIndex`: Currently highlighted match index. `-1` means no active
 *   match has been chosen yet.
 * - `total`: Number of matches for the current query.
 *
 * Returns:
 * The previous match index, wrapping from zero to the last match. Returns `-1`
 * when there are no matches.
 *
 * Example:
 * `currentIndex=0` and `total=3` returns `2`.
 */
export function getPreviousMatchIndex({
  currentIndex,
  total,
}: {
  currentIndex: number;
  total: number;
}) {
  if (total <= 0) {
    return -1;
  }

  if (currentIndex < 0) {
    return total - 1;
  }

  return (currentIndex - 1 + total) % total;
}

/**
 * Collect parent ids that must be expanded for search matches to be visible.
 *
 * Args:
 * - `matches`: Matches returned by `findWidgetTreeMatches`.
 *
 * Returns:
 * Unique ancestor ids in first-seen order. The caller can merge these ids into
 * the tree's expanded set before rendering a highlighted match.
 *
 * Example:
 * Two matches under the same `Column` include that `Column` only once.
 */
export function collectAncestorNodeIds(
  matches: WidgetTreeSearchMatch[],
): string[] {
  const ancestorNodeIds: string[] = [];
  const seen = new Set<string>();

  for (const match of matches) {
    for (const nodeId of match.ancestorNodeIds) {
      if (!seen.has(nodeId)) {
        seen.add(nodeId);
        ancestorNodeIds.push(nodeId);
      }
    }
  }

  return ancestorNodeIds;
}

function visitWidgetTreeForSearch(
  node: WidgetTreeNode,
  ancestorNodeIds: string[],
  visit: (node: WidgetTreeNode, ancestorNodeIds: string[]) => void,
) {
  visit(node, ancestorNodeIds);

  for (const child of node.children) {
    visitWidgetTreeForSearch(child, [...ancestorNodeIds, node.id], visit);
  }
}
