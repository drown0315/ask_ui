import {
  useEffect,
  useMemo,
  useState,
  type CSSProperties,
  type KeyboardEvent,
} from 'react';
import type { BridgeSessionState, WidgetTreeNode } from '../../types/bridgeSession';
import {
  buildVisibleWidgetTreeRows,
  collectExpandableNodeIds,
} from './widgetTreeRows';

type WidgetTreeIconKind =
  | 'app'
  | 'layout'
  | 'gesture'
  | 'visual'
  | 'animation'
  | 'text'
  | 'custom'
  | 'widget';

/**
 * Choose the icon shown beside one Widget Tree row label.
 *
 * This method:
 * 1. checks for likely project widgets first
 * 2. matches common Flutter widget label fragments to broad UI categories
 * 3. falls back to a neutral widget icon when no rule matches
 *
 * Args:
 * - `label`: Widget label from the bridge response. It is usually the Flutter
 *   Inspector `description`, such as `Scaffold`, `GestureDetector`, or
 *   `WonderIllustration`.
 *
 * Returns:
 * A small icon record containing the category key, rendered glyph, and tooltip
 * text for the row.
 *
 * Example:
 * `GestureDetector` returns the interaction icon, `SizedBox.expand` returns
 * the layout icon, and `WonderIllustration` returns the project widget icon.
 */
function getWidgetTreeIcon(label: string): {
  kind: WidgetTreeIconKind;
  glyph: string;
  title: string;
} {
  if (isCustomWidget(label)) {
    return {
      kind: 'custom',
      glyph: '◆',
      title: 'Project widget',
    };
  }

  if (matchesWidget(label, ['MaterialApp', 'Scaffold', 'Theme', '[root]'])) {
    return {
      kind: 'app',
      glyph: '□',
      title: 'App structure widget',
    };
  }

  if (
    matchesWidget(label, [
      'Text',
      'RichText',
      'DefaultTextStyle',
      'EditableText',
    ])
  ) {
    return {
      kind: 'text',
      glyph: 'T',
      title: 'Text widget',
    };
  }

  if (
    matchesWidget(label, [
      'Gesture',
      'Listener',
      'TrackpadListener',
      'Tap',
      'Pointer',
    ])
  ) {
    return {
      kind: 'gesture',
      glyph: '⌁',
      title: 'Interaction widget',
    };
  }

  if (
    matchesWidget(label, [
      'Image',
      'Opacity',
      'Transform',
      'Clip',
      'DecoratedBox',
      'FractionalTranslation',
    ])
  ) {
    return {
      kind: 'visual',
      glyph: '▧',
      title: 'Visual widget',
    };
  }

  if (
    matchesWidget(label, [
      'Animated',
      'Animation',
      'Animate',
      'ValueListenableBuilder',
    ])
  ) {
    return {
      kind: 'animation',
      glyph: '◇',
      title: 'Animation widget',
    };
  }

  if (
    matchesWidget(label, [
      'Container',
      'Stack',
      'Column',
      'Row',
      'Padding',
      'SizedBox',
      'Center',
      'Positioned',
      'LayoutBuilder',
      'KeyedSubtree',
      'ScrollConfiguration',
    ])
  ) {
    return {
      kind: 'layout',
      glyph: '▣',
      title: 'Layout widget',
    };
  }

  return {
    kind: 'widget',
    glyph: '·',
    title: 'Widget',
  };
}

/**
 * Return whether a widget label looks like a project widget.
 *
 * Args:
 * - `label`: Widget label from the bridge response. The current web payload
 *   does not include `createdByLocalProject` or creation location, so this
 *   function can only use the label text.
 *
 * Returns:
 * `true` for known Ask UI demo app naming patterns, otherwise `false`.
 *
 * Example:
 * `WonderIllustration` and `HomeScreen` return `true`; `Container` returns
 * `false`.
 */
function isCustomWidget(label: string) {
  return /^[A-Z]/.test(label) && /^Wonder|Wonders|Home|Previous|Bottom/.test(label);
}

/**
 * Return whether a widget label contains any category pattern.
 *
 * Args:
 * - `label`: Widget label from the bridge response.
 * - `patterns`: Case-sensitive fragments that identify one broad widget
 *   category. For example, `Gesture` matches `GestureDetector`.
 *
 * Returns:
 * `true` when at least one pattern appears in the label.
 *
 * Example:
 * `matchesWidget('DefaultTextStyle', ['Text', 'RichText'])` returns `true`.
 */
function matchesWidget(label: string, patterns: string[]) {
  return patterns.some((pattern) => label.includes(pattern));
}

