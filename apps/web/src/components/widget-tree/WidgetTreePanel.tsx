import type { BridgeSessionState } from '../../types/bridgeSession';

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

  return (
    <div className="widget-tree-state">
      <div className="widget-tree-state-title">Bridge session ready</div>
      <div className="widget-tree-state-copy">
        Session {state.sessionId} is ready. Real Flutter Widget Tree fetching is
        handled by the next integration slice.
      </div>
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
          <div className="widget-tree-subtitle">Bridge session bootstrap</div>
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
