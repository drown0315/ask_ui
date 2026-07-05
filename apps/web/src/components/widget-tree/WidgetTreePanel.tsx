import {
  useEffect,
  useMemo,
  useState,
  type CSSProperties,
  type KeyboardEvent,
} from 'react';
import { selectWidgetById } from '../../services/askUiBridgeClient';
import type {
  BridgeSessionState,
  WidgetTreeLoadState,
  WidgetTreeNode,
} from '../../types/bridgeSession';
import {
  buildVisibleWidgetTreeRows,
  collectExpandableNodeIds,
} from './widgetTreeRows';
import {
  collectAncestorNodeIds,
  findWidgetTreeMatches,
  getNextMatchIndex,
  getPreviousMatchIndex,
} from './widgetTreeSearch';

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

function WidgetTreeRows({
  root,
  selectedWidgetId,
  searchActiveWidgetId,
  searchExpandedAncestorIds,
  onSelectWidget,
}: {
  root: WidgetTreeNode;
  selectedWidgetId: string | null;
  searchActiveWidgetId: string | null;
  searchExpandedAncestorIds: string[];
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

  useEffect(() => {
    if (searchExpandedAncestorIds.length === 0) {
      return;
    }

    setExpandedNodeIds((current) => {
      const next = new Set(current);

      for (const nodeId of searchExpandedAncestorIds) {
        next.add(nodeId);
      }

      return next;
    });
  }, [searchExpandedAncestorIds]);

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
            } ${
              row.node.id === searchActiveWidgetId
                ? 'widget-tree-row-search-active'
                : ''
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
  bridgeSessionState,
  widgetTreeState,
  selectedWidgetId,
  searchActiveWidgetId,
  searchExpandedAncestorIds,
  onSelectWidget,
}: {
  bridgeSessionState: BridgeSessionState;
  widgetTreeState: WidgetTreeLoadState;
  selectedWidgetId: string | null;
  searchActiveWidgetId: string | null;
  searchExpandedAncestorIds: string[];
  onSelectWidget: (widgetId: string) => void;
}) {
  if (bridgeSessionState.status === 'incomplete') {
    return (
      <div className="widget-tree-state">
        <div className="widget-tree-state-title">Session parameters required</div>
        <div className="widget-tree-state-copy">
          Add {bridgeSessionState.missing.join(' and ')} to the page URL to
          create an Ask UI bridge session.
        </div>
      </div>
    );
  }

  if (bridgeSessionState.status === 'creating') {
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

  if (bridgeSessionState.status === 'error') {
    return (
      <div className="widget-tree-state widget-tree-state-error">
        <div className="widget-tree-state-title">Bridge session failed</div>
        <div className="widget-tree-state-copy">{bridgeSessionState.message}</div>
      </div>
    );
  }

  if (widgetTreeState.status === 'loading') {
    return (
      <div className="widget-tree-state">
        <div className="widget-tree-state-title">Fetching Widget Tree</div>
        <div className="widget-tree-state-copy">
          Session {bridgeSessionState.sessionId} is reading the Flutter Inspector
          summary tree.
        </div>
      </div>
    );
  }

  if (widgetTreeState.status === 'error') {
    return (
      <div className="widget-tree-state widget-tree-state-error">
        <div className="widget-tree-state-title">Widget Tree failed</div>
        <div className="widget-tree-state-copy">{widgetTreeState.message}</div>
      </div>
    );
  }

  return (
    <div className="widget-tree-root-list">
      <WidgetTreeRows
        root={widgetTreeState.root}
        selectedWidgetId={selectedWidgetId}
        searchActiveWidgetId={searchActiveWidgetId}
        searchExpandedAncestorIds={searchExpandedAncestorIds}
        onSelectWidget={onSelectWidget}
      />
    </div>
  );
}

export function WidgetTreePanel({
  bridgeSessionState,
  onRefresh,
  widgetTreeState,
}: {
  bridgeSessionState: BridgeSessionState;
  onRefresh: () => Promise<void>;
  widgetTreeState: WidgetTreeLoadState;
}) {
  const [selectedWidgetId, setSelectedWidgetId] = useState<string | null>(null);
  const [selectionError, setSelectionError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchActiveIndex, setSearchActiveIndex] = useState(-1);
  const searchMatches = useMemo(() => {
    if (widgetTreeState.status !== 'loaded') {
      return [];
    }

    return findWidgetTreeMatches(widgetTreeState.root, searchQuery);
  }, [searchQuery, widgetTreeState]);
  const searchActiveWidgetId =
    searchActiveIndex >= 0
      ? searchMatches[searchActiveIndex]?.nodeId ?? null
      : null;
  const searchExpandedAncestorIds = useMemo(
    () => collectAncestorNodeIds(searchMatches),
    [searchMatches],
  );
  const hasSearchQuery = searchQuery.trim().length > 0;
  const searchCounter =
    hasSearchQuery && searchMatches.length > 0
      ? `${searchActiveIndex + 1}/${searchMatches.length}`
      : hasSearchQuery
        ? `0/0`
        : '';
  const canRefresh =
    bridgeSessionState.status === 'ready' && widgetTreeState.status !== 'loading';

  useEffect(() => {
    setSelectedWidgetId(null);
    setSelectionError(null);
    setSearchActiveIndex(-1);
  }, [widgetTreeState]);

  async function handleSelectWidget(widgetId: string) {
    if (bridgeSessionState.status !== 'ready') {
      return;
    }

    const previousWidgetId = selectedWidgetId;
    setSelectedWidgetId(widgetId);
    setSelectionError(null);

    try {
      await selectWidgetById(bridgeSessionState.sessionId, widgetId);
    } catch (error: unknown) {
      setSelectedWidgetId(previousWidgetId);
      setSelectionError(
        error instanceof Error ? error.message : 'Failed to select Flutter widget',
      );
    }
  }

  function selectSearchMatch(nextIndex: number) {
    const match = searchMatches[nextIndex];

    if (!match) {
      setSearchActiveIndex(-1);
      return;
    }

    setSearchActiveIndex(nextIndex);
    void handleSelectWidget(match.nodeId);
  }

  function handleSearchQueryChange(query: string) {
    setSearchQuery(query);

    if (!query.trim() || widgetTreeState.status !== 'loaded') {
      setSearchActiveIndex(-1);
      return;
    }

    const matches = findWidgetTreeMatches(widgetTreeState.root, query);

    if (matches.length === 0) {
      setSearchActiveIndex(-1);
      return;
    }

    setSearchActiveIndex(0);
    void handleSelectWidget(matches[0].nodeId);
  }

  function handleSearchNext() {
    selectSearchMatch(
      getNextMatchIndex({
        currentIndex: searchActiveIndex,
        total: searchMatches.length,
      }),
    );
  }

  function handleSearchPrevious() {
    selectSearchMatch(
      getPreviousMatchIndex({
        currentIndex: searchActiveIndex,
        total: searchMatches.length,
      }),
    );
  }

  function handleRefresh() {
    void onRefresh().catch(() => undefined);
  }

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
          onClick={handleRefresh}
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
          onChange={(event) => handleSearchQueryChange(event.currentTarget.value)}
          onKeyDown={(event) => {
            if (event.key === 'Enter') {
              event.preventDefault();
              handleSearchNext();
            }
          }}
          placeholder="Search widgets"
          value={searchQuery}
          type="search"
        />
        {searchCounter ? (
          <span className="widget-tree-search-counter">{searchCounter}</span>
        ) : null}
        {hasSearchQuery ? (
          <div className="widget-tree-search-actions">
            <button
              aria-label="Previous widget tree search match"
              className="widget-tree-search-action widget-tree-search-action-previous"
              disabled={searchMatches.length === 0}
              onClick={handleSearchPrevious}
              title="Previous match"
              type="button"
            />
            <button
              aria-label="Next widget tree search match"
              className="widget-tree-search-action widget-tree-search-action-next"
              disabled={searchMatches.length === 0}
              onClick={handleSearchNext}
              title="Next match"
              type="button"
            />
          </div>
        ) : null}
      </div>
      {selectionError ? (
        <div className="widget-tree-selection-error">{selectionError}</div>
      ) : null}
      <WidgetTreeSessionState
        bridgeSessionState={bridgeSessionState}
        widgetTreeState={widgetTreeState}
        selectedWidgetId={selectedWidgetId}
        searchActiveWidgetId={searchActiveWidgetId}
        searchExpandedAncestorIds={searchExpandedAncestorIds}
        onSelectWidget={handleSelectWidget}
      />
    </aside>
  );
}
