export function TopBar() {
  return (
    <header className="top-bar">
      <div className="top-bar-brand">
        <div className="brand-mark" aria-hidden="true" />
        <span>Ask UI</span>
      </div>

      <div className="top-bar-session" aria-label="Target device status">
        <span className="status-dot" aria-hidden="true" />
        <span>iPhone 15 Pro</span>
        <span className="session-muted">Flutter debug</span>
      </div>

      <div className="top-bar-actions" aria-label="Workbench actions">
        <button className="toolbar-button toolbar-button-active" type="button">
          Select Widget
        </button>
        <button className="toolbar-button" type="button">
          Hot Reload
        </button>
        <button className="toolbar-button toolbar-button-subtle" type="button">
          Hot Restart
        </button>
      </div>
    </header>
  );
}