function WidgetTreeRows({
  root,
  selectedWidgetId,
  onSelectWidget,
}: {
  root: WidgetTreeNode;
  selectedWidgetId: string | null;
  onSelectWidget: (widgetId: string) => void;
}) {
  const allExpandableNodeIds = useMemo(() => collectExpandableNodeIds(root), [root]);
  const [expandedNodeIds, setExpandedNodeIds] = useState(
    () => new Set(allExpandableNodeIds),
  );
  const rows = useMemo(
    () =>
      buildVisibleWidgetTreeRows({
        root,
        expandedNodeIds,
      }),
    [expandedNodeIds, root],
  );

  useEffect(() => {
    setExpandedNodeIds(new Set(allExpandableNodeIds));
  }, [allExpandableNodeIds]);

  function toggleNode(nodeId: string) {
    setExpandedNodeIds((current) => {
      const next = new Set(current);

      if (next.has(nodeId)) {
        next.delete(nodeId);
      } else {
        next.add(nodeId);
      }

      return next;
    });
  }

  return (
    <div className="widget-tree-flat-list" role="tree">
      {rows.map((row) => {
        const isExpanded = row.hasChildren && expandedNodeIds.has(row.node.id);
        const icon = getWidgetTreeIcon(row.node.label);

        return (
          <div
            aria-expanded={row.hasChildren ? isExpanded : undefined}
            aria-level={row.depth + 1}
            aria-selected={row.node.id === selectedWidgetId}
            className={`widget-tree-row ${
              row.node.id === selectedWidgetId ? 'widget-tree-row-selected' : ''
            }`}
            key={row.id}
            onClick={() => onSelectWidget(row.node.id)}
            onKeyDown={(event: KeyboardEvent<HTMLDivElement>) => {
              if (event.key === 'Enter' || event.key === ' ') {
                event.preventDefault();
                onSelectWidget(row.node.id);
              }
            }}
            role="treeitem"
            style={{ '--tree-depth': row.depth } as CSSProperties}
            tabIndex={0}
          >
            <button
              aria-label={
                row.hasChildren
                  ? `${isExpanded ? 'Collapse' : 'Expand'} ${row.node.label}`
                  : undefined
              }
              className="widget-tree-toggle"
              disabled={!row.hasChildren}
              onClick={(event) => {
                event.stopPropagation();
                if (row.hasChildren) {
                  toggleNode(row.node.id);
                }
              }}
              onPointerDown={(event) => event.stopPropagation()}
              type="button"
            >
              {row.hasChildren ? (isExpanded ? '▾' : '▸') : ''}
            </button>
            <span className="widget-tree-branch" aria-hidden="true" />
            <span
              aria-label={icon.title}
              className={`widget-tree-type-icon widget-tree-type-icon-${icon.kind}`}
              title={icon.title}
            >
              {icon.glyph}
            </span>
            <span className="widget-tree-label" title={row.node.label}>
              {row.node.label}
            </span>
          </div>
        );
      })}
    </div>
  );
}

function WidgetTreeSessionState({
  state,
  selectedWidgetId,
  onSelectWidget,
}: {
  state: BridgeSessionState;
  selectedWidgetId: string | null;
  onSelectWidget: (widgetId: string) => void;
}) {
  if (state.status === 'incomplete') {
    return (
      <div className="widget-tree-state">
        <div className="widget-tree-state-title">Session parameters required</div>
        <div className="widget-tree-state-copy">
          Add {state.missing.join(' and ')} to the page URL to create an Ask UI
          bridge session.
        </div>
      </div>
    );
  }

  if (state.status === 'creating') {
    return (
      <div className="widget-tree-state">
        <div className="widget-tree-state-title">Creating bridge session</div>
        <div className="widget-tree-state-copy">
          Ask UI is sending the Flutter VM Service URI and project root to the
          local bridge.
        </div>
      </div>
    );
  }

  if (state.status === 'error') {
    return (
      <div className="widget-tree-state widget-tree-state-error">
        <div className="widget-tree-state-title">Bridge session failed</div>
        <div className="widget-tree-state-copy">{state.message}</div>
      </div>
    );
  }

  if (state.widgetTree.status === 'loading') {
    return (
      <div className="widget-tree-state">
        <div className="widget-tree-state-title">Fetching Widget Tree</div>
        <div className="widget-tree-state-copy">
          Session {state.sessionId} is reading the Flutter Inspector summary tree.
        </div>
      </div>
    );
  }

  if (state.widgetTree.status === 'error') {
    return (
      <div className="widget-tree-state widget-tree-state-error">
        <div className="widget-tree-state-title">Widget Tree failed</div>
        <div className="widget-tree-state-copy">{state.widgetTree.message}</div>
      </div>
    );
  }

  return (
    <div className="widget-tree-root-list">
      <WidgetTreeRows
        root={state.widgetTree.root}
        selectedWidgetId={selectedWidgetId}
        onSelectWidget={onSelectWidget}
      />
    </div>
  );
}

export function WidgetTreePanel({
  bridgeSessionState,
  canRefresh,
  selectedWidgetId,
  selectionError,
  onRefresh,
  onSelectWidget,
}: {
  bridgeSessionState: BridgeSessionState;
  canRefresh: boolean;
  selectedWidgetId: string | null;
  selectionError: string | null;
  onRefresh: () => void;
  onSelectWidget: (widgetId: string) => void;
}) {
  return (
    <aside className="workbench-panel widget-tree-panel">
      <div className="widget-tree-header">
        <div>
          <div className="widget-tree-title">Widget Tree</div>
          <div className="widget-tree-subtitle">Flutter Inspector summary</div>
        </div>
        <button
          aria-label="Refresh widget tree"
          className="widget-tree-icon-button"
          disabled={!canRefresh}
          onClick={onRefresh}
          title="Refresh widget tree"
          type="button"
        >
          ↻
        </button>
      </div>
      <div className="widget-tree-search">
        <span aria-hidden="true" className="widget-tree-search-icon">
          ⌕
        </span>
        <input
          aria-label="Search widget tree"
          className="widget-tree-search-input"
          placeholder="Search widgets"
          type="search"
        />
      </div>
      {selectionError ? (
        <div className="widget-tree-selection-error">{selectionError}</div>
      ) : null}
      <WidgetTreeSessionState
        state={bridgeSessionState}
        selectedWidgetId={selectedWidgetId}
        onSelectWidget={onSelectWidget}
      />
    </aside>
  );
}
