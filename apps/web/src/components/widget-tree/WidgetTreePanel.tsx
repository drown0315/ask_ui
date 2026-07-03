import { useEffect, useMemo, useState, type CSSProperties } from 'react';
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

function isCustomWidget(label: string) {
  return /^[A-Z]/.test(label) && /^Wonder|Wonders|Home|Previous|Bottom/.test(label);
}

function matchesWidget(label: string, patterns: string[]) {
  return patterns.some((pattern) => label.includes(pattern));
}

function WidgetTreeRows({ root }: { root: WidgetTreeNode }) {
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
            className="widget-tree-row"
            key={row.id}
            role="treeitem"
            style={{ '--tree-depth': row.depth } as CSSProperties}
          >
            <button
              aria-label={
                row.hasChildren
                  ? `${isExpanded ? 'Collapse' : 'Expand'} ${row.node.label}`
                  : undefined
              }
              className="widget-tree-toggle"
              disabled={!row.hasChildren}
              onClick={() => {
                if (row.hasChildren) {
                  toggleNode(row.node.id);
                }
              }}
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

function WidgetTreeSessionState({ state }: { state: BridgeSessionState }) {
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
      <WidgetTreeRows root={state.widgetTree.root} />
    </div>
  );
}

export function WidgetTreePanel({
  bridgeSessionState,
}: {
  bridgeSessionState: BridgeSessionState;
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
          disabled
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
      <WidgetTreeSessionState state={bridgeSessionState} />
    </aside>
  );
}
