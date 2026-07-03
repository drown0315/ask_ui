import type { CSSProperties } from 'react';
import type { BridgeSessionState, WidgetTreeNode } from '../../types/bridgeSession';

function WidgetTreeNodeRow({
  node,
  depth,
}: {
  node: WidgetTreeNode;
  depth: number;
}) {
  return (
    <li>
      <div
        className="widget-tree-row"
        style={{ '--tree-depth': depth } as CSSProperties}
      >
        <span className="widget-tree-toggle" aria-hidden="true">
          {node.children.length > 0 ? '▾' : ''}
        </span>
        <span className="widget-tree-branch" aria-hidden="true" />
        <span className="widget-tree-badge" aria-hidden="true">
          {node.label.slice(0, 1).toUpperCase()}
        </span>
        <span className="widget-tree-label" title={node.label}>
          {node.label}
        </span>
      </div>
      {node.children.length > 0 ? (
        <ul className="widget-tree-list">
          {node.children.map((child) => (
            <WidgetTreeNodeRow key={child.id} node={child} depth={depth + 1} />
          ))}
        </ul>
      ) : null}
    </li>
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
    <ul className="widget-tree-list widget-tree-root-list">
      <WidgetTreeNodeRow node={state.widgetTree.root} depth={0} />
    </ul>
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
